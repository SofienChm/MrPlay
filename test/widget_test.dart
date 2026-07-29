import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mrplay/app.dart';
import 'package:mrplay/data/repositories/favorites_repository.dart';
import 'package:mrplay/data/repositories/settings_repository.dart';

void main() {
  testWidgets('App renders hub page', (WidgetTester tester) async {
    await Hive.initFlutter();
    final favoritesRepo = FavoritesRepository();
    final settingsRepo = SettingsRepository();
    await favoritesRepo.init();
    await settingsRepo.init();

    await tester.pumpWidget(MrPlayApp(
      favoritesRepository: favoritesRepo,
      settingsRepository: settingsRepo,
    ));
    expect(find.text('MrPlay'), findsOneWidget);
  });
}
