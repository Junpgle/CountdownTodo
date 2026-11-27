import 'dart:io';

import 'package:countdown_todo/utils/local_image_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'localImageExists caches existence and respects explicit invalidation',
    () async {
      final tempDir = await Directory.systemTemp.createTemp('local_img_cache_');
      addTearDown(() async {
        invalidateLocalImageExistenceCache();
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      expect(localImageExists(null), isFalse);
      expect(localImageExists(''), isFalse);

      final file = File('${tempDir.path}/sample.png');
      await file.writeAsBytes(const <int>[1, 2, 3]);

      expect(localImageExists(file.path), isTrue);

      await file.delete();
      // Within TTL, returns cached positive result until invalidated.
      expect(localImageExists(file.path), isTrue);

      invalidateLocalImageExistenceCache(file.path);
      expect(localImageExists(file.path), isFalse);
    },
  );
}
