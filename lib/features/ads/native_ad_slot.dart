import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../core/config/ad_units.dart';
import '../../core/utils/log.dart';
import '../browser/browser_state.dart';
import 'banner_ad_slot.dart';

/// Native ad on the hub (layout drawn by the native factory in Swift).
/// Active only while the hub is visible and the app is foregrounded;
/// refreshes at most once a minute and keeps the current ad when a refresh
/// fails.
class NativeAdSlot extends ConsumerStatefulWidget {
  const NativeAdSlot({super.key, this.height = 136});

  final double height;

  @override
  ConsumerState<NativeAdSlot> createState() => _NativeAdSlotState();
}

class _NativeAdSlotState extends ConsumerState<NativeAdSlot> with WidgetsBindingObserver {
  static const Duration _minRefresh = Duration(seconds: 60);

  NativeAd? _ad;
  NativeAd? _loading;
  DateTime? _loadedAt;
  bool _backgrounded = false;
  int _failures = 0;
  Timer? _retry;

  bool get _hubVisible => ref.read(hubVisibleProvider);
  bool get _active => _hubVisible && !_backgrounded;

  bool get _stale => _loadedAt == null || DateTime.now().difference(_loadedAt!) >= _minRefresh;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadIfNeeded());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final bg = state == AppLifecycleState.paused;
    if (bg == _backgrounded) return;
    setState(() => _backgrounded = bg);
    bg ? _retry?.cancel() : _loadIfNeeded();
  }

  void _loadIfNeeded() {
    if (!mounted || !_active || _loading != null) return;
    if (_ad == null || _stale) _load();
  }

  void _load() {
    _retry?.cancel();
    final ad = NativeAd(
      adUnitId: AdUnits.hubNative,
      factoryId: AdUnits.nativeFactoryId,
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: (loaded) {
          if (!mounted || !identical(loaded, _loading)) {
            unawaited(loaded.dispose());
            return;
          }
          final old = _ad;
          _loading = null;
          _failures = 0;
          _loadedAt = DateTime.now();
          setState(() => _ad = loaded as NativeAd);
          if (old != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(old.dispose()));
          }
        },
        onAdFailedToLoad: (failed, error) {
          unawaited(failed.dispose());
          log('native failed: ${error.code} ${error.message}', tag: 'ads');
          if (identical(failed, _loading)) _loading = null;
          // A failed refresh keeps showing the current ad.
          if (!mounted || _ad != null || !_active) return;
          _retry = Timer(adRetryDelay(_failures++), _loadIfNeeded);
        },
      ),
    );
    _loading = ad;
    unawaited(ad.load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _retry?.cancel();
    unawaited(_loading?.dispose());
    unawaited(_ad?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(hubVisibleProvider, (_, visible) {
      visible ? _loadIfNeeded() : _retry?.cancel();
    });
    final ad = _ad;
    if (ad == null || !ref.watch(hubVisibleProvider) || _backgrounded) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: widget.height,
          width: double.infinity,
          child: AdWidget(key: ValueKey(ad), ad: ad),
        ),
      ),
    );
  }
}
