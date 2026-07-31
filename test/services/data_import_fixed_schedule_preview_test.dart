import 'dart:convert';

import 'package:countdown_todo/services/data_import_service.dart';
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
}
