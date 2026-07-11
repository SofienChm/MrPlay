import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class MiniPlayerWidget extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onExpand;
  final VoidCallback onClose;

  static const double height = 72.0;

  const MiniPlayerWidget({
    super.key,
    required this.title,
    this.subtitle = 'Now Playing',
    required this.onExpand,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onExpand,
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: AppColors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 48,
                  height: 48,
                  color: AppColors.surfaceLighter,
                  child: const Icon(
                    Icons.play_circle_fill,
                    color: AppColors.textMuted,
                    size: 24,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title.isNotEmpty ? title : 'Playing',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 40,
                height: 48,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.open_in_full, color: Colors.white, size: 20),
                  tooltip: 'Expand',
                  onPressed: () {
                    // Stop event propagation to the outer GestureDetector
                    onExpand();
                  },
                ),
              ),
              SizedBox(
                width: 40,
                height: 48,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.close, color: Colors.white, size: 20),
                  tooltip: 'Close',
                  onPressed: () {
                    onClose();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
