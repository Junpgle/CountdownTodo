import 'package:flutter_test/flutter_test.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'package:countdown_todo/services/external_share_payload_classifier.dart';

void main() {
  SharedMediaFile media(String mimeType, {String path = '/tmp/share.bin'}) {
    return SharedMediaFile(
      path: path,
      type: SharedMediaType.file,
      mimeType: mimeType,
    );
  }

  test('maps each private share MIME type to its isolated workflow', () {
    expect(
      ExternalSharePayloadClassifier.modeFor(
        media(ExternalSharePayloadClassifier.courseMime),
      ),
      ExternalShareMode.courseImport,
    );
    expect(
      ExternalSharePayloadClassifier.modeFor(
        media(ExternalSharePayloadClassifier.imageMime),
      ),
      ExternalShareMode.imageRecognition,
    );
    expect(
      ExternalSharePayloadClassifier.modeFor(
        media(ExternalSharePayloadClassifier.financeMime),
      ),
      ExternalShareMode.financeImport,
    );
    expect(
      ExternalSharePayloadClassifier.modeFor(
        media(ExternalSharePayloadClassifier.fileMime),
      ),
      ExternalShareMode.fileInbox,
    );
  });

  test('keeps ordinary MIME types on automatic routing', () {
    expect(
      ExternalSharePayloadClassifier.modeFor(media('application/json')),
      ExternalShareMode.automatic,
    );
  });

  test('recognizes inline text sent through the finance target', () async {
    final inlineText = media(
      ExternalSharePayloadClassifier.financeMime,
      path: '午餐 25 元',
    );

    expect(
      await ExternalSharePayloadClassifier.isInlineText(inlineText),
      isTrue,
    );
  });

  test('does not mistake a not-yet-copied course path for inline text',
      () async {
    final courseFile = SharedMediaFile(
      path: '/cache/exported_schedule.mhtml',
      type: SharedMediaType.text,
      mimeType: 'text/plain',
    );

    expect(
      await ExternalSharePayloadClassifier.isInlineText(courseFile),
      isFalse,
    );
  });
}
