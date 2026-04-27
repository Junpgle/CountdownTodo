import 'dart:io';

void main() {
  final file = File('d:/Codes/Android/math_quiz_app/lib/storage_service.dart');
  String content = file.readAsStringSync();
  
  // Find the problematic part
  const badPart = '  }\n}\n  static Future<List<Map<String, dynamic>>> getSyncFailures() async {';
  const goodPart = '  }\n\n  static Future<List<Map<String, dynamic>>> getSyncFailures() async {';
  
  if (content.contains(badPart)) {
    content = content.replaceFirst(badPart, goodPart);
    file.writeAsStringSync(content);
    print('Fixed!');
  } else {
    print('Not found!');
  }
}
