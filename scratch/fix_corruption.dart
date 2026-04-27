import 'dart:io';

void main() {
  final file = File('d:/Codes/Android/math_quiz_app/lib/storage_service.dart');
  final lines = file.readAsLinesSync();
  final newLines = <String>[];

  for (var line in lines) {
    var newLine = line;
    // Fix broken debugPrint and Exceptions
    if (newLine.contains('debugPrint("') && !newLine.contains('");')) {
      newLine = newLine.trimRight();
      if (!newLine.endsWith(');')) {
         newLine += '");';
      }
    }
    if (newLine.contains('throw Exception("') && !newLine.contains('");')) {
      newLine = newLine.trimRight();
      if (!newLine.endsWith(');')) {
         newLine += '");';
      }
    }
    newLines.add(newLine);
  }
  
  file.writeAsStringSync(newLines.join('\n'));
}
