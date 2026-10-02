import 'dart:typed_data';

import 'package:countdown_todo/models/chat_message.dart';
import 'package:countdown_todo/services/ai_multimodal_message_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('pending attachment request text', () {
    test('uses the same fallback prompt for estimation and sending', () {
      final cases = [
        (ChatAttachmentKind.image, 'image/png', 'image.png'),
        (ChatAttachmentKind.audio, 'audio/wav', 'audio.wav'),
        (ChatAttachmentKind.video, 'video/mp4', 'video.mp4'),
        (ChatAttachmentKind.document, 'text/plain', 'notes.txt'),
      ];

      for (final (kind, mimeType, name) in cases) {
        final estimateText = AiMultimodalMessageBuilder.requestTextForAttachment(
          text: '',
          attachmentKind: kind,
        );
        final content = AiMultimodalMessageBuilder.buildContent(
          text: '',
          attachment: ChatImageAttachment(
            path: '/tmp/$name',
            name: name,
            mimeType: mimeType,
            kind: kind,
          ),
          bytes: Uint8List.fromList([1]),
          provider: 'custom',
        );

        expect(estimateText, isNotEmpty, reason: kind.name);
        expect(content.first['text'], estimateText, reason: kind.name);
      }
    });

    test('trims typed text and leaves no-attachment input empty', () {
      expect(
        AiMultimodalMessageBuilder.requestTextForAttachment(
          text: '  查看这些内容  ',
          attachmentKind: ChatAttachmentKind.image,
        ),
        '查看这些内容',
      );
      expect(
        AiMultimodalMessageBuilder.requestTextForAttachment(
          text: '',
          attachmentKind: null,
        ),
        isEmpty,
      );
    });
  });
}
