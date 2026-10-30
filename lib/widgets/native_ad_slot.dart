import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../ad_config.dart';
import '../presentation/widgets/persistent_webview.dart';

/// Native Advanced ad (compact custom layout) used on the hub page. Collapses
/// to nothing while no ad is loaded, retries with capped backoff, only shows
/// while the hub is visible, and refreshes (at most once a minute) when the
/// user comes back to the hub.
class NativeAdSlot extends StatefulWidget {
  final String? adUnitId;
  final double height;

  const NativeAdSlot({
    super.key,
    this.adUnitId,
    this.height = 136,
  });

  @override
  State<NativeAdSlot> createState() => _NativeAdSlotState();
}

class _NativeAdSlotState extends State<NativeAdSlot>
    with WidgetsBindingObserver {
  static const Duration _initialRetryDelay = Duration(seconds: 30);
  static const Duration _maxRetryDelay = Duration(minutes: 5);

  static const Duration _minRefreshInterval = Duration(seconds: 60);

  NativeAd? _nativeAd;
  NativeAd? _loadingAd;
  DateTime? _loadedAt;
  bool _isAppBackgrounded = false;
  bool _hubVisible = PersistentWebViewState.hubVisible.value;
  int _retryCount = 0;
  Timer? _retryTimer;

  bool get _isActive => _hubVisible && !_isAppBackgrounded;

  bool get _isStale =>
      _loadedAt == null ||
      DateTime.now().difference(_loadedAt!) >= _minRefreshInterval;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    PersistentWebViewState.hubVisible.addListener(_onHubVisibilityChanged);
    _loadAd();
  }

  void _onHubVisibilityChanged() {
    final visible = PersistentWebViewState.hubVisible.value;
    if (visible == _hubVisible || !mounted) return;
    setState(() => _hubVisible = visible);
    if (visible) {
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

  /// Loads when there is no ad yet, or the current one is older than
  /// [_minRefreshInterval].
  void _loadIfNeeded() {
    if (!_isActive || _loadingAd != null) return;
    if (_nativeAd == null) _retryCount = 0;
    if (_nativeAd == null || _isStale) _loadAd();
  }

  void _loadAd() {
    if (!_isActive || _loadingAd != null) return;

    final unitId = widget.adUnitId ?? AdConfig.hubNativeAdUnitId;
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
          debugPrint('MrPlay native failed to load ($unitId): '
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    PersistentWebViewState.hubVisible.removeListener(_onHubVisibilityChanged);
    _retryTimer?.cancel();
    _loadingAd?.dispose();
    _nativeAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _nativeAd;
    if (ad == null || !_isActive) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: widget.height,
          width: double.infinity,
          child: AdWidget(key: ValueKey(ad.hashCode), ad: ad),
        ),
      ),
    );
  }
}
