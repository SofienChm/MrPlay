import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../ad_config.dart';

/// Floating Native Advanced ad shown over the webview (browse page and the
/// expanded video tab), in the old floating banner's spot. Uses the hub's
/// `mrplayNative` layout. The user can close it; a new video tab
/// ([showToken] changes) brings it back with a fresh ad (at most once a
/// minute). The close button sits above the ad so it never covers AdChoices.
class FloatingNativeAdSlot extends StatefulWidget {
  final bool isVisible;
  final Object? showToken;

  const FloatingNativeAdSlot({
    super.key,
    required this.isVisible,
    this.showToken,
  });

  @override
  State<FloatingNativeAdSlot> createState() => _FloatingNativeAdSlotState();
}

class _FloatingNativeAdSlotState extends State<FloatingNativeAdSlot>
    with WidgetsBindingObserver {
  static const Duration _initialRetryDelay = Duration(seconds: 30);
  static const Duration _maxRetryDelay = Duration(minutes: 5);
  static const Duration _minRefreshInterval = Duration(seconds: 60);
  static const double _adHeight = 136;
  static const double _maxAdWidth = 320;
  // Left gutter + the video tab's right-hand button column (16 + 40 + gap).
  static const double _reservedWidth = 16 + 64;

  NativeAd? _nativeAd;
  NativeAd? _loadingAd;
  DateTime? _loadedAt;
  bool _isDismissed = false;
  bool _isAppBackgrounded = false;
  int _retryCount = 0;
  Timer? _retryTimer;

  bool get _isActive =>
      widget.isVisible && !_isDismissed && !_isAppBackgrounded;

  bool get _isStale =>
      _loadedAt == null ||
      DateTime.now().difference(_loadedAt!) >= _minRefreshInterval;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadAd();
  }

  @override
  void didUpdateWidget(FloatingNativeAdSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.showToken != null && widget.showToken != oldWidget.showToken) {
      // A new video tab: show the ad again even if it was closed.
      _isDismissed = false;
    }
    if (_isActive) {
      _loadIfNeeded();
    } else {
      _retryTimer?.cancel();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final bg = state == AppLifecycleState.paused;
    if (bg == _isAppBackgrounded) return;
    setState(() => _isAppBackgrounded = bg);
    if (bg) {
      _retryTimer?.cancel();
    } else {
      _loadIfNeeded();
    }
  }

  void _loadIfNeeded() {
    if (!_isActive || _loadingAd != null) return;
    if (_nativeAd == null) _retryCount = 0;
    if (_nativeAd == null || _isStale) _loadAd();
  }

  void _loadAd() {
    if (!_isActive || _loadingAd != null) return;
    final unitId = AdConfig.floatingNativeAdUnitId;
    _loadingAd = NativeAd(
      adUnitId: unitId,
      request: const AdRequest(),
      factoryId: 'mrplayNative',
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          if (!mounted || !identical(_loadingAd, ad)) {
            ad.dispose();
            return;
          }
          final old = _nativeAd;
          _loadingAd = null;
          _retryCount = 0;
          _loadedAt = DateTime.now();
          setState(() => _nativeAd = ad as NativeAd);
          if (old != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
          }
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          debugPrint('MrPlay floating native failed to load ($unitId): '
              'code=${error.code} message=${error.message}');
          if (identical(_loadingAd, ad)) _loadingAd = null;
          if (!mounted) return;
          // A refresh failed: keep showing the current ad.
          if (_nativeAd != null || !_isActive) return;
          _retryTimer?.cancel();
          final delay = _initialRetryDelay * (1 << _retryCount.clamp(0, 4));
          _retryCount++;
          _retryTimer = Timer(
            delay > _maxRetryDelay ? _maxRetryDelay : delay,
            () {
              if (mounted) _loadAd();
            },
          );
        },
      ),
    )..load();
  }

  void _handleDismiss() {
    _retryTimer?.cancel();
    setState(() => _isDismissed = true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _retryTimer?.cancel();
    _loadingAd?.dispose();
    _nativeAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _nativeAd;
    if (ad == null || !_isActive) return const SizedBox.shrink();
    final screenWidth = MediaQuery.of(context).size.width;
    final width = (screenWidth - _reservedWidth).clamp(0.0, _maxAdWidth);
    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              GestureDetector(
                onTap: _handleDismiss,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: 28,
                  height: 28,
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
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  height: _adHeight,
                  width: width,
                  child: AdWidget(key: ValueKey(ad.hashCode), ad: ad),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
