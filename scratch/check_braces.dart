import 'dart:io';

void main() {
  final content = File('d:/Codes/Android/math_quiz_app/lib/services/database_helper.dart').readAsStringSync();
  int open = 0;
  int close = 0;
  for (int i = 0; i < content.length; i++) {
    if (content[i] == '{') open++;
    if (content[i] == '}') close++;
  }
  print('Open: $open, Close: $close');
}
