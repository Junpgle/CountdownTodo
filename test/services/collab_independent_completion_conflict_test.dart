import 'dart:convert';
import 'dart:io';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/services/database_helper.dart';
import 'package:countdown_todo/storage_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late String username;
  var sequence = 0;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    directory = await Directory.systemTemp.createTemp(
      'collab-completion-test-',
    );
    await databaseFactory.setDatabasesPath(directory.path);
  });

  setUp(() async {
    username = 'collab-user-${sequence++}';
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await prefs.setString('current_login_user', username);
    await prefs.setInt('current_user_id', 7);
    await prefs.setBool('migration_marker_${username}_v4', true);
    await prefs.setBool('cleanup_done_${username}_v4_repair', true);
    await prefs.setBool('conflict_detection_enabled', false);
  });

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await DatabaseHelper.instance.closeDatabase();
  });

  tearDownAll(() async {
    debugDefaultTargetPlatformOverride = null;
    await directory.delete(recursive: true);
  });

  test('toggling collabType=1 completion marks _independent_completion_only and preserves version', () async {
    final original = TodoItem(
      id: '00000000-0000-4000-8000-00000000c001',
      title: '各自完成团队待办',
      teamUuid: 'team-uuid-1',
      collabType: 1,
      isDone: false,
      version: 3,
      updatedAt: 1000,
      createdAt: 1000,
    );
    await StorageService.saveTodos(
      username,
      [original],
      sync: false,
      isSyncSource: true,
      recomputeScheduleConflicts: false,
    );

    final completed = original.detachedCopy()..isDone = true;
    completed.markAsChanged();
    await StorageService.saveTodos(
      username,
      [completed],
      sync: false,
      recomputeScheduleConflicts: false,
    );

    final stored = (await StorageService.getTodoByUuid(username, original.id))!;
    expect(stored.isDone, isTrue);
    expect(stored.version, 3);

    final db = await DatabaseHelper.instance.databaseForUser(username);
    final ops = await db.query(
      'op_logs',
      where: 'target_uuid = ?',
      whereArgs: [original.id],
    );
    expect(ops, hasLength(1));
    final payload = jsonDecode(ops.single['data_json'] as String) as Map;
    expect(payload['_independent_completion_only'], isTrue);
    expect(payload['version'], 3);
    expect(payload['is_completed'], 1);
  });

  test('clearResolvedCollabCompletionConflictsForTest clears completion-only conflicts but keeps real content conflicts', () {
    final completionOnly = TodoItem(
      id: 'collab-conflict-1',
      title: '相同标题',
      teamUuid: 'team-uuid-1',
      collabType: 1,
      isDone: true,
      completedAt: 1700000000000,
      version: 5,
      updatedAt: 1700000000000,
      hasConflict: true,
      serverVersionData: {
        'uuid': 'collab-conflict-1',
        'content': '相同标题',
        'team_uuid': 'team-uuid-1',
        'collab_type': 1,
        'is_completed': 0,
        'is_deleted': 0,
        'version': 4,
        'updated_at': 1690000000000,
      },
    );
    final realDiff = TodoItem(
      id: 'collab-conflict-2',
      title: '本地改了标题',
      teamUuid: 'team-uuid-1',
      collabType: 1,
      isDone: true,
      version: 5,
      updatedAt: 1700000000000,
      hasConflict: true,
      serverVersionData: {
        'uuid': 'collab-conflict-2',
        'content': '服务端标题',
        'team_uuid': 'team-uuid-1',
        'collab_type': 1,
        'is_completed': 0,
        'is_deleted': 0,
        'version': 5,
        'updated_at': 1690000000000,
      },
    );

    final resolved =
        StorageService.clearResolvedCollabCompletionConflictsForTest([
          completionOnly,
          realDiff,
        ]);

    expect(resolved.map((e) => e.id).toList(), ['collab-conflict-1']);
    expect(completionOnly.hasConflict, isFalse);
    expect(completionOnly.serverVersionData, isNull);
    expect(realDiff.hasConflict, isTrue);
    expect(realDiff.serverVersionData, isNotNull);
  });
}
