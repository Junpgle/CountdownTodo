import 'dart:io';
import 'dart:typed_data';

Future<String> readTextFile(String path) => File(path).readAsString();

Future<Uint8List> readFileBytes(String path) => File(path).readAsBytes();

Future<bool> localFileExists(String path) => File(path).exists();
