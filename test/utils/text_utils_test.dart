import 'package:countdown_todo/utils/text_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('trimToNull returns null for null and blank strings and trims text', () {
    expect(AppTextUtils.trimToNull(null), isNull);
    expect(AppTextUtils.trimToNull(''), isNull);
    expect(AppTextUtils.trimToNull('   \t\n '), isNull);
    expect(AppTextUtils.trimToNull('  hello  '), 'hello');
  });

  test('truncate preserves short text and caps long strings with ellipsis', () {
    expect(AppTextUtils.truncate('abc', 5), 'abc');
    expect(AppTextUtils.truncate('abcde', 5), 'abcde');
    expect(AppTextUtils.truncate('abcdef', 5), 'abcde…');
    expect(AppTextUtils.truncate('abcdef', 3, ellipsis: '...'), 'abc...');
    expect(AppTextUtils.truncate('abcdef', 0), '');
    expect(AppTextUtils.truncate('abcdef', -2), '');
  });
}
