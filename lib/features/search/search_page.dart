import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/platforms.dart';
import '../../core/utils/url_utils.dart';
import '../player/playback_engine.dart';

/// Search a chosen platform and open the results in the browser.
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final TextEditingController _controller = TextEditingController();
  Platform _selected = Platforms.builtIn.first;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _search([Platform? platform]) {
    if (platform != null) setState(() => _selected = platform);
    final query = _controller.text.trim();
    if (query.isEmpty) return;
    ref.read(playbackEngineProvider).loadUrl(UrlUtils.platformSearch(_selected.url, query));
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Search')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildField(context),
            const SizedBox(height: 16),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final p in Platforms.builtIn)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(p.name),
                        selected: p.name == _selected.name,
                        selectedColor: p.color,
                        labelStyle: TextStyle(
                          color: p.name == _selected.name ? Colors.white : null,
                          fontSize: 12,
                        ),
                        onSelected: (_) => setState(() => _selected = p),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text('Quick search on:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Expanded(
              child: GridView.count(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 2,
                children: [for (final p in Platforms.builtIn) _QuickSearchTile(platform: p, onTap: () => _search(p))],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _search(),
        decoration: InputDecoration(
          hintText: 'Search ${_selected.name}...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _controller.text.isEmpty
              ? null
              : IconButton(icon: const Icon(Icons.clear), onPressed: _controller.clear),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        ),
      ),
    );
  }
}

class _QuickSearchTile extends StatelessWidget {
  const _QuickSearchTile({required this.platform, required this.onTap});

  final Platform platform;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = platform.color;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Ink(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Center(
          child: Text(
            platform.name,
            style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12),
          ),
        ),
      ),
    );
  }
}
