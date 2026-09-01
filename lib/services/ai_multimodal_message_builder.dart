import 'dart:convert';
import 'dart:typed_data';

import '../models/chat_message.dart';

/// Builds OpenAI-compatible chat content parts while keeping provider-specific
/// differences in one place. Attachments are sent only for the current request;
/// callers persist paths/metadata, never the encoded payload.
class AiMultimodalMessageBuilder {
  static const int maxImageBytes = 10 * 1024 * 1024;
  static const int maxAudioBytes = 20 * 1024 * 1024;
  static const int maxVideoBytes = 32 * 1024 * 1024;
  static const int maxDocumentBytes = 10 * 1024 * 1024;

  static int maxBytesFor(ChatAttachmentKind kind) => switch (kind) {
        ChatAttachmentKind.image => maxImageBytes,
        ChatAttachmentKind.audio => maxAudioBytes,
        ChatAttachmentKind.video => maxVideoBytes,
        ChatAttachmentKind.document => maxDocumentBytes,
      };

  static List<Map<String, dynamic>> buildContent({
    required String text,
    required ChatImageAttachment attachment,
    required Uint8List bytes,
    required String provider,
  }) {
    final normalizedText =
        text.trim().isEmpty ? _defaultPrompt(attachment.kind) : text.trim();
    final encoded = base64Encode(bytes);
    final dataUrl = 'data:${attachment.mimeType};base64,$encoded';
    final content = <Map<String, dynamic>>[
      {'type': 'text', 'text': normalizedText},
    ];

    switch (attachment.kind) {
      case ChatAttachmentKind.image:
        content.add({
          'type': 'image_url',
          'image_url': {'url': dataUrl},
        });
        break;
      case ChatAttachmentKind.audio:
        final isMimo = provider == 'mimo' || provider == 'mimo_token_plan';
        content.add({
          'type': 'input_audio',
          'input_audio': {
            'data': isMimo ? dataUrl : encoded,
            if (!isMimo) 'format': _audioFormat(attachment.mimeType),
          },
        });
        break;
      case ChatAttachmentKind.video:
        content.add({
          'type': 'video_url',
          'video_url': {'url': dataUrl},
          if (provider == 'mimo' || provider == 'mimo_token_plan') ...{
            'fps': 2,
            'media_resolution': 'default',
          },
        });
        break;
      case ChatAttachmentKind.document:
        if (_isTextDocument(attachment.mimeType, attachment.name)) {
          final decoded = utf8.decode(bytes, allowMalformed: true);
          content.add({
            'type': 'text',
            'text': '[ATTACHMENT_START name=${jsonEncode(attachment.name)} '
                'mime=${jsonEncode(attachment.mimeType)}]\n'
                '$decoded\n[ATTACHMENT_END]',
          });
        } else {
          content.add({
            'type': 'file',
            'file': {
              'filename': attachment.name,
              'file_data': dataUrl,
            },
          });
        }
        break;
    }
    return content;
  }

  static bool isTextDocument(ChatImageAttachment attachment) =>
      _isTextDocument(attachment.mimeType, attachment.name);

  static String _defaultPrompt(ChatAttachmentKind kind) => switch (kind) {
        ChatAttachmentKind.image => '请分析图片内容，并结合我的待办与日程给出结果。',
        ChatAttachmentKind.audio => '请理解这段音频，并提取重要信息、待办与建议。',
        ChatAttachmentKind.video => '请分析这段视频，并提取重要信息、待办与建议。',
        ChatAttachmentKind.document => '请阅读这份文件，并提取重要信息、待办与建议。',
      };

  static String _audioFormat(String mimeType) {
    final normalized = mimeType.toLowerCase();
    return normalized.contains('wav') ? 'wav' : 'mp3';
  }

  static bool _isTextDocument(String mimeType, String name) {
    final normalizedMime = mimeType.toLowerCase();
    if (normalizedMime.startsWith('text/') ||
        normalizedMime == 'application/json' ||
        normalizedMime == 'application/xml' ||
        normalizedMime == 'application/yaml' ||
        normalizedMime == 'application/x-yaml') {
      return true;
    }
    final normalizedName = name.toLowerCase();
    return const ['.txt', '.md', '.csv', '.json', '.xml', '.yaml', '.yml']
        .any(normalizedName.endsWith);
  }
}
