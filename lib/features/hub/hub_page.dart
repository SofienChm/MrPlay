import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/config/platforms.dart';
import '../../core/theme/palettes.dart';
import '../../core/utils/url_utils.dart';
import '../../data/models/models.dart';
import '../ads/native_ad_slot.dart';
import '../library/history_page.dart';
import '../library/library_page.dart';
import '../library/playlists_page.dart';
import '../player/playback_engine.dart';
import '../search/search_page.dart';
import '../settings/settings_page.dart';
import '../stats/stats_page.dart';
import 'platform_tile.dart';

const Color _shortcutColor = Color(0xFF2C2C2C);

/// Home screen: platform grid, search and user shortcuts.
class HubPage extends ConsumerStatefulWidget {
  const HubPage({super.key});

  @override
  ConsumerState<HubPage> createState() => _HubPageState();
}

class _HubPageState extends ConsumerState<HubPage> {
  final TextEditingController _search = TextEditingController();
  final Map<String, String> _shortcutIds = {};

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String get _query => _search.text.trim().toLowerCase();

  List<Platform> _platforms(List<Shortcut> shortcuts, String defaultPlatform) {
    _shortcutIds
      ..clear()
      ..addEntries(shortcuts.map((s) => MapEntry(s.url, s.id)));
    final all = [
      ...Platforms.builtIn,
      for (final s in shortcuts)
        Platform(name: s.name, url: s.url, icon: Icons.public, color: _shortcutColor, isCustom: true),
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final i = all.indexWhere((p) => p.name == defaultPlatform);
    if (i > 0) all.insert(0, all.removeAt(i));
    return all;
  }

  void _open(Platform platform) {
    unawaited(ref.read(siriProvider).donate(name: platform.name, url: platform.url));
    ref.read(playbackEngineProvider).loadUrl(platform.url);
  }

  void _submit(String value) {
    final query = value.trim();
    if (query.isEmpty) return;
    final match = Platforms.byName(query);
    if (match != null) {
      _open(match);
    } else {
      ref.read(playbackEngineProvider).loadUrl(UrlUtils.googleSearch(query));
    }
    _search.clear();
  }

  void _push(Widget page) =>
      unawaited(Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page)));

  Future<void> _addShortcut() async {
    final result = await showDialog<({String name, String url})>(
      context: context,
      builder: (_) => const _AddShortcutDialog(),
    );
    if (result == null) return;
    await ref.read(shortcutRepositoryProvider).add(name: result.name, url: UrlUtils.withScheme(result.url));
  }

  Future<void> _confirmRemove(Platform platform) async {
    final id = _shortcutIds[platform.url];
    if (id == null) return;
    final remove = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${platform.name}?'),
        content: const Text('This shortcut will be removed from the hub.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (remove == true) await ref.read(shortcutRepositoryProvider).remove(id);
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final shortcuts = ref.watch(shortcutsProvider).valueOrNull ?? const <Shortcut>[];
    final query = _query;
    final searching = query.isNotEmpty;
    final platforms = _platforms(shortcuts, settings.defaultPlatform)
        .where((p) => !searching || p.name.toLowerCase().contains(query))
        .toList();

    return Scaffold(
      bottomNavigationBar: _HubNavigationBar(onOpen: _push),
      body: DecoratedBox(
        decoration: HubBackgrounds.decoration(settings.hubBackground),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TopBar(onOpen: _push),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'MrPlay',
                  style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 16),
              _SearchField(controller: _search, onSubmitted: _submit),
              const SizedBox(height: 24),
              Expanded(
                child: searching && platforms.isEmpty
                    ? _NoResults(query: _search.text)
                    : _PlatformGrid(
                        platforms: platforms,
                        showExtras: !searching,
                        onOpen: _open,
                        onRemove: _confirmRemove,
                        onPlaylists: () => _push(const PlaylistsPage()),
                        onAdd: () => unawaited(_addShortcut()),
                      ),
              ),
              const SizedBox(height: 12),
              const Center(child: NativeAdSlot()),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onOpen});

  final void Function(Widget page) onOpen;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.search, color: Colors.white),
            onPressed: () => onOpen(const SearchPage()),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.favorite, color: Colors.white),
            onPressed: () => onOpen(const LibraryPage()),
          ),
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            onPressed: () => onOpen(const SettingsPage()),
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onSubmitted});

  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: DecoratedBox(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30)),
        child: TextField(
          controller: controller,
          onSubmitted: onSubmitted,
          textInputAction: TextInputAction.search,
          style: const TextStyle(color: Colors.black87),
          decoration: InputDecoration(
            hintText: 'Search platforms or Google...',
            hintStyle: const TextStyle(color: Colors.grey),
            prefixIcon: const Icon(Icons.search, color: Colors.grey),
            suffixIcon: controller.text.isEmpty
                ? null
                : IconButton(icon: const Icon(Icons.clear, color: Colors.grey), onPressed: controller.clear),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          ),
        ),
      ),
    );
  }
}

class _PlatformGrid extends StatelessWidget {
  const _PlatformGrid({
    required this.platforms,
    required this.showExtras,
    required this.onOpen,
    required this.onRemove,
    required this.onPlaylists,
    required this.onAdd,
  });

  final List<Platform> platforms;
  final bool showExtras;
  final ValueChanged<Platform> onOpen;
  final ValueChanged<Platform> onRemove;
  final VoidCallback onPlaylists;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final tiles = [
      for (final p in platforms)
        PlatformTile(
          label: p.name,
          icon: p.icon,
          color: p.color,
          onTap: () => onOpen(p),
          onLongPress: p.isCustom ? () => onRemove(p) : null,
        ),
      if (showExtras) ...[
        PlatformTile(label: 'Playlist', icon: Icons.playlist_play, onTap: onPlaylists),
        PlatformTile(label: 'Add', icon: Icons.add, onTap: onAdd),
      ],
    ];
    return GridView.count(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      crossAxisCount: 4,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      children: tiles,
    );
  }
}

class _NoResults extends StatelessWidget {
  const _NoResults({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.search_off, size: 64, color: Colors.white38),
          const SizedBox(height: 16),
          Text('No platforms match "$query"', style: const TextStyle(color: Colors.white70, fontSize: 14)),
          const SizedBox(height: 8),
          const Text('Press Enter to search Google', style: TextStyle(color: Colors.white38, fontSize: 12)),
        ],
      ),
    );
  }
}

class _HubNavigationBar extends StatelessWidget {
  const _HubNavigationBar({required this.onOpen});

  final void Function(Widget page) onOpen;

  static const List<Widget> _pages = [
    LibraryPage(),
    HistoryPage(),
    StatsPage(),
    SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      onTap: (i) => onOpen(_pages[i]),
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.video_library_outlined), label: 'Library'),
        BottomNavigationBarItem(icon: Icon(Icons.history), label: 'Watch History'),
        BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: 'Stats'),
        BottomNavigationBarItem(icon: Icon(Icons.settings_outlined), label: 'Settings'),
      ],
    );
  }
}

class _AddShortcutDialog extends StatefulWidget {
  const _AddShortcutDialog();

  @override
  State<_AddShortcutDialog> createState() => _AddShortcutDialogState();
}

class _AddShortcutDialogState extends State<_AddShortcutDialog> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _url = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    final url = _url.text.trim();
    if (name.isEmpty || url.isEmpty) return;
    Navigator.pop(context, (name: name, url: url));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add shortcut'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Name', hintText: 'My Site'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            autocorrect: false,
            onSubmitted: (_) => _save(),
            decoration: const InputDecoration(labelText: 'URL', hintText: 'example.com'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: _save, child: const Text('Add')),
      ],
    );
  }
}
