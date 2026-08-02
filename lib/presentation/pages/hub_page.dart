import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/platform_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/custom_bookmark.dart';
import '../../data/models/platform_model.dart';
import '../../data/repositories/custom_bookmarks_repository.dart';
import '../widgets/platform_card.dart';
import '../pages/search_page.dart';
import 'favorites_page.dart';
import 'settings_page.dart';
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

  List<PlatformModel> get _allPlatforms => [
        ...PlatformConstants.platforms,
        ..._customBookmarks.map(
          (b) => PlatformModel(
            name: b.name,
            url: b.url,
            icon: 'custom',
            category: 'custom',
            color: AppColors.border,
          ),
        ),
      ];

  @override
  void initState() {
    super.initState();
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
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
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
    final nameController = TextEditingController();
    final urlController = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add shortcut'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'My Site',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlController,
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
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final name = nameController.text.trim();
              var url = urlController.text.trim();
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
              if (dialogContext.mounted) Navigator.pop(dialogContext, true);
            },
          child: const Text('Add'),
          ),
        ],
      ),
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
    setState(() => _showResults = false);
  }

  Future<void> _launchGoogleSearch(String query) async {
    final url = Uri.parse('https://www.google.com/search?q=${Uri.encodeComponent(query)}');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  void _onPlatformTap(PlatformModel platform) {
    MrPlayApp.webViewKey.currentState?.loadUrl(platform.url);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.hubGradientStart, AppColors.hubGradientEnd],
          ),
        ),
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
                              MaterialPageRoute(builder: (_) => const FavoritesPage()),
                            );
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.settings, color: Colors.white),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const SettingsPage()),
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
                    onChanged: _onSearchChanged,
                    onSubmitted: _onSearchSubmitted,
                    decoration: InputDecoration(
                      hintText: 'Search platforms or Google...',
                      prefixIcon: const Icon(Icons.search, color: Colors.grey),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, color: Colors.grey),
                              onPressed: () {
                                _searchController.clear();
                                _onSearchChanged('');
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: _showResults && _filteredPlatforms.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.search_off, size: 64, color: Colors.white38),
                            const SizedBox(height: 16),
                            Text(
                              'No platforms match "${_searchController.text}"',
                              style: const TextStyle(color: Colors.white70, fontSize: 14),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Press Enter to search Google',
                              style: const TextStyle(color: Colors.white38, fontSize: 12),
                            ),
                          ],
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: GridView.builder(
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 4,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                          itemCount: _filteredPlatforms.length + (_showResults ? 0 : 1),
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
