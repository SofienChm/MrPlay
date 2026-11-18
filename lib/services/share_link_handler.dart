import 'package:receive_sharing_intent/receive_sharing_intent.dart';

class ShareLinkHandler {
  ShareLinkHandler._();

  static final ShareLinkHandler instance = ShareLinkHandler._();

  void Function(String url)? _onLink;
  void Function(String filePath, String type)? _onImport;

  /// Paths already delivered this session. Some platforms deliver the initial
  /// shared media on both `getInitialMedia()` and `getMediaStream()`, which
  /// would otherwise open the link resolver / trigger the import twice.
  final Set<String> _handledPaths = <String>{};

  void init({
    required void Function(String url) onLink,
    void Function(String filePath, String type)? onImport,
  }) {
    _onLink = onLink;
    _onImport = onImport;
    ReceiveSharingIntent.instance.getMediaStream().listen(_handle);
    ReceiveSharingIntent.instance.getInitialMedia().then(_handle);
  }

  void _handle(List<SharedMediaFile> files) {
    for (final file in files) {
      // De-duplicate the initial-media / media-stream overlap: a file already
      // handled this session is skipped.
      if (!_handledPaths.add(file.path)) continue;

      final isLink =
          file.type == SharedMediaType.url || file.type == SharedMediaType.text;
      if (isLink && file.path.isNotEmpty) {
        _onLink?.call(file.path);
        continue;
      }

      if (_onImport != null && file.path.isNotEmpty) {
        final ext = file.path.toLowerCase();
        if (ext.endsWith('.json')) {
          _onImport!(file.path, 'json');
        } else if (ext.endsWith('.csv')) {
          _onImport!(file.path, 'csv');
        }
      }
    }
  }
}
