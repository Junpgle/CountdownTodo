import 'package:countdown_todo/models/auto_backup_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AutoBackupConfig', () {
    test('is disabled by default with daily interval and keep 7 snapshots', () {
      const config = AutoBackupConfig();
      expect(config.enabled, isFalse);
      expect(config.intervalDays, 1);
      expect(config.maxKeepCount, 7);
      expect(config.customDirectory, isNull);
    });

    test('round-trips JSON serialization', () {
      const original = AutoBackupConfig(
        enabled: true,
        intervalDays: 3,
        maxKeepCount: 14,
        customDirectory: '/tmp/backups',
        lastBackupAt: 1700000000000,
        lastBackupFilePath: '/tmp/backups/cdt_auto_backup_20261115_120000.json',
        lastBackupError: 'permission denied',
      );
      final decoded = AutoBackupConfig.fromJsonString(original.toJsonString());
      expect(decoded.enabled, original.enabled);
      expect(decoded.intervalDays, original.intervalDays);
      expect(decoded.maxKeepCount, original.maxKeepCount);
      expect(decoded.customDirectory, original.customDirectory);
      expect(decoded.lastBackupAt, original.lastBackupAt);
      expect(decoded.lastBackupFilePath, original.lastBackupFilePath);
      expect(decoded.lastBackupError, original.lastBackupError);
    });

    test('sanitizes invalid interval and keep count values', () {
      final decoded = AutoBackupConfig.fromJson({
        'intervalDays': -2,
        'maxKeepCount': 0,
        'customDirectory': '   ',
      });
      expect(decoded.intervalDays, AutoBackupConfig.defaultIntervalDays);
      expect(decoded.maxKeepCount, AutoBackupConfig.defaultMaxKeepCount);
      expect(decoded.customDirectory, isNull);
    });
  });

  group('AutoBackupPolicy.isBackupDue', () {
    test('returns false when disabled', () {
      const config = AutoBackupConfig(enabled: false, lastBackupAt: null);
      expect(
        AutoBackupPolicy.isBackupDue(config: config, nowMs: 1700000000000),
        isFalse,
      );
    });

    test('returns true when never backed up', () {
      const config = AutoBackupConfig(enabled: true, lastBackupAt: null);
      expect(
        AutoBackupPolicy.isBackupDue(config: config, nowMs: 1700000000000),
        isTrue,
      );
    });

    test('returns false before interval elapses and true once reached', () {
      final base = DateTime(2026, 11, 15, 12, 0).millisecondsSinceEpoch;
      final config = AutoBackupConfig(
        enabled: true,
        intervalDays: 1,
        lastBackupAt: base,
      );
      final almostOneDay = base + const Duration(hours: 23).inMilliseconds;
      final oneDayLater = base + const Duration(days: 1).inMilliseconds;

      expect(
        AutoBackupPolicy.isBackupDue(config: config, nowMs: almostOneDay),
        isFalse,
      );
      expect(
        AutoBackupPolicy.isBackupDue(config: config, nowMs: oneDayLater),
        isTrue,
      );
    });

    test('returns true if system clock moved backwards', () {
      final base = DateTime(2026, 11, 15, 12, 0).millisecondsSinceEpoch;
      final config = AutoBackupConfig(enabled: true, lastBackupAt: base);
      expect(
        AutoBackupPolicy.isBackupDue(
          config: config,
          nowMs: base - const Duration(hours: 1).inMilliseconds,
        ),
        isTrue,
      );
    });
  });

  group('AutoBackupPolicy file naming and pruning', () {
    test('builds and validates snapshot filenames', () {
      final name = AutoBackupPolicy.buildBackupFileName(
        DateTime(2026, 11, 15, 9, 5, 3),
      );
      expect(name, 'cdt_auto_backup_20261115_090503.json');
      expect(AutoBackupPolicy.isAutoBackupFileName(name), isTrue);
      expect(AutoBackupPolicy.isAutoBackupFileName('$name.tmp'), isFalse);
      expect(AutoBackupPolicy.isAutoBackupFileName('other.json'), isFalse);
    });

    test('selects oldest entries beyond maxKeepCount', () {
      final items = ['n5', 'n4', 'n3', 'n2', 'n1'];
      expect(AutoBackupPolicy.selectFilesToPrune(items, 5), isEmpty);
      expect(AutoBackupPolicy.selectFilesToPrune(items, 7), isEmpty);
      expect(AutoBackupPolicy.selectFilesToPrune(items, 3), ['n2', 'n1']);
    });

    test('sanitizes username for directory path', () {
      expect(AutoBackupPolicy.sanitizeUsernameForPath(''), 'default');
      expect(
        AutoBackupPolicy.sanitizeUsernameForPath('user/name:1*2'),
        'user_name_1_2',
      );
    });
  });
}
