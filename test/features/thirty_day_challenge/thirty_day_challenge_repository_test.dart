import 'package:countdown_todo/features/thirty_day_challenge/models/thirty_day_challenge.dart';
import 'package:countdown_todo/features/thirty_day_challenge/repositories/thirty_day_challenge_repository.dart';
import 'package:countdown_todo/services/storage/storage_key_scope.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'an explicitly empty recovery field clears a stale corrupt-state copy',
    () async {
      const username = 'challenge-restore-test';
      final prefs = await SharedPreferences.getInstance();
      final stateKey = StorageKeyScope.scoped(
        'thirty_day_self_challenge_v1',
        username,
      );
      await prefs.setString(stateKey, '{broken json');

      await ThirtyDayChallengeRepository.load(username: username);
      expect(
        await ThirtyDayChallengeRepository.getCorruptStateBackup(
          username: username,
        ),
        '{broken json',
      );

      final restoredState = ThirtyDayChallengeState.custom(
        title: '恢复后的挑战',
        taskTitles: ['完成第一项'],
      );
      await ThirtyDayChallengeRepository.importBackup({
        'state': restoredState.toJson(),
        'started': true,
        'corrupt_state_backup': '',
      }, username: username);

      expect(
        await ThirtyDayChallengeRepository.getCorruptStateBackup(
          username: username,
        ),
        isNull,
      );
      expect(
        (await ThirtyDayChallengeRepository.load(username: username))
            .challengeTitle,
        '恢复后的挑战',
      );
    },
  );

  test('importing a backup with a recovery copy preserves that copy', () async {
    const username = 'challenge-corrupt-backup-test';
    final state = ThirtyDayChallengeState.custom(
      title: '可恢复挑战',
      taskTitles: ['完成第一项'],
    );

    await ThirtyDayChallengeRepository.importBackup({
      'state': state.toJson(),
      'started': true,
      'corrupt_state_backup': '{original broken json',
    }, username: username);

    expect(
      await ThirtyDayChallengeRepository.getCorruptStateBackup(
        username: username,
      ),
      '{original broken json',
    );
  });
}
