import 'package:open_file/open_file.dart';

class FileOpenService {
  FileOpenService._();

  static Future<void> open(String path) async {
    await OpenFile.open(path);
  }
}
