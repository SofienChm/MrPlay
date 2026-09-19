import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../core/constants/content_blocker_js.dart';

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

  static bool _isAdDomain(String host) {
    final h = host.toLowerCase();
    const adDomains = [
      'doubleclick.net',
      'googlesyndication.com',
      'googleadservices.com',
      'google-analytics.com',
      'adservice.google.com',
      'pagead2.googlesyndication.com',
      'tpc.googlesyndication.com',
    ];
    for (final d in adDomains) {
      if (h == d || h.endsWith('.$d')) return true;
    }
    return false;
  }

  static bool _isAllowedPlatformDomain(String host) {
    final h = host.toLowerCase();
    const allowedDomains = [
      'youtube.com',
      'youtu.be',
      'kick.com',
      'twitch.tv',
      '9gag.com',
      'dailymotion.com',
      'ifunny.co',
      'rumble.com',
      'music.youtube.com',
    ];
    for (final d in allowedDomains) {
      if (h == d || h.endsWith('.$d')) return true;
    }
    return false;
  }

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
              initialUserScripts: UnmodifiableListView([
                UserScript(
                  source: ContentBlockerJS.popupBlockerScript,
                  injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                  forMainFrameOnly: false,
                ),
              ]),
              onProgressChanged: (_, progress) {
                setState(() => _progress = progress / 100);
              },
              onCreateWindow: (controller, createWindowAction) async {
                final url = createWindowAction.request.url;
                if (url == null) return false;
                final host = url.host;
                if (_isAdDomain(host)) return false;
                if (!_isAllowedPlatformDomain(host)) return false;
                controller.loadUrl(urlRequest: URLRequest(url: url));
                return false;
              },
            ),
          ),
        ],
      ),
    );
  }
}
