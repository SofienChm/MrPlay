import 'package:flutter/material.dart';
import '../../data/models/favorite_video.dart';
import '../../data/repositories/favorites_repository.dart';
import '../../app.dart';

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  List<FavoriteVideo> _favorites = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    final favorites = await FavoritesRepository.getAll();
    if (mounted) {
      setState(() {
        _favorites = favorites;
        _isLoading = false;
      });
    }
  }

  Future<void> _removeFavorite(FavoriteVideo video) async {
    await FavoritesRepository.remove(video.id);
    _loadFavorites();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Favorites'),
        actions: [
          if (_favorites.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              onPressed: () async {
                await FavoritesRepository.clear();
                _loadFavorites();
              },
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _favorites.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.favorite_border, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text('No favorites yet', style: TextStyle(color: Colors.grey, fontSize: 16)),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _favorites.length,
                  itemBuilder: (context, index) {
                    final video = _favorites[index];
                    return ListTile(
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 120,
                          height: 68,
                          child: video.thumbnailUrl.isNotEmpty
                              ? Image.network(video.thumbnailUrl, fit: BoxFit.cover)
                              : Container(color: Colors.grey, child: const Icon(Icons.play_circle, color: Colors.white)),
                        ),
                      ),
                      title: Text(video.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(video.channel, maxLines: 1),
                      trailing: IconButton(
                        icon: const Icon(Icons.favorite, color: Colors.red),
                        onPressed: () => _removeFavorite(video),
                      ),
                      onTap: () {
                        MrPlayApp.webViewKey.currentState?.loadUrl(video.platformUrl);
                      },
                    );
                  },
                ),
    );
  }
}
