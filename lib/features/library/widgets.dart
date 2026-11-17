import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../player/playback_engine.dart';

/// Plays [url] in the browser layer and returns to the root so it is visible.
void playUrl(BuildContext context, WidgetRef ref, String url) {
  if (url.isEmpty) return;
  ref.read(playbackEngineProvider).loadUrl(url);
  Navigator.of(context).popUntil((r) => r.isFirst);
}

/// 16:9 rounded thumbnail with a placeholder icon.
class VideoThumbnail extends StatelessWidget {
  const VideoThumbnail({super.key, required this.url, this.width = 96, this.icon = Icons.play_circle});

  final String url;
  final double width;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: Colors.grey.shade800,
      alignment: Alignment.center,
      child: Icon(icon, color: Colors.white54),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: width,
        height: width * 9 / 16,
        child: url.isEmpty
            ? placeholder
            : CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                placeholder: (_, __) => placeholder,
                errorWidget: (_, __, ___) => placeholder,
              ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: muted),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(message!, style: TextStyle(color: muted), textAlign: TextAlign.center),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

/// Generic loading / error wrapper for an [AsyncValue] list.
class AsyncList<T> extends StatelessWidget {
  const AsyncList({super.key, required this.value, required this.builder});

  final AsyncValue<List<T>> value;
  final Widget Function(List<T> items) builder;

  @override
  Widget build(BuildContext context) => value.when(
        data: builder,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(icon: Icons.error_outline, title: 'Something went wrong', message: '$e'),
      );
}

/// Destructive confirmation dialog. Returns true when confirmed.
Future<bool> confirm(
  BuildContext context, {
  required String title,
  String? message,
  String action = 'Delete',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(action, style: const TextStyle(color: Colors.red)),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Single text-field dialog. Returns the trimmed text, or null if cancelled/empty.
Future<String?> promptText(
  BuildContext context, {
  required String title,
  String label = 'Name',
  String initial = '',
  String action = 'Save',
}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _TextPromptDialog(title: title, label: label, initial: initial, action: action),
    );

class _TextPromptDialog extends StatefulWidget {
  const _TextPromptDialog({required this.title, required this.label, required this.initial, required this.action});

  final String title;
  final String label;
  final String initial;
  final String action;

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  late final TextEditingController _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    Navigator.pop(context, text.isEmpty ? null : text);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: TextField(
          controller: _controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: widget.label),
          onSubmitted: (_) => _submit(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: _submit, child: Text(widget.action)),
        ],
      );
}

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 1)));
}

/// Fire-and-forget helper that keeps `unawaited_futures` happy.
void fireAndForget(Future<void> future) => unawaited(future);
