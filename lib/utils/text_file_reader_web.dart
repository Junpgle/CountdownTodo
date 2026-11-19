import 'dart:typed_data';

Future<String> readTextFile(String path) {
  throw UnsupportedError(
    'Web cannot read a local file path. Use picked bytes.',
  );
}

Future<Uint8List> readFileBytes(String path) {
  throw UnsupportedError(
    'Web cannot read a local file path. Use picked bytes.',
  );
}

Future<bool> localFileExists(String path) async => false;
