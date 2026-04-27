import 'dart:io';

void main() {
  final file = File('d:/Codes/Android/math_quiz_app/lib/screens/about_screen.dart');
  final lines = file.readAsLinesSync();
  
  final newLines = <String>[];
  bool added = false;
  
  for (var line in lines) {
    newLines.add(line);
    if (!added && line.contains("import '../storage_service.dart';")) {
      newLines.add("import 'dart:async';");
      newLines.add("import '../services/local_migration_service.dart';");
      added = true;
    }
    
    // Fix EdgeInsets.top
    if (line.contains("EdgeInsets.top(8.0)")) {
      newLines[newLines.length - 1] = line.replaceFirst("EdgeInsets.top(8.0)", "EdgeInsets.only(top: 8.0)");
    }
  }
  
  file.writeAsStringSync(newLines.join('\n'));
}
