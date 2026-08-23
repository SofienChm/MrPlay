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
  BannerAd? _bannerAd;
  Widget? _adWidget;
  bool _adLoaded = false;
  bool _isDismissed = false;
  bool _isAppBackgrounded = false;
  Timer? _retryTimer;

  /// The effective unit ID: explicit override wins, otherwise the manual
  /// [AdConfig] unit for this slot.
  String get _resolvedAdUnitId {
    if (widget.adUnitId != null) return widget.adUnitId!;
    return widget.slot == BannerSlot.hub
        ? AdConfig.hubBannerAdUnitId
        : AdConfig.bannerAdUnitId;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadBannerAd();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final bg = state == AppLifecycleState.paused;
    if (bg != _isAppBackgrounded) {
      setState(() => _isAppBackgrounded = bg);
    }
  }

  void _loadBannerAd() {
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
          _adWidget = AdWidget(key: ValueKey(ad.hashCode), ad: ad as BannerAd);
          setState(() => _adLoaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          // Logged so Xcode/Console shows WHY the banner is missing
          // (no-fill, wrong app id, offline...). Retry every 30s.
          debugPrint('MrPlay banner failed to load '
              '($unitId): '
              'code=${error.code} domain=${error.domain} message=${error.message}');
          if (!mounted) return;
          setState(() => _bannerAd = null);
          _retryTimer?.cancel();
          _retryTimer = Timer(const Duration(seconds: 30), () {
            if (mounted && !_adLoaded) _loadBannerAd();
          });
        },
      ),
    )..load();
  }

  void _handleDismiss() {
    // Session-scoped dismissal: the banner stays hidden for the rest of the
    // app session (across both tabs) instead of auto-reappearing after a
    // few minutes. Re-presenting an ad the user explicitly closed during the
    // same session is the pattern AdMob flags as intrusive.
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