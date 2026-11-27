import 'package:countdown_todo/utils/json_value_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses numeric values from common storage representations', () {
    expect(JsonValueParser.toNullableInt(12), 12);
    expect(JsonValueParser.toNullableInt(12.9), 12);
    expect(JsonValueParser.toNullableInt(' 34 '), 34);
    expect(JsonValueParser.toNullableInt('invalid'), isNull);
    expect(JsonValueParser.toInt(null, fallback: 7), 7);
  });

  test('parses server epoch and ISO date values', () {
    expect(JsonValueParser.epochMillisOrNow('1704067200000'), 1704067200000);
    expect(
      JsonValueParser.epochMillisOrNow('2024-01-01T00:00:00Z'),
      DateTime.utc(2024, 1, 1).millisecondsSinceEpoch,
    );
    expect(JsonValueParser.localDateTime(0), isNull);
    expect(
      JsonValueParser.localDateTime('2024-01-01T00:00:00Z'),
      DateTime.utc(2024, 1, 1).toLocal(),
    );
  });

  test('ignores malformed JSON maps instead of throwing', () {
    expect(JsonValueParser.toMap('{"ok": 1}'), {'ok': 1});
    expect(JsonValueParser.toMap('{invalid'), isNull);
    expect(JsonValueParser.toMap(['not', 'a', 'map']), isNull);
  });

  test('parses double values safely with optional fallback', () {
    expect(JsonValueParser.toNullableDouble(12), 12.0);
    expect(JsonValueParser.toNullableDouble(3.5), 3.5);
    expect(JsonValueParser.toNullableDouble(' 4.25 '), 4.25);
    expect(JsonValueParser.toNullableDouble('bad'), isNull);
    expect(JsonValueParser.toNullableDouble(null), isNull);
    expect(JsonValueParser.toDouble('bad', fallback: 1.5), 1.5);
  });

  test('parses bool values from bool, num, and string forms', () {
    expect(JsonValueParser.toNullableBool(true), isTrue);
    expect(JsonValueParser.toNullableBool(false), isFalse);
    expect(JsonValueParser.toNullableBool(1), isTrue);
    expect(JsonValueParser.toNullableBool(0), isFalse);
    expect(JsonValueParser.toNullableBool(' true '), isTrue);
    expect(JsonValueParser.toNullableBool('1'), isTrue);
    expect(JsonValueParser.toNullableBool('YES'), isTrue);
    expect(JsonValueParser.toNullableBool(' false '), isFalse);
    expect(JsonValueParser.toNullableBool('0'), isFalse);
    expect(JsonValueParser.toNullableBool('No'), isFalse);
    expect(JsonValueParser.toNullableBool('invalid'), isNull);
    expect(JsonValueParser.toNullableBool(null), isNull);
    expect(JsonValueParser.toBool(null, fallback: true), isTrue);
    expect(JsonValueParser.toBool('invalid'), isFalse);
  });

  test('parses string lists with optional empty filtering and scalar wrap', () {
    expect(JsonValueParser.toStringList(null), isEmpty);
    expect(JsonValueParser.toStringList(['a', '', 12]), ['a', '', '12']);
    expect(
      JsonValueParser.toStringList(['a', '', null, 'b'], skipEmpty: true),
      ['a', 'b'],
    );
    expect(JsonValueParser.toStringList('single'), isEmpty);
    expect(JsonValueParser.toStringList('single', wrapScalar: true), [
      'single',
    ]);
    expect(
      JsonValueParser.toStringList('', skipEmpty: true, wrapScalar: true),
      isEmpty,
    );
  });
}
