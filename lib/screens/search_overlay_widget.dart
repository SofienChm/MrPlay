import 'package:flutter/material.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../theme/app_colors.dart';

class SearchOverlayWidget extends StatelessWidget {
  final bool isSearchLoading;
  final List<Video> searchResults;
  final VoidCallback onDismiss;
  final ValueChanged<Video> onResultTap;

  const SearchOverlayWidget({
    super.key,
    required this.isSearchLoading,
    required this.searchResults,
    required this.onDismiss,
    required this.onResultTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surfaceOverlay,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
                    onPressed: onDismiss,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Search Results',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  if (isSearchLoading)
                    const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.textTertiary,
                      ),
                    ),
                ],
              ),
            ),
            const Divider(color: AppColors.textFaint, height: 1),
            Expanded(
              child: isSearchLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppColors.textTertiary),
                    )
                  : searchResults.isEmpty
                      ? const Center(
                          child: Text(
                            'No results found',
                            style: TextStyle(color: AppColors.textTertiary, fontSize: 15),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemCount: searchResults.length,
                          separatorBuilder: (_, __) => const Divider(
                            color: AppColors.textVeryFaint, height: 1, indent: 72,
                          ),
                          itemBuilder: (context, index) {
                            final video = searchResults[index];
                            final thumb = video.thumbnails.mediumResUrl;
                            final dur = video.duration;
                            final durStr = dur != null
                                ? '${dur.inMinutes}:${(dur.inSeconds % 60).toString().padLeft(2, '0')}'
                                : '';
                            return InkWell(
                              onTap: () => onResultTap(video),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8,
                                ),
                                child: Row(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: SizedBox(
                                        width: 60,
                                        height: 45,
                                        child: Stack(
                                          children: [
                                            Image.network(
                                              thumb,
                                              fit: BoxFit.cover,
                                              width: 60,
                                              height: 45,
                                              loadingBuilder: (context, child, loadingProgress) {
                                                if (loadingProgress == null) return child;
                                                return Container(
                                                  color: AppColors.surfaceLighter,
                                                  child: const Center(
                                                    child: SizedBox(
                                                      width: 16, height: 16,
                                                      child: CircularProgressIndicator(strokeWidth: 2),
                                                    ),
                                                  ),
                                                );
                                              },
                                              errorBuilder: (_, __, ___) =>
                                                  Container(
                                                color: AppColors.surfaceLighter,
                                                child: const Icon(
                                                  Icons.movie,
                                                  color: AppColors.textDim,
                                                  size: 24,
                                                ),
                                              ),
                                            ),
                                            if (durStr.isNotEmpty)
                                              Positioned(
                                                right: 3,
                                                bottom: 3,
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(
                                                    horizontal: 4, vertical: 1,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.black87,
                                                    borderRadius: BorderRadius.circular(3),
                                                  ),
                                                  child: Text(
                                                    durStr,
                                                    style: const TextStyle(
                                                      color: AppColors.textPrimary,
                                                      fontSize: 10,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            video.title,
                                            style: const TextStyle(
                                              color: AppColors.textPrimary,
                                              fontSize: 14,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            video.author,
                                            style: const TextStyle(
                                              color: AppColors.textTertiary,
                                              fontSize: 12,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
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
