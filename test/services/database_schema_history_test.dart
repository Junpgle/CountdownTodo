import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:countdown_todo/services/database_schema_history.dart';
import 'package:countdown_todo/services/database_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test('database schema history covers every version newest first', () {
    final versions = DatabaseSchemaHistory.changes
        .map((change) => change.version)
        .toList();

    expect(versions.first, DatabaseSchemaHistory.currentVersion);
    expect(
      versions,
      List<int>.generate(
        DatabaseSchemaHistory.currentVersion,
        (index) => DatabaseSchemaHistory.currentVersion - index,
      ),
    );
  });

  test('every database schema version has a readable changelog', () {
    for (final change in DatabaseSchemaHistory.changes) {
      expect(change.title.trim(), isNotEmpty);
      expect(change.changes, isNotEmpty);
      expect(change.changes.every((item) => item.trim().isNotEmpty), isTrue);
    }
  });

  test('v58 todo tables migrate to skip state without changing old rows', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await db.execute('CREATE TABLE todos (uuid TEXT PRIMARY KEY)');
    await db.execute('CREATE TABLE todo_completions (todo_uuid TEXT, user_id INTEGER, is_completed INTEGER, PRIMARY KEY(todo_uuid, user_id))');
    await db.insert('todos', {'uuid': 'old-todo'});
    await db.insert('todo_completions', {
      'todo_uuid': 'old-todo',
      'user_id': 7,
      'is_completed': 1,
    });

    await DatabaseHelper.ensureTodoSkipStateSchema(db);

    final todo = (await db.query('todos')).single;
    final completion = (await db.query('todo_completions')).single;
    expect(todo['is_skipped'], 0);
    expect(todo['is_skipped_sync_pending'], 0);
    expect(completion['is_completed'], 1);
    expect(completion['is_skipped'], 0);
    expect(completion['is_skipped_sync_pending'], 0);
  });
}
