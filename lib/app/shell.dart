import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/ad_units.dart';
import '../features/ads/banner_ad_slot.dart';
import '../features/browser/browser_layer.dart';
import '../features/browser/browser_state.dart';
import '../features/hub/hub_page.dart';
import '../features/player/player_overlay.dart';
import '../features/player/player_state.dart';

/// Root layers: hub → browser → player → floating banner.
class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Stack(
        children: [
          HubPage(),
          Positioned.fill(child: SafeArea(bottom: false, child: BrowserLayer())),
          PlayerOverlay(),
          Positioned(left: 0, right: 0, bottom: 80, child: _FloatingBanner()),
        ],
      ),
    );
  }
}

/// Banner over the browser; hidden on the hub (it has its own native slot)
/// and while a player covers the screen.
class _FloatingBanner extends ConsumerWidget {
  const _FloatingBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hubVisible = ref.watch(hubVisibleProvider);
    final player = ref.watch(playerProvider);
    final playerCovers = player.isVideoTab || (player.hasVideo && !player.isMinimized);
    return BannerAdSlot(
      adUnitId: AdUnits.floatingBanner,
      visible: !hubVisible && !playerCovers,
      alignment: Alignment.centerLeft,
    );
  }
}
