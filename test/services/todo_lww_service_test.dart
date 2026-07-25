import 'package:countdown_todo/services/todo_lww_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TodoLwwService', () {
    test('an older snapshot cannot win only because its version is higher', () {
      expect(
        TodoLwwService.isIncomingWinner(
          incomingUpdatedAt: 1000,
          incomingVersion: 99,
          currentUpdatedAt: 2000,
          currentVersion: 2,
        ),
        isFalse,
      );
    });

    test('a newer write wins even when an old client has a lower version', () {
      expect(
        TodoLwwService.isIncomingWinner(
          incomingUpdatedAt: 3000,
          incomingVersion: 2,
          currentUpdatedAt: 2000,
          currentVersion: 9,
        ),
        isTrue,
      );
    });

    test('version is used only when timestamps are equal', () {
      expect(
        TodoLwwService.isIncomingWinner(
          incomingUpdatedAt: 2000,
          incomingVersion: 4,
          currentUpdatedAt: 2000,
          currentVersion: 3,
        ),
        isTrue,
      );
      expect(
        TodoLwwService.isIncomingWinner(
          incomingUpdatedAt: 2000,
          incomingVersion: 3,
          currentUpdatedAt: 2000,
          currentVersion: 3,
        ),
        isFalse,
      );
    });

    test('stale recurring tombstones and conflicted snapshots stay local', () {
      expect(
        TodoLwwService.shouldReplaceRecurringSnapshot(
          incomingUpdatedAt: 1000,
          incomingVersion: 999999,
          currentUpdatedAt: 2000,
          currentVersion: 3,
        ),
        isFalse,
      );
      expect(
        TodoLwwService.shouldReplaceRecurringSnapshot(
          incomingUpdatedAt: 3000,
          incomingVersion: 4,
          currentUpdatedAt: 2000,
          currentVersion: 3,
          incomingHasConflict: true,
        ),
        isFalse,
      );
    });
  });
}
