import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/video.dart';
import '../../providers/player_provider.dart';
import '../../services/recent_activity_service.dart';
import '../../core/constants/platform_constants.dart';

class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({super.key});

  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  late Future<List<Map<String, dynamic>>> _historyFuture;
  bool _isLoading = false;
  String? _clearError;

  @override
  void initState() {
    super.initState();
    _refreshHistory();
  }

  Future<void> _refreshHistory() async {
    setState(() => _isLoading = true);
    _historyFuture = RecentActivityService.instance.load();
    setState(() => _isLoading = false);
  }

  Future<void> _clearHistory() async {
    setState(() => _isLoading = true);
    try {
      await RecentActivityService.instance.clear();
      await _refreshHistory();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('History cleared')),
        );
      }
    } catch (e) {
      setState(() => _clearError = 'Failed to clear history');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  String _formatDate(int ms) {
    final date = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays >= 15) {
      return '${date.month}/${date.day}/${date.year}';
    } else if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Watch History'),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildHistoryList(theme),
                if (_clearError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _clearError!,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _buildHistoryList(ThemeData theme) {
    return Expanded(
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _historyFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return _emptyState(theme);
          }

          final history = snapshot.data!;
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: history.length,
            itemBuilder: (context, index) {
              final entry = history[index];
              final date = entry['date'] as int?;
              final formatted = date != null ? _formatDate(date) : 'Unknown';

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  leading: _platformIcon(entry['platform'] as String? ?? 'Web', theme),
                  title: Text(
                    entry['title'] as String? ?? 'Unknown Video',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                  subtitle: Text(
                    '${entry['platform'] as String? ?? 'Web'} • $formatted',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  onTap: () {
                    final url = entry['url'] as String?;
                    if (url != null && url.isNotEmpty) {
                      _openUrl(url);
                    }
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _platformIcon(String platform, ThemeData theme) {
    final icons = {
      'YouTube': Icons.play_arrow_rounded,
      'Music': Icons.music_rounded,
      'DailyMotion': Icons.videocam_rounded,
      'Twitch': Icons.cloud_download_rounded,
      'Kick': Icons.notifications_rounded,
      '9Gag': Icons.fun_foreground_rounded,
      'iFunny': Icons.sentiment_very_satisfied_rounded,
      'Rumble': Icons.pan_tool_rounded,
      'Web': Icons.link_rounded,
    };
    final icon = icons[platform] ?? Icons.link_rounded;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(icon, size: 24, color: theme.colorScheme.primary),
    );
  }

  Widget _emptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: Center,
        children: [
          Icon(
            Icons.history_rounded,
            size: 64,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'No watch history yet',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Videos you watch will appear here',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }
}