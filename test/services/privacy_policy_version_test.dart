import 'package:countdown_todo/services/privacy_policy_version.dart';
import 'package:countdown_todo/services/storage/app_settings_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('PrivacyPolicyVersion.extract', () {
    test('supports the legacy Chinese version date', () {
      expect(
        PrivacyPolicyVersion.extract('版本日期：2026年6月14日'),
        '2026-06-14',
      );
    });

    test('uses the implementation review date in the current policy format',
        () {
      const content = '''
生效日期：2025-04-23
最近按实现核对：2026-07-20
''';

      expect(PrivacyPolicyVersion.extract(content), '2026-07-20');
    });

    test('does not invent a version when no supported marker exists', () {
      expect(PrivacyPolicyVersion.extract('# Privacy policy'), isNull);
    });
  });

  group('AppSettingsStorage privacy version cache', () {
    test('reuses a recent check without requiring a cached version', () async {
      SharedPreferences.setMockInitialValues({
        'privacy_policy_date': '2026-07-20',
        'privacy_policy_cache_time': DateTime.now().millisecondsSinceEpoch,
      });

      expect(await AppSettingsStorage.isPrivacyPolicyUpToDate(), isTrue);
    });

    test('does not treat a future stored marker as current', () async {
      SharedPreferences.setMockInitialValues({
        'privacy_policy_date': '2026-09-14',
        'privacy_policy_cached_version': '2026-07-20',
        'privacy_policy_cache_time': DateTime.now().millisecondsSinceEpoch,
      });

      expect(await AppSettingsStorage.isPrivacyPolicyUpToDate(), isFalse);
    });
  });
}
