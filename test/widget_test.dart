import 'package:flutter_test/flutter_test.dart';
import 'package:mrplay/app.dart';

void main() {
  testWidgets('App renders hub page', (WidgetTester tester) async {
    await tester.pumpWidget(const MrPlayApp());
    expect(find.text('MrPlay'), findsOneWidget);
  });
}
