import 'dart:io';

import 'package:receive_sharing_intent/receive_sharing_intent.dart';

/// Explicit destinations exposed in the Android share sheet.
///
/// The automatic destination keeps the historical behaviour for callers that
/// do not choose a purpose. The other destinations are encoded as private MIME
/// types by the native share-target activities, so the Dart side can keep each
/// workflow isolated even though they all eventually enter MainActivity.
enum ExternalShareMode {
  automatic,
  courseImport,
  imageRecognition,
  financeImport,
  fileInbox,
}

/// Distinguishes inline shared text from a text file shared by URI.
///
/// Android can report a shared `.txt`/`.json` file as `text/plain`, while the
/// plugin still puts the copied file path in [SharedMediaFile.path]. Checking
/// the path first keeps those files on the course-import path.
abstract final class ExternalSharePayloadClassifier {
  static const courseMime = 'application/vnd.countdowntodo.course';
  static const imageMime = 'application/vnd.countdowntodo.image';
  static const financeMime = 'application/vnd.countdowntodo.finance';
  static const fileMime = 'application/vnd.countdowntodo.file';

  static ExternalShareMode modeFor(SharedMediaFile media) {
    switch (media.mimeType?.trim().toLowerCase()) {
      case courseMime:
        return ExternalShareMode.courseImport;
      case imageMime:
        return ExternalShareMode.imageRecognition;
      case financeMime:
        return ExternalShareMode.financeImport;
      case fileMime:
        return ExternalShareMode.fileInbox;
      default:
        return ExternalShareMode.automatic;
    }
  }

  static Future<bool> isInlineText(SharedMediaFile media) async {
    final mode = modeFor(media);
    if (mode == ExternalShareMode.courseImport ||
        mode == ExternalShareMode.imageRecognition ||
        mode == ExternalShareMode.fileInbox) {
      return false;
    }

    final path = media.path.trim();
    if (path.isNotEmpty &&
        (await File(path).exists() || _looksLikeFilePath(path))) {
      return false;
    }

    // The finance share target deliberately forwards inline text with a
    // private MIME type, so the normal text MIME check cannot identify it.
    if (mode == ExternalShareMode.financeImport) return true;

    return media.type == SharedMediaType.text ||
        media.mimeType?.toLowerCase().startsWith('text/') == true;
  }

  static bool _looksLikeFilePath(String value) {
    final lower = value.toLowerCase();
    if (lower.startsWith('/') ||
        lower.startsWith('file://') ||
        lower.startsWith('content://')) {
      return true;
    }

    final lastSegment = lower.split(RegExp(r'[\\/]')).last;
    return const {
      'json',
      'txt',
      'html',
      'htm',
      'mhtml',
      'ics',
      'csv',
    }.any((extension) => lastSegment.endsWith('.$extension'));
  }
}
