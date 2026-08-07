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
    if (!_adLoaded || _bannerAd == null || _isDismissed || !widget.isVisible || _isAppBackgrounded) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 0, 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 320,
                height: 100,
                child: Container(
                  color: Colors.black.withValues(alpha: 0.8),
                  child: Center(child: _adWidget!),
                ),
              ),
            ),
            Positioned(
              top: -20,
              right: -20,
              child: GestureDetector(
                onTap: _handleDismiss,
                hitTestBehavior: HitTestBehavior.opaque,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: Colors.white24,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close,
                    size: 22,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
