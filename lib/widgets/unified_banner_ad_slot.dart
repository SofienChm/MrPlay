import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../core/theme/app_colors.dart';
import '../ad_config.dart';

/// Which logical ad slot this widget serves. Determines which [AdConfig] unit
/// supplies the ad unit ID when none is passed explicitly.
enum BannerSlot { floating, hub }

class UnifiedBannerAdSlot extends StatefulWidget {
  final String? adUnitId;
  final BannerSlot slot;
  final AdSize adSize;
  final Color backgroundColor;
  final bool isVisible;
  final bool showDismissButton;
  final Alignment alignment;

  const UnifiedBannerAdSlot({
    super.key,
    this.adUnitId,
    this.slot = BannerSlot.floating,
    this.adSize = AdSize.largeBanner,
    this.backgroundColor = AppColors.surface,
    this.isVisible = true,
    this.showDismissButton = true,
    this.alignment = Alignment.center,
  });

  @override
  State<UnifiedBannerAdSlot> createState() => _UnifiedBannerAdSlotState();
}

class _UnifiedBannerAdSlotState extends State<UnifiedBannerAdSlot>
    with WidgetsBindingObserver {
  static const Duration _initialRetryDelay = Duration(seconds: 30);
  static const int _maxRetries = 3;

  BannerAd? _bannerAd;
  Widget? _adWidget;
  bool _adLoaded = false;
  bool _isDismissed = false;
  bool _isAppBackgrounded = false;
  int _retryCount = 0;
  Timer? _retryTimer;

  /// The effective unit ID: explicit override wins, otherwise the manual
  /// [AdConfig] unit for this slot.
  String get _resolvedAdUnitId {
    if (widget.adUnitId != null) return widget.adUnitId!;
    return widget.slot == BannerSlot.hub
        ? AdConfig.hubBannerAdUnitId
        : AdConfig.bannerAdUnitId;
  }

  /// True while the slot is on screen and eligible to load ads.
  bool get _isActive => widget.isVisible && !_isDismissed && !_isAppBackgrounded;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadBannerAd();
  }

  @override
  void didUpdateWidget(UnifiedBannerAdSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    final wasActive =
        oldWidget.isVisible && !_isDismissed && !_isAppBackgrounded;
    if (!wasActive && _isActive) {
      if (!_adLoaded && _bannerAd == null) _loadBannerAd();
    } else if (wasActive && !_isActive) {
      _retryTimer?.cancel();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final bg = state == AppLifecycleState.paused;
    if (bg != _isAppBackgrounded) {
      setState(() => _isAppBackgrounded = bg);
      if (bg) {
        _retryTimer?.cancel();
      } else if (!_adLoaded && _bannerAd == null) {
        _loadBannerAd();
      }
    }
  }

  void _loadBannerAd({bool isRetry = false}) {
    if (!_isActive) return;
    if (!isRetry) _retryCount = 0;

    _bannerAd?.dispose();
    final unitId = _resolvedAdUnitId;
    debugPrint('MrPlay banner loading from $unitId '
        '(slot=${widget.slot.name})');
    _bannerAd = BannerAd(
      adUnitId: unitId,
      size: widget.adSize,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted) return;
          _retryCount = 0;
          _adWidget = AdWidget(key: ValueKey(ad.hashCode), ad: ad as BannerAd);
          setState(() => _adLoaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          debugPrint('MrPlay banner failed to load '
              '($unitId): '
              'code=${error.code} domain=${error.domain} message=${error.message}');
          if (!mounted) return;
          setState(() => _bannerAd = null);
          if (!_isActive) return;
          if (_retryCount >= _maxRetries) {
            debugPrint('MrPlay banner giving up on $unitId after '
                '$_maxRetries retries');
            return;
          }
          _retryTimer?.cancel();
          final delay = Duration(
              seconds: _initialRetryDelay.inSeconds * (1 << _retryCount));
          _retryCount++;
          _retryTimer = Timer(delay, () {
            if (mounted && _isActive && !_adLoaded) {
              _loadBannerAd(isRetry: true);
            }
          });
        },
      ),
    )..load();
  }

  void _handleDismiss() {
    _retryTimer?.cancel();
    _bannerAd?.dispose();
    _bannerAd = null;
    setState(() => _isDismissed = true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _retryTimer?.cancel();
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_adLoaded ||
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
                          color: const Color(0xFF2D2D2D).withValues(alpha: 0.90),
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