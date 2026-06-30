import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class BrowserFileService {
  BrowserFileService._();

  static Future<String> saveTextFile(
    String content,
    String fileName, {
    String mimeType = 'text/plain;charset=utf-8',
  }) async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/$fileName');
    await file.writeAsString(content, encoding: utf8);
    return file.path;
  }

  static Future<void> shareTextFile(
    String content,
    String fileName, {
    String subject = '',
    String mimeType = 'text/plain;charset=utf-8',
  }) async {
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/$fileName');
    await file.writeAsString(content, encoding: utf8);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: mimeType)],
        subject: subject,
      ),
    );
  }

  static Future<String> saveBytesFile(
    Uint8List bytes,
    String fileName, {
    String mimeType = 'application/octet-stream',
  }) async {
    final directory = await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  static Future<void> shareBytesFile(
    Uint8List bytes,
    String fileName, {
    String text = '',
    String mimeType = 'application/octet-stream',
  }) async {
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: mimeType)],
        text: text,
      ),
    );
  }
}
