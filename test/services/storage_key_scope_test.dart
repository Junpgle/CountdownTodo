import 'package:countdown_todo/services/storage/storage_key_scope.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps legacy global key for an empty username', () {
    expect(StorageKeyScope.scoped('user_countdowns', null), 'user_countdowns');
    expect(StorageKeyScope.scoped('user_countdowns', ''), 'user_countdowns');
  });

  test('scopes data keys by username', () {
    expect(
      StorageKeyScope.scoped('user_countdowns', 'alice'),
      'user_countdowns_alice',
    );
    expect(
      StorageKeyScope.scoped('user_countdowns', 'alice@example.com'),
      'user_countdowns_alice@example.com',
    );
  });
}
