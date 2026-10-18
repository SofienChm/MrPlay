import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../ad_config.dart';

/// Native Advanced ad (small template) used on the hub page. Collapses to
/// nothing while no ad is loaded and retries with capped backoff.
class NativeAdSlot extends StatefulWidget {
  final String? adUnitId;
  final double height;

  const NativeAdSlot({
    super.key,
    this.adUnitId,
    this.height = 100,
  });

  @override
  State<NativeAdSlot> createState() => _NativeAdSlotState();
}

class _NativeAdSlotState extends State<NativeAdSlot>
    with WidgetsBindingObserver {
  static const Duration _initialRetryDelay = Duration(seconds: 30);
  static const Duration _maxRetryDelay = Duration(minutes: 5);

  NativeAd? _nativeAd;
  bool _adLoaded = false;
  bool _isAppBackgrounded = false;
  int _retryCount = 0;
  Timer? _retryTimer;
  String? _lastError; // TEMP debug: remove once native ad is confirmed working

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadAd();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final bg = state == AppLifecycleState.paused;
    if (bg == _isAppBackgrounded) return;
    setState(() => _isAppBackgrounded = bg);
    if (bg) {
      _retryTimer?.cancel();
    } else if (!_adLoaded && _nativeAd == null) {
      _retryCount = 0;
      _loadAd();
    }
  }

  void _loadAd() {
    if (_isAppBackgrounded) return;

    _nativeAd?.dispose();
    final unitId = widget.adUnitId ?? AdConfig.hubNativeAdUnitId;
    _nativeAd = NativeAd(
      adUnitId: unitId,
      request: const AdRequest(),
      nativeTemplateStyle: NativeTemplateStyle(
        templateType: TemplateType.small,
        mainBackgroundColor: const Color(0xFF2D2D2D),
        cornerRadius: 12,
        callToActionTextStyle: NativeTemplateTextStyle(
          textColor: Colors.white,
          backgroundColor: const Color(0xFF2196F3),
          size: 14,
        ),
        primaryTextStyle: NativeTemplateTextStyle(
          textColor: Colors.white,
          size: 14,
        ),
        secondaryTextStyle: NativeTemplateTextStyle(
          textColor: Colors.white70,
          size: 12,
        ),
        tertiaryTextStyle: NativeTemplateTextStyle(
          textColor: Colors.white54,
          size: 12,
        ),
      ),
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          if (!mounted) return;
          _retryCount = 0;
          setState(() => _adLoaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          debugPrint('MrPlay native failed to load ($unitId): '
              'code=${error.code} message=${error.message}');
          if (!mounted) return;
          setState(() {
            _nativeAd = null;
            _adLoaded = false;
            _lastError = 'Native ad error ${error.code}: ${error.message}';
          });
          if (_isAppBackgrounded) return;
          _retryTimer?.cancel();
          final delay = _initialRetryDelay * (1 << _retryCount.clamp(0, 4));
          _retryCount++;
          _retryTimer = Timer(
            delay > _maxRetryDelay ? _maxRetryDelay : delay,
            () {
              if (mounted && !_adLoaded) _loadAd();
            },
          );
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _retryTimer?.cancel();
    _nativeAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_adLoaded || _nativeAd == null || _isAppBackgrounded) {
      if (_lastError != null && !_isAppBackgrounded) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(_lastError!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 11)),
        );
      }
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: widget.height,
          width: double.infinity,
          child: AdWidget(ad: _nativeAd!),
        ),
      ),
    );
  }
}
