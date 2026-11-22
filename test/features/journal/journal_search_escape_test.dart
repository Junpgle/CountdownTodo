import 'package:countdown_todo/features/journal/models/journal_entry.dart';
import 'package:countdown_todo/features/journal/services/journal_storage.dart';
import 'package:countdown_todo/services/database_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Database database;
  late JournalStorage storage;
  const accountId = 'journal-like-escape-test';

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await DatabaseHelper.ensureJournalSchema(database);
    storage = JournalStorage.forTesting(databaseLoader: (_) async => database);

    await storage.saveEntry(
      JournalEntry(
        id: 'percent-match',
        title: '进度 50%',
        content: '完成一半',
        occurredAt: DateTime(2026, 11, 20, 10),
      ),
      const [],
      accountId: accountId,
    );
    await storage.saveEntry(
      JournalEntry(
        id: 'percent-nonmatch',
        title: '进度 500',
        content: '没有百分号',
        occurredAt: DateTime(2026, 11, 21, 10),
      ),
      const [],
      accountId: accountId,
    );
    await storage.saveEntry(
      JournalEntry(
        id: 'underscore-nonmatch',
        title: 'axb tag',
        content: '没有下划线',
        occurredAt: DateTime(2026, 11, 22, 10),
      ),
      const [],
      accountId: accountId,
    );
  });

  tearDown(() => database.close());

  test('loadEntries escapes % and _ wildcards in LIKE searches', () async {
    final percentResults = await storage.loadEntries(
      accountId: accountId,
      searchQuery: '50%',
    );
    expect(percentResults.map((e) => e.id).toList(), ['percent-match']);

    final underscoreResults = await storage.loadEntries(
      accountId: accountId,
      searchQuery: 'a_b',
    );
    expect(underscoreResults, isEmpty);
  });
}
