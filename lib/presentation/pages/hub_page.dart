import 'package:flutter/material.dart';
import '../../core/constants/platform_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/custom_bookmark.dart';
import '../../data/models/platform_model.dart';
import '../../data/repositories/custom_bookmarks_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../services/analytics_service.dart';
import '../widgets/platform_card.dart';
import '../pages/search_page.dart';
import 'favorites_page.dart';
import 'history_page.dart';
import 'settings_page.dart';
import 'stats_page.dart';
import '../../app.dart';

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

  List<PlatformModel> get _allPlatforms {
    final bookmarks = _customBookmarks
        .map(
          (b) => PlatformModel(
            name: b.name,
            url: b.url,
            icon: 'custom',
            category: 'custom',
            subtitle: 'Custom',
            color: AppColors.border,
          ),
        )
        .toList();
    bookmarks.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return [...PlatformConstants.platforms, ...bookmarks];
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_syncSearchFromController);
    _loadCustomBookmarks();
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
    AnalyticsService.logSearch(query);

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
    SettingsRepository.setLastPlatformUrl(platform.url);
    AnalyticsService.logPlatformOpened(platform.name);
    MrPlayApp.webViewKey.currentState?.loadUrl(platform.url);
  }

  void _openMoreChannels() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SearchPage()),
    );
  }

  void _openFavorites() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const FavoritesPage()),
    );
  }

  void _openWatchLater() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const FavoritesPage(initialIndex: 1),
      ),
    );
  }

  void _openHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const HistoryPage()),
    );
  }

  void _openStats() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const StatsPage()),
    );
  }

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'MrPlay',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add, color: Colors.white70),
                    tooltip: 'Add shortcut',
                    onPressed: _showAddBookmarkDialog,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.cardDark,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border, width: 1),
                ),
                child: TextField(
                  controller: _searchController,
                  onSubmitted: _onSearchSubmitted,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Search',
                    hintStyle:
                        const TextStyle(color: Colors.white38, fontSize: 14),
                    prefixIcon:
                        const Icon(Icons.search, color: Colors.white38, size: 20),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear,
                                color: Colors.white38, size: 18),
                            onPressed: _searchController.clear,
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 13),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
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
                          const Text(
                            'Press Enter to search Google',
                            style: TextStyle(
                                color: Colors.white38, fontSize: 12),
                          ),
                        ],
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          childAspectRatio: 1.35,
                        ),
                        itemCount: _filteredPlatforms.length +
                            (_showResults ? 0 : 1),
                        itemBuilder: (context, index) {
                          if (index >= _filteredPlatforms.length) {
                            return _MoreCard(onTap: _openMoreChannels);
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
            _QuickActionBar(
              onFavorite: _openFavorites,
              onLater: _openWatchLater,
              onHistory: _openHistory,
              onStats: _openStats,
            ),
          ],
        ),
      ),
      bottomNavigationBar: _HubBottomNav(onSettings: _openSettings),
    );
  }
}

class _QuickActionBar extends StatelessWidget {
  final VoidCallback onFavorite;
  final VoidCallback onLater;
  final VoidCallback onHistory;
  final VoidCallback onStats;

  const _QuickActionBar({
    required this.onFavorite,
    required this.onLater,
    required this.onHistory,
    required this.onStats,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Row(
        children: [
          _QuickAction(
            icon: Icons.favorite_border,
            label: 'Favorite',
            onTap: onFavorite,
          ),
          _QuickAction(
            icon: Icons.format_list_bulleted,
            label: 'Later',
            onTap: onLater,
          ),
          _QuickAction(
            icon: Icons.history,
            label: 'History',
            onTap: onHistory,
          ),
          _QuickAction(
            icon: Icons.bar_chart,
            label: 'Stats',
            onTap: onStats,
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.cardDark,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border, width: 1),
                ),
                child: Icon(icon, color: Colors.white70, size: 24),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoreCard extends StatelessWidget {
  final VoidCallback onTap;

  const _MoreCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.cardDark,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border, width: 1),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'More',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            const Text(
              'Channels',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const Spacer(),
            Align(
              alignment: Alignment.bottomRight,
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(10),
                ),
                child:
                    const Icon(Icons.more_horiz, color: Colors.white70, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HubBottomNav extends StatelessWidget {
  final VoidCallback onSettings;

  const _HubBottomNav({required this.onSettings});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0A0A0A),
        border: Border(top: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: _NavItem(
                icon: Icons.grid_view_rounded,
                label: 'Home',
                color: AppColors.youtube,
                onTap: () {},
              ),
            ),
            Expanded(
              child: _NavItem(
                icon: Icons.settings_outlined,
                label: 'Setting',
                color: Colors.white54,
                onTap: onSettings,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: color == AppColors.youtube
                    ? FontWeight.w600
                    : FontWeight.w400,
              ),
            ),
          ],
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
