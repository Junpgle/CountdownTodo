import 'dart:io';

import 'package:receive_sharing_intent/receive_sharing_intent.dart';

/// Distinguishes inline shared text from a text file shared by URI.
///
/// Android can report a shared `.txt`/`.json` file as `text/plain`, while the
/// plugin still puts the copied file path in [SharedMediaFile.path]. Checking
/// the path first keeps those files on the course-import path.
abstract final class ExternalSharePayloadClassifier {
  static Future<bool> isInlineText(SharedMediaFile media) async {
    final path = media.path.trim();
    if (path.isNotEmpty && await File(path).exists()) return false;

    return media.type == SharedMediaType.text ||
        media.mimeType?.toLowerCase().startsWith('text/') == true;
  }
}
