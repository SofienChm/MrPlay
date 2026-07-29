import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../data/models/platform_model.dart';
import '../widgets/loading_indicator.dart';

class WebViewPage extends StatefulWidget {
  final PlatformModel platform;

  const WebViewPage({
    super.key,
    required this.platform,
  });

  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage> {
  late final WebViewController _controller;
  bool _isLoading = true;
  double _loadingProgress = 0;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            setState(() {
              _isLoading = progress < 100;
              _loadingProgress = progress / 100.0;
            });
          },
          onPageStarted: (String url) {
            setState(() {
              _isLoading = true;
            });
          },
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false;
            });
          },
          onWebResourceError: (WebResourceError error) {
            setState(() {
              _isLoading = false;
            });
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.platform.url));
  }

  void _goBack() {
    _controller.canGoBack().then((canGoBack) {
      if (canGoBack) {
        _controller.goBack();
      } else if (mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Custom browser bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey.shade900,
                border: Border(
                  bottom: BorderSide(
                    color: Colors.grey.shade800,
                  ),
                ),
              ),
              child: Row(
                children: [
                  // Back button
                  IconButton(
                    onPressed: () {
                      _goBack();
                    },
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    tooltip: 'Back',
                  ),
                  // Forward button
                  IconButton(
                    onPressed: () async {
                      if (await _controller.canGoForward()) {
                        await _controller.goForward();
                      }
                    },
                    icon: const Icon(Icons.arrow_forward, color: Colors.white),
                    tooltip: 'Forward',
                  ),
                  // Title/URL
                  Expanded(
                    child: Text(
                      widget.platform.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  // Reload
                  IconButton(
                    onPressed: () => _controller.reload(),
                    icon: const Icon(Icons.refresh, color: Colors.white),
                    tooltip: 'Reload',
                  ),
                  // Share
                  IconButton(
                    onPressed: () {
                      // TODO: Implement share (Phase 4)
                    },
                    icon: const Icon(Icons.share, color: Colors.white),
                    tooltip: 'Share',
                  ),
                ],
              ),
            ),

            // Loading progress bar
            if (_isLoading)
              LinearProgressIndicator(
                value: _loadingProgress > 0 ? _loadingProgress : null,
                backgroundColor: Colors.grey.shade800,
                valueColor: const AlwaysStoppedAnimation<Color>(
                  Color(0xFF00C853),
                ),
              ),

            // WebView
            Expanded(
              child: Stack(
                children: [
                  WebViewWidget(controller: _controller),
                  if (_isLoading && _loadingProgress == 0)
                    const LoadingIndicator(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
