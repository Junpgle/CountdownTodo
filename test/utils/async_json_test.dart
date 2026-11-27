import 'package:countdown_todo/utils/async_json.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'decodeJsonOffload and encodeJsonOffload round-trip small payloads',
    () async {
      final payload = <String, dynamic>{
        'id': '1',
        'items': [1, 2, 3],
      };
      final encoded = await encodeJsonOffload(payload, estimatedItemCount: 3);
      final decoded = await decodeJsonOffload(encoded) as Map<String, dynamic>;
      expect(decoded['id'], '1');
      expect(decoded['items'], [1, 2, 3]);
    },
  );

  test(
    'decodeJsonOffload and encodeJsonOffload round-trip large isolate payloads',
    () async {
      final items = List.generate(
        400,
        (index) => <String, dynamic>{
          'id': 'item-$index',
          'title': 'Sample payload row number $index with padding text',
        },
      );
      final encoded = await encodeJsonOffload(
        items,
        estimatedItemCount: items.length,
      );
      expect(
        encoded.length,
        greaterThanOrEqualTo(kAsyncJsonOffloadThresholdBytes),
      );

      final decoded = await decodeJsonOffload(encoded) as List<dynamic>;
      expect(decoded, hasLength(400));
      expect((decoded.last as Map<String, dynamic>)['id'], 'item-399');
    },
  );

  test(
    'decodeJsonOffload propagates FormatException on malformed large JSON',
    () async {
      final malformed =
          '{"broken":"${'x' * (kAsyncJsonOffloadThresholdBytes + 32)}"';
      await expectLater(
        decodeJsonOffload(malformed),
        throwsA(isA<FormatException>()),
      );
    },
  );
}
