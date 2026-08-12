import 'dart:convert';

/// Identifies the editor that started a native image-picker request.
///
/// Android can destroy the activity while the system picker is open. Keeping
/// this small context locally lets the journal reopen the right draft when the
/// picker result is recovered after an app restart.
class JournalImagePickContext {
  final String accountId;
  final String entryId;
  final String draftId;
  final bool isEditing;

  const JournalImagePickContext({
    required this.accountId,
    required this.entryId,
    required this.draftId,
    required this.isEditing,
  });

  String encode() => jsonEncode({
        'accountId': accountId,
        'entryId': entryId,
        'draftId': draftId,
        'isEditing': isEditing,
      });

  static JournalImagePickContext? decode(String? value) {
    if (value == null || value.isEmpty) return null;
    try {
      final raw = jsonDecode(value);
      if (raw is! Map<String, dynamic>) return null;
      final accountId = raw['accountId']?.toString() ?? '';
      final entryId = raw['entryId']?.toString() ?? '';
      final draftId = raw['draftId']?.toString() ?? '';
      if (accountId.isEmpty || entryId.isEmpty || draftId.isEmpty) return null;
      return JournalImagePickContext(
        accountId: accountId,
        entryId: entryId,
        draftId: draftId,
        isEditing: raw['isEditing'] == true,
      );
    } catch (_) {
      return null;
    }
  }
}
