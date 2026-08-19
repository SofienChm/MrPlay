import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../ad_config.dart';
import '../core/theme/app_colors.dart';

class UnifiedBannerAdSlot extends StatefulWidget {
  final Color backgroundColor;
  final bool isVisible;

  const UnifiedBannerAdSlot({
    super.key,
    this.backgroundColor = AppColors.surface,
    this.isVisible = true,
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
  Timer? _reappearTimer;
  Timer? _retryTimer;

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
    _bannerAd = BannerAd(
      adUnitId: AdConfig.bannerAdUnitId,
      size: AdSize.largeBanner,
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
            if (mounted && !_adLoaded) _loadBannerAd();
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
    _reappearTimer?.cancel();
    _reappearTimer = Timer(
      const Duration(minutes: 5),
      () {
        if (!mounted) return;
        setState(() => _isDismissed = false);
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reappearTimer?.cancel();
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
      padding: const EdgeInsets.fromLTRB(8, 6, 16, 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 320,
            height: 100,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Container(
                    color: const Color(0xFF2D2D2D).withValues(alpha: 0.92),
                    child: Center(child: _adWidget!),
                  ),
                ),
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
