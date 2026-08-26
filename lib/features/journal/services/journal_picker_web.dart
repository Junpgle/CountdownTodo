import 'package:image_picker/image_picker.dart';

import 'journal_picker_context.dart';

Future<List<XFile>> pickJournalImages() async {
  return ImagePicker().pickMultiImage(imageQuality: 88, maxWidth: 2400);
}

Future<XFile?> takeJournalPhoto() async {
  return ImagePicker().pickImage(
    source: ImageSource.camera,
    imageQuality: 88,
    maxWidth: 2400,
  );
}

Future<void> savePendingJournalPick(JournalImagePickContext context) async {}

Future<void> clearPendingJournalPick() async {}

Future<RecoveredJournalPick?> recoverPendingJournalPick(
  String activeAccountId,
) async {
  return null;
}

class RecoveredJournalPick {
  final JournalImagePickContext context;
  final List<XFile> files;
  final Exception? error;

  const RecoveredJournalPick({
    required this.context,
    this.files = const [],
    this.error,
  });
}
