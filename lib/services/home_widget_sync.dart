import 'dart:convert';

import 'package:home_widget/home_widget.dart';

import '../core/config/app_info.dart';
import '../core/utils/log.dart';
import '../data/models/models.dart';

/// Pushes recent videos to the home-screen widget. The widget decodes
/// `[[String: String]]`, so every value is sent as a string.
class HomeWidgetSync {
  bool _configured = false;

  Future<void> push(List<HistoryEntry> entries) async {
    try {
      if (!_configured) {
        await HomeWidget.setAppGroupId(AppInfo.appGroupId);
        _configured = true;
      }
      final data = [
        for (final e in entries.take(10))
          {
            'title': e.title,
            'url': e.url,
            'platform': e.platform,
            'date': e.watchedAt.millisecondsSinceEpoch.toString(),
          },
      ];
      await HomeWidget.saveWidgetData<String>('recent', jsonEncode(data));
      await HomeWidget.updateWidget(iOSName: AppInfo.homeWidgetKind);
    } on Exception catch (e) {
      log('home widget update failed: $e');
    }
  }

  /// URLs opened from the widget (`mrplay://open?url=...`).
  Stream<String> get openedUrls async* {
    final initial = await HomeWidget.initiallyLaunchedFromHomeWidget();
    final first = _urlOf(initial);
    if (first != null) yield first;
    await for (final uri in HomeWidget.widgetClicked) {
      final url = _urlOf(uri);
      if (url != null) yield url;
    }
  }

  static String? _urlOf(Uri? uri) {
    final url = uri?.queryParameters['url'];
    return url == null || url.isEmpty ? null : url;
  }
}
