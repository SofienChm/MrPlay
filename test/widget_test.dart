import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mrplay/app.dart';

void main() {
  late Directory hiveDir;

  setUpAll(() {
    hiveDir = Directory.systemTemp.createTempSync('mrplay_hive_test');
    Hive.init(hiveDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    if (hiveDir.existsSync()) hiveDir.deleteSync(recursive: true);
  });

  testWidgets('App renders hub page', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: MrPlayApp()));
    expect(find.text('MrPlay'), findsOneWidget);
  });
}
