import 'package:countdown_todo/features/journal/screens/journal_home_screen.dart';
import 'package:countdown_todo/features/journal/services/journal_storage.dart';
import 'package:countdown_todo/services/database_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('纯空白搜索按未搜索状态显示空日记提示', (tester) async {
    final database = (await tester.runAsync(
      () => databaseFactoryFfi.openDatabase(inMemoryDatabasePath),
    ))!;
    addTearDown(() => database.close());
    await tester.runAsync(() => DatabaseHelper.ensureJournalSchema(database));

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: JournalHomeScreen(
          username: 'journal-search-test',
          storage: JournalStorage.forTesting(
            databaseLoader: (_) async => database,
          ),
        ),
      ),
    );
    final emptyState = find.text('今天不写也没关系');
    await _waitFor(tester, () => emptyState.evaluate().isNotEmpty);

    await tester.tap(find.byTooltip('搜索日记'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.widgetWithText(FilledButton, '搜索'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(emptyState, findsOneWidget);
    expect(find.text('没有找到相关日记'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _waitFor(WidgetTester tester, bool Function() ready) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (ready()) {
      await tester.pump();
      return;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  fail('页面未出现预期的日记状态');
}
