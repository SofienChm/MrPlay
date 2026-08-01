import 'package:receive_sharing_intent/receive_sharing_intent.dart';

class ShareLinkHandler {
  ShareLinkHandler._();

  static final ShareLinkHandler instance = ShareLinkHandler._();

  void init(void Function(String url) onOpen) {
    ReceiveSharingIntent.instance.getMediaStream().listen(
      (files) => _handle(files, onOpen),
    );
    ReceiveSharingIntent.instance.getInitialMedia().then(
      (files) => _handle(files, onOpen),
    );
  }

  void _handle(List<SharedMediaFile> files, void Function(String url) onOpen) {
    for (final file in files) {
      final isLink =
          file.type == SharedMediaType.url || file.type == SharedMediaType.text;
      if (isLink && file.path.isNotEmpty) {
        onOpen(file.path);
      }
    }
  }
}
