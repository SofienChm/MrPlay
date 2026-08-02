import 'package:flutter/material.dart';
import '../../data/models/favorite_video.dart';
import '../../data/repositories/favorites_repository.dart';
import '../../data/repositories/watch_later_repository.dart';
import '../../app.dart';

class FavoritesPage extends StatelessWidget {
  const FavoritesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Library'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.favorite), text: 'Favorites'),
              Tab(icon: Icon(Icons.bookmark), text: 'Watch Later'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _VideoListTab(
              getAll: FavoritesRepository.getAll,
              remove: FavoritesRepository.remove,
              clear: FavoritesRepository.clear,
              emptyIcon: Icons.favorite_border,
              emptyText: 'No favorites yet',
              trailingIcon: Icons.favorite,
              trailingColor: Colors.red,
            ),
            _VideoListTab(
              getAll: WatchLaterRepository.getAll,
              remove: WatchLaterRepository.remove,
              clear: WatchLaterRepository.clear,
              emptyIcon: Icons.bookmark_border,
              emptyText: 'Watch Later queue is empty',
              trailingIcon: Icons.bookmark,
              trailingColor: Colors.amber,
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoListTab extends StatefulWidget {
  final Future<List<FavoriteVideo>> Function() getAll;
  final Future<void> Function(String id) remove;
  final Future<void> Function() clear;
  final IconData emptyIcon;
  final String emptyText;
  final IconData trailingIcon;
  final Color trailingColor;

  const _VideoListTab({
    required this.getAll,
    required this.remove,
    required this.clear,
    required this.emptyIcon,
    required this.emptyText,
    required this.trailingIcon,
    required this.trailingColor,
  });

  @override
  State<_VideoListTab> createState() => _VideoListTabState();
}

class _VideoListTabState extends State<_VideoListTab>
    with AutomaticKeepAliveClientMixin {
  List<FavoriteVideo> _videos = [];
  bool _isLoading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final videos = await widget.getAll();
    if (mounted) {
      setState(() {
        _videos = videos;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_videos.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(widget.emptyIcon, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(widget.emptyText,
                style: const TextStyle(color: Colors.grey, fontSize: 16)),
          ],
        ),
      );
    }
    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: () async {
              await widget.clear();
              _load();
            },
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _videos.length,
            itemBuilder: (context, index) {
              final video = _videos[index];
              return ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 120,
                    height: 68,
                    child: video.thumbnailUrl.isNotEmpty
                        ? Image.network(video.thumbnailUrl, fit: BoxFit.cover)
                        : Container(
                            color: Colors.grey,
                            child: const Icon(Icons.play_circle,
                                color: Colors.white)),
                  ),
                ),
                title:
                    Text(video.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(video.channel, maxLines: 1),
                trailing: IconButton(
                  icon: Icon(widget.trailingIcon, color: widget.trailingColor),
                  onPressed: () async {
                    await widget.remove(video.id);
                    _load();
                  },
                ),
                onTap: () {
                  MrPlayApp.webViewKey.currentState?.loadUrl(video.platformUrl);
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
