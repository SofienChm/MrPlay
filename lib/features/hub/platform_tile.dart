import 'package:flutter/material.dart';

/// Hub grid tile with a small scale-down animation on press.
class PlatformTile extends StatefulWidget {
  const PlatformTile({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.color,
    this.onLongPress,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// Filled background; null draws an outlined tile.
  final Color? color;

  @override
  State<PlatformTile> createState() => _PlatformTileState();
}

class _PlatformTileState extends State<PlatformTile> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    duration: const Duration(milliseconds: 150),
    vsync: this,
  );
  late final Animation<double> _scale = Tween<double>(begin: 1, end: 0.95)
      .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color;
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap();
      },
      onTapCancel: _controller.reverse,
      onLongPress: widget.onLongPress,
      child: ScaleTransition(
        scale: _scale,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(16),
            border: color == null ? Border.all(color: Colors.white30, width: 1.5) : null,
            boxShadow: color == null
                ? null
                : [
                    BoxShadow(
                      color: color.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(widget.icon, size: 36, color: color == null ? Colors.white70 : Colors.white),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  widget.label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color == null ? Colors.white70 : Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
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
