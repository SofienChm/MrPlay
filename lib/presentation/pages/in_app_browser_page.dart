import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Lightweight in-app browser used for pages like the Privacy Policy so
/// users never leave MrPlay.
class InAppBrowserPage extends StatefulWidget {
  const InAppBrowserPage({super.key, required this.url, this.title});

  final String url;
  final String? title;

  @override
  State<InAppBrowserPage> createState() => _InAppBrowserPageState();
}

class _InAppBrowserPageState extends State<InAppBrowserPage> {
  double _progress = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? 'MrPlay'),
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_progress < 1)
            LinearProgressIndicator(value: _progress, minHeight: 2),
          Expanded(
            child: InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(widget.url)),
              onProgressChanged: (_, progress) {
                setState(() => _progress = progress / 100);
              },
            ),
          ),
        ],
      ),
    );
  }
}
