import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../core/utils/log.dart';

/// Retry delay after the [failures]-th failed load: 30s, 60s, 2m, 4m, then 5m.
Duration adRetryDelay(int failures) {
  const max = Duration(minutes: 5);
  final delay = const Duration(seconds: 30) * (1 << failures.clamp(0, 4));
  return delay > max ? max : delay;
}

/// A dismissible AdMob banner. Loads only while visible and the app is in the
/// foreground; retries failed loads with exponential backoff.
class BannerAdSlot extends StatefulWidget {
  const BannerAdSlot({
    super.key,
    required this.adUnitId,
    this.size = AdSize.largeBanner,
    this.visible = true,
    this.dismissible = true,
    this.alignment = Alignment.center,
  });

  final String adUnitId;
  final AdSize size;
  final bool visible;
  final bool dismissible;
  final Alignment alignment;

  @override
  State<BannerAdSlot> createState() => _BannerAdSlotState();
}

class _BannerAdSlotState extends State<BannerAdSlot> with WidgetsBindingObserver {
  BannerAd? _ad;
  bool _loaded = false;
  bool _dismissed = false;
  bool _backgrounded = false;
  int _failures = 0;
  Timer? _retry;

  bool get _active => widget.visible && !_dismissed && !_backgrounded;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didUpdateWidget(BannerAdSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.adUnitId != widget.adUnitId) {
      _disposeAd();
      _failures = 0;
    }
    _onActivityChanged();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final bg = state == AppLifecycleState.paused;
    if (bg == _backgrounded) return;
    setState(() => _backgrounded = bg);
    _onActivityChanged();
  }

  void _onActivityChanged() {
    if (!_active) {
      _retry?.cancel();
    } else if (_ad == null) {
      _load();
    }
  }

  void _load() {
    if (!_active || _ad != null) return;
    _retry?.cancel();
    _ad = BannerAd(
      adUnitId: widget.adUnitId,
      size: widget.size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted || !identical(ad, _ad)) {
            unawaited(ad.dispose());
            return;
          }
          _failures = 0;
          setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          unawaited(ad.dispose());
          log('banner ${widget.adUnitId} failed: ${error.code} ${error.message}', tag: 'ads');
          if (!identical(ad, _ad)) return;
          _ad = null;
          if (!mounted) return;
          setState(() => _loaded = false);
          if (!_active) return;
          _retry = Timer(adRetryDelay(_failures++), _load);
        },
      ),
    );
    unawaited(_ad!.load());
  }

  void _disposeAd() {
    _retry?.cancel();
    unawaited(_ad?.dispose());
    _ad = null;
    _loaded = false;
  }

  void _dismiss() => setState(() {
        _disposeAd();
        _dismissed = true;
      });

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeAd();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (!_loaded || ad == null || !_active) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Align(
        alignment: widget.alignment,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: widget.size.width.toDouble(),
            height: widget.size.height.toDouble(),
            child: Stack(
              children: [
                Positioned.fill(
                  child: ColoredBox(
                    color: const Color(0xEB2D2D2D),
                    child: Center(child: AdWidget(key: ValueKey(ad), ad: ad)),
                  ),
                ),
                if (widget.dismissible)
                  Positioned(top: 4, right: 4, child: _DismissButton(onTap: _dismiss)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DismissButton extends StatelessWidget {
  const _DismissButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: const Color(0xE62D2D2D),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: const Icon(Icons.close, size: 16, color: Colors.white70),
      ),
    );
  }
}
