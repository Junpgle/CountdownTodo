import 'dart:convert';

import 'package:countdown_todo/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('getHistory preserves each formatted record', () async {
    SharedPreferences.setMockInitialValues({
      'history_test-user': [
        jsonEncode({
          'date': '2026-10-17T12:34:56.000',
          'score': 8,
          'duration': 42,
          'details': '第一条',
        }),
        jsonEncode({
          'date': '2026-10-16T08:09:10.000',
          'score': 6,
          'duration': 31,
          'details': '第二条',
        }),
      ],
    });

    final history = await StorageService.getHistory('test-user');

    expect(history, [
      '时间: 2026-10-17 12:34:56\n得分: 8\n用时: 42秒\n详情:\n第一条\n-----------------',
      '时间: 2026-10-16 08:09:10\n得分: 6\n用时: 31秒\n详情:\n第二条\n-----------------',
    ]);
  });

  test('getMathStats reads legacy score text without JSON decoding', () async {
    SharedPreferences.setMockInitialValues({
      'history_test-user': ['corrupt record', '旧记录得分: 80'],
    });

    final stats = await StorageService.getMathStats('test-user');

    expect(stats['accuracy'], 0.8);
    expect(stats['bestTime'], isNull);
    expect(stats['todayCount'], 0);
  });
}
