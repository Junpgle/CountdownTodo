import 'package:countdown_todo/services/privacy_policy_version.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
