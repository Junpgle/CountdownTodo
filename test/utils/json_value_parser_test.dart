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
}
