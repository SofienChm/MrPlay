import 'package:flutter_test/flutter_test.dart';
import 'package:mrplay/main.dart';

void main() {
  testWidgets('App renders hub screen by default', (WidgetTester tester) async {
    await tester.pumpWidget(const MrPlayApp(autoLaunchYouTube: false));
    expect(find.byType(MrPlayApp), findsOneWidget);
  });

  testWidgets('App renders browser screen when auto-launch is set', (WidgetTester tester) async {
    await tester.pumpWidget(const MrPlayApp(autoLaunchYouTube: true));
    expect(find.byType(MrPlayApp), findsOneWidget);
  });
}
