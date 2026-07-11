import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/js_snippets.dart';

class NavigationUtils {
  NavigationUtils._();

  static Future<void> handleBackNavigation({
    required BuildContext context,
    required InAppWebViewController? webViewController,
    required bool isOnWatchPage,
    required bool isMiniPlayerOpen,
    required bool showMiniPlayer,
    required VoidCallback onCloseMiniPlayer,
    required VoidCallback onClose,
  }) async {
    if (showMiniPlayer) {
      onCloseMiniPlayer();
      return;
    }
    if (isOnWatchPage && !isMiniPlayerOpen) {
      await webViewController?.evaluateJavascript(
        source: JsSnippets.nativeHeaderBack,
      );
    } else if (webViewController != null &&
        await webViewController.canGoBack()) {
      await webViewController.goBack();
    } else {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('auto_launch_youtube', false);
      if (!context.mounted) return;
      onClose();
    }
  }
}
