import 'dart:io';

void main() {
  final file = File('d:/Codes/Android/math_quiz_app/lib/storage_service.dart');
  final lines = file.readAsLinesSync();
  
  // Remove the last few lines that are likely messy
  while (lines.isNotEmpty && (lines.last.contains('getSyncFailures') || lines.last.trim() == '}' || lines.last.isEmpty)) {
    lines.removeLast();
  }
  
  // Also check if the current last line has the `n mess
  if (lines.isNotEmpty && lines.last.contains('}`n`n')) {
     lines[lines.length-1] = '${lines.last.split('}`n`n')[0]}  }';
  }

  // Add the correct method and class end
  lines.add('');
  lines.add('  static Future<List<Map<String, dynamic>>> getSyncFailures() async {');
  lines.add('    final db = await DatabaseHelper.instance.database;');
  lines.add("    return await db.query('op_logs', where: 'sync_error IS NOT NULL AND is_synced = 0', orderBy: 'timestamp DESC');");
  lines.add('  }');
  lines.add('}');
  
  file.writeAsStringSync(lines.join('\n'));
}
