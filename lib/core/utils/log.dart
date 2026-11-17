import 'package:flutter/foundation.dart';

/// Tagged debug log. Compiled to a no-op in release builds.
void log(String message, {String tag = 'MrPlay'}) {
  if (kReleaseMode) return;
  debugPrint('[$tag] $message');
}
