import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../core/theme/app_colors.dart';
import '../data/repositories/settings_repository.dart';
import '../services/ad_config_service.dart';

class UnifiedBannerAdSlot extends StatefulWidget {
  final Color backgroundColor;
  final bool isVisible;
  final AdSize adSize;
  final bool showDismissButton;
  final AlignmentGeometry alignment;

  /// Which remote-config-driven ad unit this slot loads. Defaults to the
  /// floating banner unit; the hub slot passes the hub-specific one.
  final ValueNotifier<String> adUnitNotifier;

  /// Remote-config-driven master switch for this slot (defaults to the
  /// floating banner enable flag; the hub slot passes the hub-specific one).
  /// When `false`, the slot loads nothing and renders nothing; flipping it
  /// back on reloads the banner.
  final ValueNotifier<bool> enabledNotifier;

  /// SharedPreferences key used to remember that the user dismissed this slot.
  /// When set, dismissing the banner persists across app restarts so it does
  /// not reopen. When null, the dismiss is in-memory only.
  final String? dismissKey;

  UnifiedBannerAdSlot({
    super.key,
    this.backgroundColor = AppColors.surface,
    this.isVisible = true,
    this.adSize = AdSize.largeBanner,
    this.showDismissButton = true,
    this.alignment = Alignment.centerLeft,
    ValueNotifier<String>? adUnitNotifier,
    ValueNotifier<bool>? enabledNotifier,
    this.dismissKey,
  })  : adUnitNotifier =
            adUnitNotifier ?? AdConfigService.instance.bannerAdUnitId,
        enabledNotifier =
            enabledNotifier ?? AdConfigService.instance.bannerEnabled;

  @override
  State<UnifiedBannerAdSlot> createState() => _UnifiedBannerAdSlotState();
}

class _UnifiedBannerAdSlotState extends State<UnifiedBannerAdSlot>
    with WidgetsBindingObserver {
  BannerAd? _bannerAd;
  Widget? _adWidget;
  bool _adLoaded = false;
  bool _isDismissed = false;
  bool _isAppBackgrounded = false;
  DateTime? _backgroundedAt;
  Timer? _retryTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.adUnitNotifier.addListener(_onAdConfigChanged);
    widget.enabledNotifier.addListener(_onEnabledChanged);
    _loadBannerAd();
    _restoreDismissed();
  }

  /// Applies the persisted "dismissed" flag so a closed banner stays closed
  /// after an app restart. Loaded asynchronously; the slot is hidden the moment
  /// the value lands.
  Future<void> _restoreDismissed() async {
    final key = widget.dismissKey;
    if (key == null) return;
    final dismissed = await SettingsRepository.getBannerDismissed(key);
    if (dismissed && mounted) {
      setState(() => _isDismissed = true);
    }
  }

  /// Remote Config delivered a different (e.g. production) banner unit:
  /// dispose the ad loaded with the previous unit and reload with the new one.
  void _onAdConfigChanged() {
    if (!mounted) return;
    _bannerAd?.dispose();
    _bannerAd = null;
    setState(() {
      _adLoaded = false;
      _adWidget = null;
    });
    _loadBannerAd();
  }

  /// Remote Config flipped this slot's master switch. Off: unload the ad and
  /// render nothing. Back on: reload the banner.
  void _onEnabledChanged() {
    if (!mounted) return;
    final enabled = widget.enabledNotifier.value;
    _retryTimer?.cancel();
    if (!enabled) {
      _bannerAd?.dispose();
      _bannerAd = null;
      setState(() {
        _adLoaded = false;
        _adWidget = null;
      });
      return;
    }
    if (!_adLoaded && !_isDismissed) {
      _loadBannerAd();
    }
  }

  /// Time spent in the background that counts as a new session. Once exceeded,
  /// a banner dismissed earlier in the session is shown again on return.
  static const Duration _sessionRefreshAfter = Duration(hours: 2);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _backgroundedAt ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final backgroundedAt = _backgroundedAt;
      _backgroundedAt = null;
      if (backgroundedAt != null &&
          DateTime.now().difference(backgroundedAt) >= _sessionRefreshAfter) {
        _isDismissed = false;
      }
    }
    final bg = state == AppLifecycleState.paused;
    if (bg != _isAppBackgrounded) {
      setState(() => _isAppBackgrounded = bg);
    }
  }

  void _loadBannerAd() {
    _bannerAd = BannerAd(
      adUnitId: widget.adUnitNotifier.value,
      size: widget.adSize,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted) return;
          _adWidget = AdWidget(key: ValueKey(ad.hashCode), ad: ad as BannerAd);
          setState(() => _adLoaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          // Logged so Xcode/Console shows WHY the banner is missing
          // (no-fill, wrong app id, offline...). Retry every 30s.
          debugPrint('MrPlay banner failed to load: '
              'code=${error.code} domain=${error.domain} message=${error.message}');
          if (!mounted) return;
          setState(() => _bannerAd = null);
          _retryTimer?.cancel();
          _retryTimer = Timer(const Duration(seconds: 30), () {
            if (mounted &&
                widget.enabledNotifier.value &&
                !_adLoaded &&
                !_isDismissed &&
                !_isAppBackgrounded &&
                widget.isVisible) {
              _loadBannerAd();
            }
          });
        },
        // A banner click opens the advertiser's page in the browser (standard
        // AdMob behaviour). Treat that like backgrounding so the banner doesn't
        // immediately re-show/re-trigger while the user is still returning.
        onAdOpened: (ad) {
          if (mounted) setState(() => _isAppBackgrounded = true);
        },
        onAdClosed: (ad) {
          if (mounted) setState(() => _isAppBackgrounded = false);
        },
      ),
    )..load();
  }

  void _handleDismiss() {
    setState(() => _isDismissed = true);
    final key = widget.dismissKey;
    if (key != null) {
      SettingsRepository.setBannerDismissed(key, true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.adUnitNotifier.removeListener(_onAdConfigChanged);
    widget.enabledNotifier.removeListener(_onEnabledChanged);
    _retryTimer?.cancel();
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabledNotifier.value ||
        !_adLoaded ||
        _bannerAd == null ||
        _isDismissed ||
        !widget.isVisible ||
        _isAppBackgrounded) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Align(
        alignment: widget.alignment,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: widget.adSize.width.toDouble(),
            height: widget.adSize.height.toDouble(),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Container(
                    color: const Color(0xFF2D2D2D).withValues(alpha: 0.92),
                    child: Center(child: _adWidget!),
                  ),
                ),
                if (widget.showDismissButton)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: _handleDismiss,
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFF2D2D2D).withValues(alpha: 0.90),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.15),
                            width: 1,
                          ),
                        ),
                        child: const Icon(
                          Icons.close,
                          size: 16,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
