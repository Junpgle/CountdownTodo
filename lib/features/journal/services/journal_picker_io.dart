import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'journal_picker_context.dart';

const _pendingPickContextKey = 'journal.pending_image_pick_context';

Future<List<XFile>> pickJournalImages() async {
  final isDesktop = defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.linux;
  if (!isDesktop) {
    return ImagePicker().pickMultiImage(imageQuality: 88, maxWidth: 2400);
  }

  final result = await FilePicker.platform.pickFiles(
    allowMultiple: true,
    type: FileType.image,
    // Desktop platforms return a file path. Avoid eagerly putting every
    // selected original image into RAM; the importer reads one file at a time.
    withData: false,
  );
  if (result == null) return [];
  return result.files
      .where((file) => file.path != null && file.path!.isNotEmpty)
      .map((file) => XFile(file.path!))
      .toList();
}

Future<XFile?> takeJournalPhoto() async {
  final isDesktop = defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.linux;
  if (isDesktop) return null;
  return ImagePicker().pickImage(
    source: ImageSource.camera,
    imageQuality: 88,
    maxWidth: 2400,
  );
}

Future<void> savePendingJournalPick(JournalImagePickContext context) async {
  await _JournalPickerContextStore.instance.write(context);
}

Future<void> clearPendingJournalPick() async {
  await _JournalPickerContextStore.instance.clear();
}

Future<RecoveredJournalPick?> recoverPendingJournalPick(
  String activeAccountId,
) async {
  final context = await _JournalPickerContextStore.instance.read();
  if (context == null) return null;
  if (context.accountId != activeAccountId) {
    await _JournalPickerContextStore.instance.clear();
    return null;
  }
  final response = await ImagePicker().retrieveLostData();
  if (response.isEmpty) return RecoveredJournalPick(context: context);
  if (response.exception != null) {
    return RecoveredJournalPick(context: context, error: response.exception);
  }
  final files = response.files ??
      (response.file == null ? const <XFile>[] : [response.file!]);
  return RecoveredJournalPick(context: context, files: files);
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

class _JournalPickerContextStore {
  _JournalPickerContextStore._();

  static final instance = _JournalPickerContextStore._();
  static const _key = _pendingPickContextKey;

  Future<void> write(JournalImagePickContext context) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_key, context.encode());
  }

  Future<JournalImagePickContext?> read() async {
    final preferences = await SharedPreferences.getInstance();
    return JournalImagePickContext.decode(preferences.getString(_key));
  }

  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_key);
  }
}
