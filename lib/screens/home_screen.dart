import 'package:flutter/material.dart';
import 'launcher_hub_screen.dart';
import 'browser_screen.dart';

class HomeScreen extends StatefulWidget {
  final String? initialUrl;

  const HomeScreen({super.key, this.initialUrl});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _activeUrl;
  BrowserScreen? _browser;

  @override
  void initState() {
    super.initState();
    if (widget.initialUrl != null) {
      _activeUrl = widget.initialUrl;
      _browser = BrowserScreen(
        targetUrl: widget.initialUrl!,
        onClose: _closePlayer,
      );
    }
  }

  void _openBrowser(String url) {
    _browser = BrowserScreen(
      targetUrl: url,
      onClose: _closePlayer,
    );
    setState(() => _activeUrl = url);
  }

  void _closePlayer() {
    setState(() => _activeUrl = null);
  }

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: _activeUrl != null ? 1 : 0,
      children: [
        LauncherHubScreen(onOpenBrowser: _openBrowser),
        _browser ?? const SizedBox.shrink(),
      ],
    );
  }
}
