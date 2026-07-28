import 'dart:async';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../core/constants/youtube_js.dart';

class PersistentWebView extends StatefulWidget {
  const PersistentWebView({super.key});

  @override
  State<PersistentWebView> createState() => PersistentWebViewState();
}

class PersistentWebViewState extends State<PersistentWebView> {
  late final WebViewController controller;
  bool isReady = false;
  bool _isLoading = false;
  Timer? _loadingTimer;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  @override
  void dispose() {
    _loadingTimer?.cancel();
    super.dispose();
  }

  void _initWebView() {
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) {
              setState(() => _isLoading = true);
            }
            _loadingTimer?.cancel();
            _loadingTimer = Timer(const Duration(seconds: 3), () {
              if (mounted) {
                setState(() => _isLoading = false);
              }
            });
          },
          onPageFinished: (String url) {
            _loadingTimer?.cancel();
            if (mounted) {
              setState(() => _isLoading = false);
            }
            if (url.contains('youtube.com')) {
              controller.runJavaScript(YouTubeJS.adBlockScript);
            }
          },
        ),
      );
  }

  void loadUrl(String url) {
    _loadingTimer?.cancel();
    controller.loadRequest(Uri.parse(url));
    setState(() {
      isReady = true;
      _isLoading = true;
    });
    _loadingTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    });
  }

  Widget _buildFullWebView() {
    return Padding(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
      child: WebViewWidget(controller: controller),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!isReady) return const SizedBox.shrink();

    return SizedBox(
      height: MediaQuery.of(context).size.height,
      width: double.infinity,
      child: Stack(
        children: [
          _buildFullWebView(),
          if (_isLoading)
            Positioned(
              top: MediaQuery.of(context).padding.top + 60,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
                  ),
                ),
              ),
            ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 10,
            child: GestureDetector(
              onTap: () {
                controller.loadRequest(Uri.parse('about:blank'));
                setState(() {
                  isReady = false;
                  _isLoading = false;
                });
              },
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 24),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
