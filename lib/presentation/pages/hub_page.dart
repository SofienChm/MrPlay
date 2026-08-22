import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../../core/constants/platform_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/hub_backgrounds.dart';
import '../../data/models/custom_bookmark.dart';
import '../../data/models/platform_model.dart';
import '../../data/repositories/custom_bookmarks_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../services/siri_shortcuts_service.dart';
import '../widgets/platform_card.dart';
import '../pages/search_page.dart';
import 'favorites_page.dart';
import 'settings_page.dart';
import 'stats_page.dart';
import 'history_page.dart';
import '../../app.dart';
import '../../ad_config.dart';
import '../../widgets/unified_banner_ad_slot.dart';

class HubPage extends StatefulWidget {
  const HubPage({super.key});

  @override
  State<HubPage> createState() => _HubPageState();
}

class _HubPageState extends State<HubPage> {
  final TextEditingController _searchController = TextEditingController();
  List<CustomBookmark> _customBookmarks = [];
  List<PlatformModel> _filteredPlatforms = PlatformConstants.platforms;
  bool _showResults = false;
  String _defaultPlatform = 'YouTube';

  List<PlatformModel> get _allPlatforms {
    final bookmarks = _customBookmarks
        .map(
          (b) => PlatformModel(
            name: b.name,
            url: b.url,
            icon: 'custom',
            category: 'custom',
            color: AppColors.border,
          ),
        )
        .toList();
    var platforms = [...PlatformConstants.platforms, ...bookmarks];
    platforms.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    if (_defaultPlatform != 'YouTube') {
      final idx = platforms.indexWhere((p) => p.name == _defaultPlatform);
      if (idx > 0) {
        final def = platforms.removeAt(idx);
        platforms.insert(0, def);
      }
    }
    return platforms;
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_syncSearchFromController);
    _loadCustomBookmarks();
    _loadDefaultPlatform();
  }

  Future<void> _loadCustomBookmarks() async {
    final bookmarks = await CustomBookmarksRepository.getAll();
    if (mounted) {
      setState(() {
        _customBookmarks = bookmarks;
        if (!_showResults) _filteredPlatforms = _allPlatforms;
      });
    }
  }

  Future<void> _loadDefaultPlatform() async {
    final platform = await SettingsRepository.getDefaultPlatform();
    if (mounted) {
      setState(() {
        _defaultPlatform = platform;
        if (!_showResults) _filteredPlatforms = _allPlatforms;
      });
    }
  }

  @override
  void dispose() {
    _searchController.removeListener(_syncSearchFromController);
    _searchController.dispose();
    super.dispose();
  }

  void _syncSearchFromController() {
    final query = _searchController.text;
    setState(() {
      if (query.isEmpty) {
        _filteredPlatforms = _allPlatforms;
        _showResults = false;
      } else {
        _filteredPlatforms = _allPlatforms
            .where((p) => p.name.toLowerCase().contains(query.toLowerCase()))
            .toList();
        _showResults = true;
      }
    });
  }

  Future<void> _showAddBookmarkDialog() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => const _AddBookmarkDialog(),
    );
    if (saved == true) _loadCustomBookmarks();
  }

  Future<void> _confirmDeleteBookmark(PlatformModel platform) async {
    final bookmark = _customBookmarks.cast<CustomBookmark?>().firstWhere(
          (b) => b!.url == platform.url,
          orElse: () => null,
        );
    if (bookmark == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Remove ${platform.name}?'),
        content: const Text('This shortcut will be removed from the hub.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await CustomBookmarksRepository.remove(bookmark.id);
      _loadCustomBookmarks();
    }
  }

  void _onSearchSubmitted(String query) {
    if (query.isEmpty) return;

    final matched = PlatformConstants.platforms
        .where((p) => p.name.toLowerCase() == query.toLowerCase())
        .toList();

    if (matched.isNotEmpty) {
      _onPlatformTap(matched.first);
    } else {
      _launchGoogleSearch(query);
    }
    _searchController.clear();
  }

  void _launchGoogleSearch(String query) {
    final url = Uri.parse(
      'https://www.google.com/search?q=${Uri.encodeComponent(query)}',
    );
    MrPlayApp.webViewKey.currentState?.loadUrl(url.toString());
  }

  void _onPlatformTap(PlatformModel platform) {
    SiriShortcutsService.instance.setCurrent(
      name: platform.name,
      url: platform.url,
    );
    MrPlayApp.webViewKey.currentState?.loadUrl(platform.url);
  }

  void _onBottomNavTap(int index) {
    final pages = [
      () => const FavoritesPage(),
      () => HistoryPage(),
      () => const StatsPage(),
      () => const SettingsPage(),
    ];
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => pages[index]()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: 0,
        onTap: _onBottomNavTap,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.video_library_outlined),
            label: 'Library',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history),
            label: 'Watch History',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart),
            label: 'Stats',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            label: 'Settings',
          ),
        ],
      ),
      body: ValueListenableBuilder<int>(
        valueListenable: MrPlayApp.hubBackgroundNotifier,
        builder: (context, background, _) => Container(
          decoration: HubBackgrounds.decorationFor(background),
          child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.search, color: Colors.white),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const SearchPage()),
                        );
                      },
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.favorite, color: Colors.white),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const FavoritesPage()),
                            );
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.settings, color: Colors.white),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const SettingsPage()),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'MrPlay',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: TextField(
                    controller: _searchController,
                    onSubmitted: _onSearchSubmitted,
                    decoration: InputDecoration(
                      hintText: 'Search platforms or Google...',
                      prefixIcon: const Icon(Icons.search, color: Colors.grey),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, color: Colors.grey),
                              onPressed: _searchController.clear,
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 15),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Center(
                child: UnifiedBannerAdSlot(
                  adUnitId: AdConfig.hubBannerAdUnitId,
                  adSize: AdSize.banner,
                  showDismissButton: false,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _showResults && _filteredPlatforms.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.search_off,
                                size: 64, color: Colors.white38),
                            const SizedBox(height: 16),
                            Text(
                              'No platforms match "${_searchController.text}"',
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 14),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Press Enter to search Google',
                              style: const TextStyle(
                                  color: Colors.white38, fontSize: 12),
                            ),
                          ],
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: GridView.builder(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 4,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                          itemCount: _filteredPlatforms.length +
                              (_showResults ? 0 : 1),
                          itemBuilder: (context, index) {
                            if (index >= _filteredPlatforms.length) {
                              return _AddCard(onTap: _showAddBookmarkDialog);
                            }
                            final platform = _filteredPlatforms[index];
                            return PlatformCard(
                              platform: platform,
                              onTap: () => _onPlatformTap(platform),
                              onLongPress: platform.category == 'custom'
                                  ? () => _confirmDeleteBookmark(platform)
                                  : null,
                            );
                          },
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

class _AddBookmarkDialog extends StatefulWidget {
  const _AddBookmarkDialog();

  @override
  State<_AddBookmarkDialog> createState() => _AddBookmarkDialogState();
}

class _AddBookmarkDialogState extends State<_AddBookmarkDialog> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _urlController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    var url = _urlController.text.trim();
    if (name.isEmpty || url.isEmpty) return;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    await CustomBookmarksRepository.add(
      CustomBookmark(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        url: url,
        addedAt: DateTime.now(),
      ),
    );
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add shortcut'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'My Site',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _urlController,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'URL',
              hintText: 'example.com',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _save,
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class _AddCard extends StatelessWidget {
  final VoidCallback onTap;

  const _AddCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white30, width: 1.5),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add, size: 36, color: Colors.white70),
            SizedBox(height: 8),
            Text(
              'Add',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
