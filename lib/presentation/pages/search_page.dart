import 'package:flutter/material.dart';
import '../../core/constants/platform_constants.dart';
import '../../data/models/platform_model.dart';
import '../../app.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _controller = TextEditingController();
  PlatformModel? _selectedPlatform;

  @override
  void initState() {
    super.initState();
    _selectedPlatform = PlatformConstants.platforms.first;
  }

  void _performSearch() {
    final query = _controller.text.trim();
    if (query.isEmpty || _selectedPlatform == null) return;

    final searchUrl = _getSearchUrl(_selectedPlatform!.url, query);
    MrPlayApp.webViewKey.currentState?.loadUrl(searchUrl);
    Navigator.pop(context);
  }

  String _getSearchUrl(String baseUrl, String query) {
    final uri = Uri.parse(baseUrl);
    final host = uri.host;

    if (host.contains('youtube.com')) {
      return 'https://m.youtube.com/results?search_query=${Uri.encodeComponent(query)}';
    } else if (host.contains('twitch.tv')) {
      return 'https://m.twitch.tv/search?term=${Uri.encodeComponent(query)}';
    } else if (host.contains('reddit.com')) {
      return 'https://www.reddit.com/search/?q=${Uri.encodeComponent(query)}';
    } else if (host.contains('instagram.com')) {
      return 'https://www.instagram.com/explore/search/keyword/?q=${Uri.encodeComponent(query)}';
    } else if (host.contains('pinterest.com')) {
      return 'https://www.pinterest.com/search/pins/?q=${Uri.encodeComponent(query)}';
    }
    return '$baseUrl/search?q=${Uri.encodeComponent(query)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Search'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: TextField(
                controller: _controller,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _performSearch(),
                decoration: InputDecoration(
                  hintText: 'Search ${_selectedPlatform?.name ?? ""}...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _controller.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _controller.clear();
                            setState(() {});
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 40,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: PlatformConstants.platforms.length,
                itemBuilder: (context, index) {
                  final platform = PlatformConstants.platforms[index];
                  final isSelected = _selectedPlatform?.name == platform.name;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(platform.name),
                      selected: isSelected,
                      selectedColor: platform.color,
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : null,
                        fontSize: 12,
                      ),
                      onSelected: (_) {
                        setState(() => _selectedPlatform = platform);
                      },
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Quick search on:',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 2,
                ),
                itemCount: PlatformConstants.platforms.length,
                itemBuilder: (context, index) {
                  final platform = PlatformConstants.platforms[index];
                  return InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      setState(() => _selectedPlatform = platform);
                      _performSearch();
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: platform.color.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: platform.color.withOpacity(0.3)),
                      ),
                      child: Center(
                        child: Text(
                          platform.name,
                          style: TextStyle(
                            color: platform.color,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
