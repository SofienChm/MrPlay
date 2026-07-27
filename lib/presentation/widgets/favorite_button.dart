import 'package:flutter/material.dart';
import '../../data/models/favorite_video.dart';
import '../../data/repositories/favorites_repository.dart';

class FavoriteButton extends StatefulWidget {
  final String id;
  final String title;
  final String channel;
  final String thumbnailUrl;
  final String platformUrl;

  const FavoriteButton({
    super.key,
    required this.id,
    required this.title,
    required this.channel,
    required this.thumbnailUrl,
    required this.platformUrl,
  });

  @override
  State<FavoriteButton> createState() => _FavoriteButtonState();
}

class _FavoriteButtonState extends State<FavoriteButton> {
  bool _isFavorite = false;

  @override
  void initState() {
    super.initState();
    _checkFavorite();
  }

  Future<void> _checkFavorite() async {
    final isFav = await FavoritesRepository.isFavorite(widget.id);
    if (mounted) setState(() => _isFavorite = isFav);
  }

  Future<void> _toggleFavorite() async {
    if (_isFavorite) {
      await FavoritesRepository.remove(widget.id);
    } else {
      await FavoritesRepository.add(FavoriteVideo(
        id: widget.id,
        title: widget.title,
        channel: widget.channel,
        thumbnailUrl: widget.thumbnailUrl,
        platformUrl: widget.platformUrl,
        addedAt: DateTime.now(),
      ));
    }
    if (mounted) setState(() => _isFavorite = !_isFavorite);
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        _isFavorite ? Icons.favorite : Icons.favorite_border,
        color: _isFavorite ? Colors.red : Colors.white,
      ),
      onPressed: _toggleFavorite,
    );
  }
}
