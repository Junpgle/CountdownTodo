import 'package:flutter_test/flutter_test.dart';
import 'package:countdown_todo/services/database_schema_history.dart';

void main() {
  test('database schema history covers every version newest first', () {
    final versions =
        DatabaseSchemaHistory.changes.map((change) => change.version).toList();

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
}
