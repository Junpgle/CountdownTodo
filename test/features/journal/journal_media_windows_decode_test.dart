import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:countdown_todo/features/journal/models/journal_entry.dart';
import 'package:countdown_todo/features/journal/services/journal_media_service.dart';
import 'package:countdown_todo/utils/app_platform.dart';

void main() {
  test('limits journal image decode size on Windows only', () {
    final provider = JournalMediaService.instance.provider(
      JournalAttachment(entryId: 'entry', imageData: Uint8List.fromList([1])),
    );

    expect(provider, isNotNull);
    if (AppPlatform.isWindows) {
      final resized = provider! as ResizeImage;
      expect(resized.width, 2048);
      expect(resized.height, 2048);
      expect(resized.policy, ResizeImagePolicy.fit);
    } else {
      expect(provider, isA<MemoryImage>());
    }
  });
}
