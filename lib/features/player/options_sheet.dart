import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/providers.dart';
import '../../core/theme/palettes.dart';
import '../browser/browser_state.dart';
import '../library/add_to_playlist_sheet.dart';
import '../library/library_page.dart';
import '../settings/settings_page.dart';
import '../share/data_transfer.dart';
import 'playback_engine.dart';
import 'player_state.dart';
import 'sleep_timer_sheet.dart';

/// The "..." menu of the browser: player tools, library and app actions.
Future<void> showOptionsSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      isScrollControlled: true,
      builder: (_) => const _OptionsSheet(),
    );

/// Delay after closing a sheet before presenting something new: iOS drops a
/// share sheet / modal presented while the previous one is still dismissing.
const _afterDismiss = Duration(milliseconds: 400);

class _OptionsSheet extends ConsumerWidget {
  const _OptionsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engine = ref.read(playbackEngineProvider);
    final video = ref.watch(playerProvider).video;
    final rootContext = Navigator.of(context, rootNavigator: true).context;
    final messenger = ScaffoldMessenger.of(context);

    void run(VoidCallback action) {
      Navigator.pop(context);
      Future<void>.delayed(_afterDismiss, action);
    }

    void push(Widget page) => run(() => Navigator.of(rootContext).push(MaterialPageRoute<void>(builder: (_) => page)));

    final items = <(IconData, String, VoidCallback)>[
      (Icons.picture_in_picture_alt, 'Picture in Picture', () => run(engine.togglePip)),
      if (video != null) ...[
        (Icons.playlist_add, 'Add to Playlist', () => run(() => showAddToPlaylistSheet(rootContext, video))),
        (
          Icons.bookmark_border,
          'Add to Watch Later',
          () => run(() async {
                final added = await ref.read(watchLaterRepositoryProvider).toggle(video);
                messenger.showSnackBar(
                  SnackBar(content: Text(added ? 'Added to Watch Later' : 'Removed from Watch Later')),
                );
              }),
        ),
      ],
      (Icons.bookmarks, 'View Library', () => push(const LibraryPage(initialTab: 1))),
      (Icons.bedtime, 'Sleep Timer', () => run(() => showSleepTimerSheet(rootContext))),
      (Icons.airplay, 'AirPlay', () => run(engine.airplay)),
      (Icons.share, 'Share Link', () => run(() => _share(rootContext, ref))),
      (Icons.settings, 'Settings', () => push(const SettingsPage())),
      (Icons.file_upload_outlined, 'Export Data', () => run(() => ref.read(dataTransferProvider).exportJson(rootContext))),
      (
        Icons.file_download_outlined,
        'Import Data',
        () => run(() => messenger.showSnackBar(const SnackBar(content: Text('Share a .json or .csv file to MrPlay to import')))),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        decoration: const BoxDecoration(
          color: PlayerColors.sheet,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          child: ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.only(top: 12, bottom: 12),
            itemCount: items.length + 1,
            separatorBuilder: (_, i) =>
                i == 0 ? const SizedBox(height: 8) : const Divider(color: Colors.white10, height: 1, indent: 56),
            itemBuilder: (_, i) {
              if (i == 0) return const _Grabber();
              final (icon, label, onTap) = items[i - 1];
              return ListTile(
                leading: Icon(icon, color: Colors.white70),
                title: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                trailing: const Icon(Icons.chevron_right, color: Colors.white24),
                onTap: onTap,
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _share(BuildContext context, WidgetRef ref) async {
    final video = ref.read(playerProvider).video;
    final browser = ref.read(browserProvider);
    var url = video?.shareUrl ?? '';
    if (url.isEmpty) url = browser.videoTabUrl ?? browser.browseUrl ?? '';
    if (url.isEmpty) return;
    // iPad presents the share sheet as a popover and needs a source rect.
    final size = MediaQuery.sizeOf(context);
    unawaited(
      Share.share(
        url,
        subject: video?.title ?? 'MrPlay',
        sharePositionOrigin: Rect.fromCenter(center: size.center(Offset.zero), width: 1, height: 1),
      ),
    );
  }
}

class _Grabber extends StatelessWidget {
  const _Grabber();

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
        ),
      );
}
