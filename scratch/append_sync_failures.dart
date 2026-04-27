import 'dart:io';

void main() {
  final file = File('d:/Codes/Android/math_quiz_app/lib/storage_service.dart');
  final content = file.readAsStringSync().trimRight();
  
  // Find the last closing brace
  if (content.endsWith('}')) {
    final newContent = content.substring(0, content.length - 1) + 
      '\n  static Future<List<Map<String, dynamic>>> getSyncFailures() async {\n' +
      '    final db = await DatabaseHelper.instance.database;\n' +
      "    return await db.query('op_logs', where: 'sync_error IS NOT NULL AND is_synced = 0', orderBy: 'timestamp DESC');\n" +
      '  }\n}\n';
    file.writeAsStringSync(newContent);
    print('Added getSyncFailures successfully.');
  } else {
    print('Could not find class ending.');
  }
}
