import 'dart:io';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/services/database_helper.dart';
import 'package:countdown_todo/services/device_calendar_read_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class PlanAvailabilityFixture {
  static const username = 'plan-availability-fixture';
  static final day = DateTime(2026, 10, 8);
  static final now = DateTime(2026, 10, 7, 12);
  late Directory directory;
  late Database db;
  late DatabaseFactory previousFactory;
  TargetPlatform? previousPlatform;

  Future<void> initialize() async {
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
    directory = await Directory.systemTemp.createTemp('cdt_plan_availability_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => directory.path,
        );
    await databaseFactory.setDatabasesPath(directory.path);
    await DatabaseHelper.instance.closeDatabase();
    db = await DatabaseHelper.instance.databaseForUser(username);
    DeviceCalendarReadService.debugIsSupportedOverride = false;
    DeviceCalendarReadService.clearSessionReadCacheForTesting();
    await todo('todo-target', '复习高数');
  }

  Future<void> todo(
    String id,
    String title, {
    DateTime? due,
    bool allDay = false,
    DateTime? legacyStart,
    bool done = false,
    Database? targetDatabase,
  }) async {
    await (targetDatabase ?? db).insert('todos', {
      'uuid': id,
      'content': title,
      'created_date':
          legacyStart?.millisecondsSinceEpoch ??
          due?.millisecondsSinceEpoch ??
          0,
      'due_date': due?.millisecondsSinceEpoch,
      'is_all_day': allDay ? 1 : 0,
      'is_completed': done ? 1 : 0,
      'created_at': now.millisecondsSinceEpoch,
      'updated_at': now.millisecondsSinceEpoch,
    });
  }

  Future<void> course(
    String id,
    DateTime date,
    int start,
    int end, {
    String semester = '',
  }) async {
    await db.insert('courses', {
      'uuid': id,
      'course_name': '合成课程',
      'date':
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
      'weekday': date.weekday,
      'start_time': start,
      'end_time': end,
      'week_index': 1,
      'semester_id': semester,
      'created_at': now.millisecondsSinceEpoch,
      'updated_at': now.millisecondsSinceEpoch,
    });
  }

  Future<void> fixed(
    String id,
    DateTime start,
    DateTime end, {
    FixedScheduleStatus status = FixedScheduleStatus.scheduled,
  }) async {
    await db.insert(
      'fixed_schedules',
      FixedScheduleItem(
        id: id,
        title: '合成会议',
        date:
            '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}',
        startTime: start.millisecondsSinceEpoch,
        endTime: end.millisecondsSinceEpoch,
        status: status,
      ).toJson(),
    );
  }

  Future<void> block(TodoPlanBlock item) => db
      .insert('todo_plan_blocks', {
        ...item.toDbJson(),
        'title_snapshot': item.titleSnapshot ?? '合成规划',
      })
      .then((_) {});

  Future<void> dispose() async {
    DeviceCalendarReadService.debugIsSupportedOverride = null;
    DeviceCalendarReadService.clearSessionReadCacheForTesting();
    await DatabaseHelper.instance.closeDatabase();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('countdown_todo/device_calendar_read'),
          null,
        );
    databaseFactory = previousFactory;
    debugDefaultTargetPlatformOverride = previousPlatform;
    await directory.delete(recursive: true);
  }
}
