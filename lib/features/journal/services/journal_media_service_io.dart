import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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
    await _ensureDesktopSourceIsReasonable(file);
    final originalBytes = await file.readAsBytes();
    if (originalBytes.isEmpty) throw const FileSystemException('图片为空');

    final compressedBytes = await _compressImage(originalBytes);
    final bytes = compressedBytes ?? originalBytes;
    final extension =
        compressedBytes == null ? _safeExtension(file.path) : '.jpg';
    final documents = await getApplicationDocumentsDirectory();
    final folder = Directory(
      p.join(_accountRoot(documents, accountId), '.drafts', draftId),
    );
    await folder.create(recursive: true);
    final attachment = JournalAttachment(
      entryId: entryId,
      mimeType: _mimeType(extension),
      sortOrder: sortOrder,
      fileSize: bytes.length,
    );
    final destination = p.join(
      folder.path,
      '${attachment.id}_$sortOrder$extension',
    );
    await File(destination).writeAsBytes(bytes, flush: true);
    return attachment.copyWith(
      localPath: destination,
    );
  }

  /// Copies the images added during this editing session into their durable
  /// entry folder. The originals stay in the draft folder until the database
  /// transaction succeeds, so a failed save never loses the user's work.
  Future<JournalMediaCommit> commitDraft({
    required String accountId,
    required String draftId,
    required String entryId,
    required List<JournalAttachment> attachments,
  }) async {
    final documents = await getApplicationDocumentsDirectory();
    final draftFolder = p.normalize(
      p.join(_accountRoot(documents, accountId), '.drafts', draftId),
    );
    final entryFolder = Directory(p.join(
      _accountRoot(documents, accountId),
      entryId,
    ));
    final committed = <JournalAttachment>[];
    final created = <JournalAttachment>[];
    final copiedFiles = <File>[];

    try {
      for (final attachment in attachments) {
        final sourcePath = attachment.localPath;
        if (sourcePath == null || !_isWithin(sourcePath, draftFolder)) {
          committed.add(attachment);
          continue;
        }

        await entryFolder.create(recursive: true);
        final destination = p.join(entryFolder.path, p.basename(sourcePath));
        final destinationFile = File(destination);
        copiedFiles.add(destinationFile);
        await File(sourcePath).copy(destination);
        final persisted = attachment.copyWith(
          entryId: entryId,
          localPath: destination,
        );
        committed.add(persisted);
        created.add(persisted);
      }
    } catch (_) {
      for (final file in copiedFiles) {
        try {
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
      try {
        if (await entryFolder.exists() && entryFolder.listSync().isEmpty) {
          await entryFolder.delete();
        }
      } catch (_) {}
      rethrow;
    }

    return JournalMediaCommit(
      attachments: committed,
      createdAttachments: created,
    );
  }

  Future<void> discardDraft({
    required String accountId,
    required String draftId,
  }) async {
    final documents = await getApplicationDocumentsDirectory();
    final draft = Directory(
      p.join(_accountRoot(documents, accountId), '.drafts', draftId),
    );
    if (await draft.exists()) await draft.delete(recursive: true);
  }

  /// Rebuilds attachments that were already copied into a draft before an
  /// Android activity restart. These files have not reached the database yet,
  /// but they are valid user-selected images and must not be discarded while
  /// recovering a pending picker result.
  Future<List<JournalAttachment>> restoreDraftAttachments({
    required String accountId,
    required String draftId,
    required String entryId,
  }) async {
    final documents = await getApplicationDocumentsDirectory();
    final folder = Directory(
      p.join(_accountRoot(documents, accountId), '.drafts', draftId),
    );
    if (!await folder.exists()) return [];

    final attachments = <JournalAttachment>[];
    await for (final entity in folder.list(followLinks: false)) {
      if (entity is! File) continue;
      final parsed = _parseDraftFileName(p.basename(entity.path));
      attachments.add(JournalAttachment(
        id: parsed?.id,
        entryId: entryId,
        localPath: entity.path,
        mimeType: _mimeType(p.extension(entity.path).toLowerCase()),
        sortOrder: parsed?.sortOrder ?? attachments.length,
        fileSize: await entity.length(),
      ));
    }
    attachments.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return attachments;
  }

  Future<bool> hasDraft({
    required String accountId,
    required String draftId,
  }) async {
    final documents = await getApplicationDocumentsDirectory();
    final folder = Directory(
      p.join(_accountRoot(documents, accountId), '.drafts', draftId),
    );
    return await folder.exists() && folder.listSync().isNotEmpty;
  }

  /// Removes abandoned draft files and durable image files no longer
  /// referenced by the local database. This only ever touches the private
  /// `Documents/journal/<account>` folder owned by the current account. Legacy
  /// unscoped media is deliberately left untouched so this safety cleanup can
  /// never delete another account's images during an upgrade.
  Future<void> cleanupOrphanedMedia({
    required String accountId,
    required Set<String> referencedPaths,
  }) async {
    final documents = await getApplicationDocumentsDirectory();
    final root = Directory(_accountRoot(documents, accountId));
    if (!await root.exists()) return;

    final normalizedRoot = p.normalize(root.path);
    final referenced = referencedPaths
        .where((path) => _isWithin(path, normalizedRoot))
        .map(p.normalize)
        .toSet();
    final drafts = Directory(p.join(root.path, '.drafts'));
    if (await drafts.exists()) await drafts.delete(recursive: true);

    final directories = <Directory>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is File && !referenced.contains(p.normalize(entity.path))) {
        await entity.delete();
      } else if (entity is Directory) {
        directories.add(entity);
      }
    }
    directories.sort((a, b) => b.path.length.compareTo(a.path.length));
    for (final directory in directories) {
      if (p.normalize(directory.path) == normalizedRoot ||
          !await directory.exists()) {
        continue;
      }
      if (directory.listSync().isEmpty) await directory.delete();
    }
  }

  ImageProvider<Object>? provider(JournalAttachment attachment) {
    final path = attachment.localPath;
    if (path != null && path.isNotEmpty && File(path).existsSync()) {
      return FileImage(File(path));
    }
    final bytes = attachment.imageData;
    return bytes == null || bytes.isEmpty ? null : MemoryImage(bytes);
  }

  Future<void> delete(JournalAttachment attachment) async {
    final path = attachment.localPath;
    if (path == null || path.isEmpty) return;
    final file = File(path);
    if (await file.exists()) await file.delete();
    try {
      final parent = file.parent;
      if (await parent.exists() && parent.listSync().isEmpty) {
        await parent.delete();
      }
    } catch (_) {}
  }

  Future<void> _ensureDesktopSourceIsReasonable(XFile file) async {
    if ((!Platform.isWindows && !Platform.isLinux) || file.path.isEmpty) {
      return;
    }
    final source = File(file.path);
    if (!await source.exists()) return;
    const maxBytes = 12 * 1024 * 1024;
    if (await source.length() > maxBytes) {
      throw const FileSystemException('桌面端暂不支持导入超过 12 MB 的图片');
    }
  }

  Future<Uint8List?> _compressImage(Uint8List source) async {
    try {
      final compressed = await FlutterImageCompress.compressWithList(
        source,
        minWidth: 1920,
        minHeight: 1920,
        quality: 85,
        format: CompressFormat.jpeg,
      );
      return compressed.isEmpty ? null : Uint8List.fromList(compressed);
    } catch (_) {
      // Some desktop platforms do not provide a compressor implementation.
      // Keeping the original is preferable to losing a selected image.
      return null;
    }
  }

  bool _isWithin(String path, String parent) {
    final normalizedPath = p.normalize(path);
    final normalizedParent = p.normalize(parent);
    return normalizedPath == normalizedParent ||
        p.isWithin(normalizedParent, normalizedPath);
  }

  String _accountRoot(Directory documents, String accountId) {
    final normalizedAccount = accountId.trim().isEmpty ? 'default' : accountId;
    final encoded =
        base64Url.encode(utf8.encode(normalizedAccount)).replaceAll('=', '');
    return p.join(documents.path, 'journal', 'account_$encoded');
  }

  String _safeExtension(String path) {
    final extension = p.extension(path).toLowerCase();
    return extension.isEmpty ? '.jpg' : extension;
  }

  _DraftFileName? _parseDraftFileName(String name) {
    final match = RegExp(r'^([0-9a-fA-F-]{36})_(\d+)\.').firstMatch(name);
    if (match == null) return null;
    return _DraftFileName(
      id: match.group(1)!,
      sortOrder: int.tryParse(match.group(2)!) ?? 0,
    );
  }

  String _mimeType(String extension) {
    switch (extension) {
      case '.png':
        return 'image/png';
      case '.webp':
        return 'image/webp';
      case '.heic':
      case '.heif':
        return 'image/heic';
      default:
        return 'image/jpeg';
    }
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

class _DraftFileName {
  final String id;
  final int sortOrder;

  const _DraftFileName({required this.id, required this.sortOrder});
}
