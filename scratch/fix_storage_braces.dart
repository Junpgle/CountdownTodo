import 'dart:io';
import 'dart:convert';

void main() {
  final file = File('d:/Codes/Android/math_quiz_app/lib/storage_service.dart');
  final bytes = file.readAsBytesSync();
  // We use latin1 to decode so we can safely process each byte without UTF-8 errors
  String content = latin1.decode(bytes);
  
  // Fix the broken suffixes. PowerShell likely replaced \n with \r\n or messed up the end of lines.
  // The common pattern of corruption is a string literal followed by ); or ), or }; that is missing its start or end.
  
  // Replace the specific mangled strings if we can identify them, or use a regex to fix unterminated strings.
  
  // Actually, the most reliable way is to find the strings that end without "); and fix them.
  // But wait, the user's errors show specific lines.
  
  // I'll try to find the "n isn't a type" error at the end of the file.
  // That likely came from my Add-Content with `n.
  
  content = content.replaceFirst('}\n}', '}'); // Remove the extra brace I added
  
  file.writeAsBytesSync(latin1.encode(content));
}
