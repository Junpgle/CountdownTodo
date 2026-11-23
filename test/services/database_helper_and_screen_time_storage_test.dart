import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:countdown_todo/services/database_helper.dart';
import 'package:countdown_todo/storage_service.dart';
import 'package:countdown_todo/utils/app_platform.dart';
import 'package:countdown_todo/utils/time_utils.dart' as time_utils;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  tearDown(() async {
    await DatabaseHelper.instance.closeDatabase();
  });

  group('DatabaseHelper.matchesDatabaseFileForUser', () {
    test('matches exact filename across Unix, Windows, and Web paths', () {
      expect(
        DatabaseHelper.matchesDatabaseFileForUser(
          '/tmp/databases/v4_uni_sync_alice.db',
          'alice',
        ),
        isTrue,
      );
      expect(
        DatabaseHelper.matchesDatabaseFileForUser(
          r'C:\Users\alice\AppData\Roaming\databases\v4_uni_sync_alice.db',
          'alice',
        ),
        isTrue,
      );
      expect(
        DatabaseHelper.matchesDatabaseFileForUser(
          'v4_uni_sync_alice.db',
          'alice',
        ),
        isTrue,
      );
    });

    test('does not confuse prefix usernames such as alice and alice_work', () {
      expect(
        DatabaseHelper.matchesDatabaseFileForUser(
          '/tmp/databases/v4_uni_sync_alice_work.db',
          'alice',
        ),
        isFalse,
      );
      expect(
        DatabaseHelper.matchesDatabaseFileForUser(
          '/tmp/databases/v4_uni_sync_alice.db',
          'alice_work',
        ),
        isFalse,
      );
    });

    test('switches cleanly between prefix-overlapping usernames', () async {
      final base = 'prefix_${DateTime.now().microsecondsSinceEpoch}';
      final longer = '${base}_work';

      SharedPreferences.setMockInitialValues({'current_login_user': longer});
      final prefs = await SharedPreferences.getInstance();
      final dbLonger = await DatabaseHelper.instance.databaseForUser(longer);
      expect(
        DatabaseHelper.matchesDatabaseFileForUser(dbLonger.path, longer),
        isTrue,
      );
      expect(
        DatabaseHelper.matchesDatabaseFileForUser(dbLonger.path, base),
        isFalse,
      );

      await prefs.setString('current_login_user', base);
      final dbBase = await DatabaseHelper.instance.databaseForUser(base);
      expect(
        DatabaseHelper.matchesDatabaseFileForUser(dbBase.path, base),
        isTrue,
      );
      expect(dbBase.path, isNot(dbLonger.path));
    });
  });

  group('ScreenTime SQLite single source of truth', () {
    test(
      'saveScreenTimeCache writes to SQLite without writing Prefs history',
      () async {
        final username = 'st_sql_${DateTime.now().microsecondsSinceEpoch}';
        SharedPreferences.setMockInitialValues({
          'current_login_user': username,
          'migrated_screentime_$username': true,
        });
        final prefs = await SharedPreferences.getInstance();

        final today = time_utils.AppTimeFormats.date(DateTime.now());
        final stats = [
          {
            'package_name': 'com.example.app',
            'app_name': '测试应用',
            'device_name': 'Mac',
            'category': '学习办公',
            'duration': 600,
          },
        ];

        await StorageService.saveScreenTimeCache(stats, username: username);

        expect(prefs.getString('screen_time_history_$username'), isNull);
        final history = await StorageService.getScreenTimeHistory(
          username: username,
        );
        expect(history[today], isNotNull);
        expect(history[today]!.single['app_name'], '测试应用');
        expect(history[today]!.single['duration'], 600);
      },
    );

    test(
      'saveScreenTimeCache migrates legacy Prefs history once and clears it',
      () async {
        final username = 'st_mig_${DateTime.now().microsecondsSinceEpoch}';
        final legacyHistory = {
          '2026-10-01': [
            {
              'package_name': 'com.legacy.app',
              'app_name': '旧版应用',
              'device_name': 'Android',
              'category': '未分类',
              'duration': 300,
            },
          ],
        };
        SharedPreferences.setMockInitialValues({
          'current_login_user': username,
          'screen_time_history_$username': jsonEncode(legacyHistory),
        });
        final prefs = await SharedPreferences.getInstance();

        final today = time_utils.AppTimeFormats.date(DateTime.now());
        await StorageService.saveScreenTimeCache([
          {
            'package_name': 'com.today.app',
            'app_name': '今日应用',
            'device_name': 'Mac',
            'category': '效率工具',
            'duration': 900,
          },
        ], username: username);

        expect(prefs.getBool('migrated_screentime_$username'), isTrue);
        expect(prefs.getString('screen_time_history_$username'), isNull);

        final history = await StorageService.getScreenTimeHistory(
          username: username,
        );
        expect(history['2026-10-01'], isNotNull);
        expect(history['2026-10-01']!.single['app_name'], '旧版应用');
        expect(history[today], isNotNull);
        expect(history[today]!.single['app_name'], '今日应用');
      },
    );

    test('handles empty current_login_user in anonymous mode and cleans corrupted legacy JSON', () async {
      SharedPreferences.setMockInitialValues({
        'current_login_user': '',
        'screen_time_history': '{not-valid-json',
      });
      final prefs = await SharedPreferences.getInstance();
      final today = time_utils.AppTimeFormats.date(DateTime.now());

      await StorageService.saveScreenTimeCache([
        {
          'package_name': 'com.anon.app',
          'app_name': '匿名应用',
          'device_name': 'Mac',
          'category': '工具',
          'duration': 180,
        },
      ]);

      expect(prefs.getBool('migrated_screentime_anonymous'), isTrue);
      expect(prefs.getString('screen_time_history'), isNull);

      final history = await StorageService.getScreenTimeHistory();
      expect(history[today], isNotNull);
      expect(history[today]!.single['app_name'], '匿名应用');
    });
  });

  test(
    'AppPlatform.isFlutterTest detects test environment without dart:io in UI',
    () {
      expect(AppPlatform.isFlutterTest, isTrue);
    },
  );
}
