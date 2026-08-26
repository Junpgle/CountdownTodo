import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/journal_entry.dart';

class JournalMediaService {
  JournalMediaService._();

  static final instance = JournalMediaService._();

  Future<JournalAttachment> importImage({
    required String accountId,
    required String draftId,
    required String entryId,
    required XFile file,
    required int sortOrder,
  }) async {
    final bytes = await file.readAsBytes();
    return JournalAttachment(
      entryId: entryId,
      imageData: Uint8List.fromList(bytes),
      mimeType: _mimeType(file.path),
      sortOrder: sortOrder,
      fileSize: bytes.length,
    );
  }

  Future<JournalMediaCommit> commitDraft({
    required String accountId,
    required String draftId,
    required String entryId,
    required List<JournalAttachment> attachments,
  }) async {
    return JournalMediaCommit(
      attachments: attachments,
      createdAttachments: const [],
    );
  }

  Future<void> discardDraft({
    required String accountId,
    required String draftId,
  }) async {}

  Future<List<JournalAttachment>> restoreDraftAttachments({
    required String accountId,
    required String draftId,
    required String entryId,
  }) async {
    return [];
  }

  Future<bool> hasDraft({
    required String accountId,
    required String draftId,
  }) async {
    return false;
  }

  Future<void> cleanupOrphanedMedia({
    required String accountId,
    required Set<String> referencedPaths,
  }) async {}

  ImageProvider<Object>? provider(JournalAttachment attachment) {
    final bytes = attachment.imageData;
    return bytes == null || bytes.isEmpty ? null : MemoryImage(bytes);
  }

  Future<void> delete(JournalAttachment attachment) async {}

  String _mimeType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }
}

class JournalMediaCommit {
  final List<JournalAttachment> attachments;
  final List<JournalAttachment> createdAttachments;

  const JournalMediaCommit({
    required this.attachments,
    required this.createdAttachments,
  });
}
