import 'package:flutter/material.dart';
import '../../app.dart';
import '../../data/models/favorite_video.dart';
import '../../data/repositories/watch_history_repository.dart';

/// List of recently watched videos. Tapping an entry replays it; the trash
/// button removes a single entry and the app-bar action clears everything.
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<FavoriteVideo> _videos = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final videos = await WatchHistoryRepository.getAll();
    if (mounted) {
      setState(() {
        _videos = videos;
        _isLoading = false;
      });
    }
  }

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.month}/${dt.day}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          if (_videos.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: 'Clear history',
              onPressed: () async {
                await WatchHistoryRepository.clear();
                _load();
              },
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _videos.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.history, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text(
                        'No watched videos yet',
                        style: TextStyle(color: Colors.grey, fontSize: 16),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
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
                              ? Image.network(
                                  video.thumbnailUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    color: Colors.grey,
                                    child: const Icon(Icons.play_circle,
                                        color: Colors.white),
                                  ),
                                )
                              : Container(
                                  color: Colors.grey,
                                  child: const Icon(Icons.play_circle,
                                      color: Colors.white),
                                ),
                        ),
                      ),
                      title: Text(
                        video.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${video.channel} · ${_relativeTime(video.addedAt)}',
                        maxLines: 1,
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () async {
                          await WatchHistoryRepository.remove(video.id);
                          _load();
                        },
                      ),
                      onTap: () {
                        MrPlayApp.webViewKey.currentState
                            ?.loadUrl(video.platformUrl);
                      },
                    );
                  },
                ),
    );
  }
}
