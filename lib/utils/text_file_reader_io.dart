import 'dart:io';

Future<String> readTextFile(String path) => File(path).readAsString();
