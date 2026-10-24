import 'dart:convert';
import 'dart:io';

import 'package:countdown_todo/models/data_export_models.dart';
import 'package:countdown_todo/services/data_import_service.dart';
import 'package:countdown_todo/services/database_helper.dart';
import 'package:countdown_todo/services/pomodoro_service.dart';
import 'package:countdown_todo/storage_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const username = 'data-import-scope-result-fixture';
  late Directory directory;
  late DatabaseFactory previousFactory;

  setUpAll(() async {
    sqfliteFfiInit();
    try {
      previousFactory = databaseFactory;
    } on StateError {
      previousFactory = databaseFactoryFfiNoIsolate;
    }
    databaseFactory = databaseFactoryFfiNoIsolate;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    directory = await Directory.systemTemp.createTemp(
      'cdt_import_scope_result_',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => directory.path,
        );
    await databaseFactory.setDatabasesPath(directory.path);
  });

  setUp(() async {
    await DatabaseHelper.instance.closeDatabase();
    SharedPreferences.setMockInitialValues({
      'current_login_user': username,
      'current_user_id': 0,
      'minor_mode_enabled': false,
    });
    await DatabaseHelper.instance.databaseForUser(username);
  });

  tearDown(() async {
    await DatabaseHelper.instance.closeDatabase();
  });

  tearDownAll(() async {
    await DatabaseHelper.instance.closeDatabase();
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    databaseFactory = previousFactory;
    await directory.delete(recursive: true);
  });

  String backup(Map<String, dynamic> data) => jsonEncode({
    'version': 2,
    'exportedAt': DateTime(2026, 10, 24).millisecondsSinceEpoch,
    'username': username,
    'userId': 0,
    'data': data,
  });

  test('设置结果只统计实际应用的支持键，不混入普通记录新增数', () async {
    final result = await DataImportService.importDataFromJsonString(
      username: username,
      jsonString: backup({
        'settings': {
          'round46_bool_preference': true,
          'round46_json_preference': {'mode': 'dense'},
          StorageService.keyAuthToken: 'must-not-import',
        },
      }),
      options: const ImportOptions(
        uuidStrategy: UuidStrategy.regenerate,
        selectedScopes: {ImportDataScope.settings},
      ),
    );

    expect(result.success, isTrue, reason: result.errorMessage);
    expect(result.scopeSummaries, hasLength(1));
    expect(result.scopeSummaries.single.scope, ImportDataScope.settings);
    expect(
      result.scopeSummaries.single.kind,
      ImportScopeRestoreKind.settingsApplied,
    );
    expect(result.scopeSummaries.single.detailCount, 2);
    expect(result.importedCount, 1); // Legacy aggregate stays API-compatible.

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('round46_bool_preference'), isTrue);
    expect(prefs.getString('round46_json_preference'), '{"mode":"dense"}');
    expect(prefs.getString(StorageService.keyAuthToken), isNull);
  });

  test('普通记录回执按数据域汇总导入器的新增、更新和跳过数', () async {
    await PomodoroService.saveTags([
      PomodoroTag(
        uuid: 'round46-update-tag',
        name: '旧标签',
        createdAt: 1,
        updatedAt: 1,
      ),
      PomodoroTag(
        uuid: 'round46-skip-tag',
        name: '保留标签',
        createdAt: 1,
        updatedAt: 10,
      ),
    ]);

    final result = await DataImportService.importDataFromJsonString(
      username: username,
      jsonString: backup({
        'pomodoro_tags': [
          {
            'uuid': 'round46-new-tag',
            'name': '新标签',
            'created_at': 1,
            'updated_at': 2,
          },
          {
            'uuid': 'round46-update-tag',
            'name': '更新标签',
            'created_at': 1,
            'updated_at': 20,
          },
          {
            'uuid': 'round46-skip-tag',
            'name': '过期标签',
            'created_at': 1,
            'updated_at': 5,
          },
        ],
      }),
      options: const ImportOptions(
        selectedScopes: {ImportDataScope.productivity},
      ),
    );

    expect(result.success, isTrue, reason: result.errorMessage);
    expect(result.scopeSummaries, hasLength(1));
    final summary = result.scopeSummaries.single;
    expect(summary.scope, ImportDataScope.productivity);
    expect(summary.kind, ImportScopeRestoreKind.recordChanges);
    expect(summary.importedCount, 1);
    expect(summary.updatedCount, 1);
    expect(summary.skippedCount, 1);
    expect(result.importedCount, 1);
    expect(result.updatedCount, 1);
    expect(result.skippedCount, 1);
  });

  test('挑战回执说明恢复状态和任务数，不计为新增记录', () async {
    final result = await DataImportService.importDataFromJsonString(
      username: username,
      jsonString: backup({
        'thirty_day_challenge': {
          'started': true,
          'state': {
            'challenge_title': '专注练习',
            'tasks': [
              {'id': 1, 'original_title': '阅读'},
              {'id': 2, 'original_title': '复盘'},
            ],
          },
        },
      }),
      options: const ImportOptions(
        uuidStrategy: UuidStrategy.regenerate,
        selectedScopes: {ImportDataScope.challenge},
      ),
    );

    expect(result.success, isTrue, reason: result.errorMessage);
    expect(result.scopeSummaries, hasLength(1));
    expect(result.scopeSummaries.single.scope, ImportDataScope.challenge);
    expect(
      result.scopeSummaries.single.kind,
      ImportScopeRestoreKind.challengeRestored,
    );
    expect(result.scopeSummaries.single.detailCount, 2);
    expect(result.scopeSummaries.single.importedCount, 0);
    expect(result.importedCount, 2); // Legacy aggregate stays API-compatible.
  });
}
