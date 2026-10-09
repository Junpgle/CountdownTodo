import 'dart:io';

import 'package:countdown_todo/features/finance/models/finance_models.dart';
import 'package:countdown_todo/features/finance/services/finance_storage.dart';
import 'package:countdown_todo/features/thirty_day_challenge/repositories/thirty_day_challenge_repository.dart';
import 'package:countdown_todo/services/chat_storage_service.dart';
import 'package:countdown_todo/services/database_helper.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Disposable database and preferences; never loads an actual user account.
class SearchScopeFixture {
  static const username = 'search_scope_fixture';
  static final day = DateTime(2026, 10, 7, 12);
  late Directory directory;
  late Database db;
  late DatabaseFactory previousFactory;
  TargetPlatform? previousPlatform;

  Future<void> initialize({int rows = 1}) async {
    SharedPreferences.setMockInitialValues({'current_login_user': username});
    previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    sqfliteFfiInit();
    try {
      previousFactory = databaseFactory;
    } on StateError {
      previousFactory = databaseFactoryFfiNoIsolate;
    }
    databaseFactory = databaseFactoryFfiNoIsolate;
    directory = await Directory.systemTemp.createTemp('cdt_search_scope_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => directory.path,
        );
    await databaseFactory.setDatabasesPath(directory.path);
    await DatabaseHelper.instance.closeDatabase();
    db = await DatabaseHelper.instance.database;
    FinanceStorage.databaseOverride = db;
    final now = day.millisecondsSinceEpoch;
    final batch = db.batch();
    for (var i = 0; i < rows; i++) {
      batch.insert('todos', {
        'uuid': 'todo_$i',
        'content': '取回餐具 $i',
        'remark': '午餐 报销 $i',
        'due_date': now,
        'created_date': now,
        'created_at': now,
        'updated_at': now,
      });
      batch.insert('journal_entries', {
        'uuid': 'journal_$i',
        'title': '午餐日记 $i',
        'content': '午餐 报销 $i',
        'occurred_at': now,
        'created_at': now,
        'updated_at': now,
      });
      batch.insert('time_logs', {
        'uuid': 'log_$i',
        'title': '午餐时间 $i',
        'remark': '午餐 报销 $i',
        'start_time': now,
        'end_time': now + 1800000,
        'created_at': now,
        'updated_at': now,
        'device_id': 'fixture',
        'team_uuid': '',
      });
    }
    batch.insert('courses', {
      'uuid': 'course',
      'course_name': '午餐营养课',
      'date': '2026-10-07',
      'weekday': 3,
      'start_time': 1,
      'end_time': 2,
      'week_index': 1,
      'created_at': now,
      'updated_at': now,
    });
    batch.insert('fixed_schedules', {
      'uuid': 'schedule',
      'title': '午餐会议',
      'date': '2026-10-07',
      'start_time': 720,
      'end_time': 780,
      'created_at': now,
      'updated_at': now,
    });
    batch.insert('todo_plan_blocks', {
      'uuid': 'block',
      'title_snapshot': '午餐准备',
      'start_time': now,
      'end_time': now + 1800000,
      'planned_minutes': 30,
      'calendar_event_id': '',
      'created_at': now,
      'updated_at': now,
    });
    batch.insert('countdowns', {
      'uuid': 'countdown',
      'title': '午餐聚会',
      'target_time': now,
      'created_at': now,
      'updated_at': now,
    });
    batch.insert('todo_groups', {
      'uuid': 'group',
      'name': '午餐安排',
      'created_at': now,
      'updated_at': now,
    });
    batch.insert('habit_goals', {
      'uuid': 'habit',
      'name': '午餐记录',
      'source_ids': '[]',
      'created_at': now,
      'updated_at': now,
    });
    batch.insert('habit_checkins', {
      'uuid': 'checkin',
      'habit_uuid': 'habit',
      'occurred_at': now,
      'logical_date': '2026-10-07',
      'value': 1,
      'note': '午餐打卡',
      'created_at': now,
      'updated_at': now,
    });
    await batch.commit(noResult: true);
    for (var i = 0; i < rows; i++) {
      await FinanceStorage.saveTransaction(
        FinanceTransaction(
          uuid: 'finance_$i',
          type: FinanceTransactionType.expense,
          amountMinor: 2850,
          transactionDate: '2026-10-07',
          merchant: '午餐 $i',
          note: '午餐 报销 $i',
          occurredAt: now,
        ),
      );
    }
    await ChatStorageService.saveSessions([
      ChatSession(id: 'chat', title: '午餐对话', createdAt: day, updatedAt: day),
    ]);
    await ThirtyDayChallengeRepository.startNewChallenge(
      title: '午餐挑战',
      taskTitles: ['午餐后散步', '整理房间'],
    );
  }

  Future<void> dispose() async {
    FinanceStorage.databaseOverride = null;
    await DatabaseHelper.instance.closeDatabase();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    databaseFactory = previousFactory;
    debugDefaultTargetPlatformOverride = previousPlatform;
    await directory.delete(recursive: true);
  }
}
