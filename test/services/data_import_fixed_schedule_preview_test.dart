import 'dart:convert';

import 'package:countdown_todo/services/data_import_service.dart';
import 'package:countdown_todo/services/storage/storage_key_scope.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('backup preview recognizes fixed schedules as an independent type',
      () async {
    final preview = await DataImportService.parseJsonString(
      jsonEncode({
        'version': 2,
        'exportedAt': DateTime(2026, 7, 20).millisecondsSinceEpoch,
        'data': {
          'fixed_schedules': [
            {
              'uuid': 'exam-1',
              'title': '高数考试',
              'date': '2026-07-22',
              'team_uuid': 'team-1',
            },
          ],
        },
      }),
    );

    expect(preview.fileVersion, 2);
    expect(preview.types, hasLength(1));
    expect(preview.types.single.key, 'fixed_schedules');
    expect(preview.types.single.label, '固定日程');
    expect(preview.types.single.count, 1);
    expect(preview.types.single.teamCount, 1);
  });

  test('challenge backup keys are scoped to the restored account', () {
    const challengeKeys = [
      'thirty_day_self_challenge_v1',
      'thirty_day_self_challenge_v1_intro_seen',
      'thirty_day_self_challenge_v1_started',
      'thirty_day_self_challenge_v1_paused',
      'thirty_day_self_challenge_v1_habit_center_promotion_dismissed',
    ];

    for (final key in challengeKeys) {
      expect(StorageKeyScope.isChallengeDataKey(key), isTrue, reason: key);
      expect(StorageKeyScope.scoped(key, 'alice'), '${key}_alice');
    }
  });

  test('backup preview lists challenge data separately from settings',
      () async {
    final preview = await DataImportService.parseJsonString(
      jsonEncode({
        'version': 2,
        'exportedAt': DateTime(2026, 10, 2).millisecondsSinceEpoch,
        'data': {
          'thirty_day_challenge': {
            'started': true,
            'state': {
              'challenge_title': '周末阅读计划',
              'tasks': [
                {'id': 1, 'original_title': '读一本书'},
                {'id': 2, 'original_title': '写下感想'},
              ],
            },
          },
        },
      }),
    );

    expect(preview.types, hasLength(1));
    expect(preview.types.single.key, 'thirty_day_challenge');
    expect(preview.types.single.label, '30 天挑战');
    expect(preview.types.single.count, 2);
  });

  test('backup preview rejects a malformed challenge recovery copy', () async {
    await expectLater(
      DataImportService.parseJsonString(
        jsonEncode({
          'version': 2,
          'exportedAt': DateTime(2026, 10, 2).millisecondsSinceEpoch,
          'data': {
            'thirty_day_challenge': {
              'started': true,
              'state': {
                'challenge_title': '周末阅读计划',
                'tasks': [
                  {'id': 1, 'original_title': '读一本书'},
                ],
              },
              'corrupt_state_backup': 123,
            },
          },
        }),
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
