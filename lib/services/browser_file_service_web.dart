import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

class BrowserFileService {
  BrowserFileService._();

  static Future<String> saveTextFile(
    String content,
    String fileName, {
    String mimeType = 'text/plain;charset=utf-8',
  }) async {
    final bytes = Uint8List.fromList(utf8.encode(content));
    _downloadBytes(bytes, fileName, mimeType);
    return fileName;
  }

  static Future<void> shareTextFile(
    String content,
    String fileName, {
    String subject = '',
    String mimeType = 'text/plain;charset=utf-8',
  }) async {
    await saveTextFile(content, fileName, mimeType: mimeType);
  }

  static Future<String> saveBytesFile(
    Uint8List bytes,
    String fileName, {
    String mimeType = 'application/octet-stream',
  }) async {
    _downloadBytes(bytes, fileName, mimeType);
    return fileName;
  }

  static Future<void> shareBytesFile(
    Uint8List bytes,
    String fileName, {
    String text = '',
    String mimeType = 'application/octet-stream',
  }) async {
    await saveBytesFile(bytes, fileName, mimeType: mimeType);
  }

  static void _downloadBytes(
    Uint8List bytes,
    String fileName,
    String mimeType,
  ) {
    final blob = web.Blob(
      <JSAny>[bytes.toJS].toJS,
      web.BlobPropertyBag(type: mimeType),
    );
    final url = web.URL.createObjectURL(blob);
    final anchor = web.HTMLAnchorElement()
      ..href = url
      ..download = fileName
      ..style.display = 'none';
    web.document.body?.appendChild(anchor);
    anchor.click();
    anchor.remove();
    web.URL.revokeObjectURL(url);
  }
}
