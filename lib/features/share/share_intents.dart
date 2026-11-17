import 'dart:async';

import 'package:receive_sharing_intent/receive_sharing_intent.dart';

/// Links and data files shared to MrPlay from other apps.
class ShareIntents {
  StreamSubscription<List<SharedMediaFile>>? _sub;

  void listen({
    required void Function(String url) onLink,
    required void Function(String path) onFile,
  }) {
    void handle(List<SharedMediaFile> files) {
      for (final file in files) {
        final path = file.path;
        if (path.isEmpty) continue;
        if (file.type == SharedMediaType.url || file.type == SharedMediaType.text) {
          onLink(path);
          continue;
        }
        final lower = path.toLowerCase();
        if (lower.endsWith('.json') || lower.endsWith('.csv')) onFile(path);
      }
    }

    _sub = ReceiveSharingIntent.instance.getMediaStream().listen(handle);
    unawaited(ReceiveSharingIntent.instance.getInitialMedia().then(handle));
  }

  void dispose() {
    unawaited(_sub?.cancel());
    _sub = null;
  }
}
