import 'dart:typed_data';

import 'package:uuid/uuid.dart';

class JournalEntry {
  final String id;
  final String? title;
  final String content;
  final DateTime occurredAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<JournalAttachment> attachments;

  JournalEntry({
    String? id,
    this.title,
    this.content = '',
    DateTime? occurredAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.attachments = const [],
  })  : id = id ?? const Uuid().v4(),
        occurredAt = occurredAt ?? DateTime.now(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  bool get isEmpty => content.trim().isEmpty && attachments.isEmpty;

  JournalEntry copyWith({
    String? title,
    String? content,
    DateTime? occurredAt,
    DateTime? updatedAt,
    List<JournalAttachment>? attachments,
    bool clearTitle = false,
  }) {
    return JournalEntry(
      id: id,
      title: clearTitle ? null : (title ?? this.title),
      content: content ?? this.content,
      occurredAt: occurredAt ?? this.occurredAt,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      attachments: attachments ?? this.attachments,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uuid': id,
      'title': title,
      'content': content,
      'occurred_at': occurredAt.millisecondsSinceEpoch,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
      'is_deleted': 0,
    };
  }

  factory JournalEntry.fromMap(
    Map<String, dynamic> map, {
    List<JournalAttachment> attachments = const [],
  }) {
    DateTime parseDate(dynamic value, DateTime fallback) {
      final millis = value is num ? value.toInt() : int.tryParse('$value');
      return millis == null
          ? fallback
          : DateTime.fromMillisecondsSinceEpoch(millis);
    }

    final now = DateTime.now();
    final title = map['title']?.toString();
    return JournalEntry(
      id: map['uuid']?.toString() ?? map['id']?.toString(),
      title: title == null || title.trim().isEmpty ? null : title,
      content: map['content']?.toString() ?? '',
      occurredAt: parseDate(map['occurred_at'], now),
      createdAt: parseDate(map['created_at'], now),
      updatedAt: parseDate(map['updated_at'], now),
      attachments: attachments,
    );
  }
}

class JournalAttachment {
  final String id;
  final String entryId;
  final String? localPath;
  final Uint8List? imageData;
  final String mimeType;
  final int? width;
  final int? height;
  final int sortOrder;
  final int fileSize;
  final DateTime createdAt;

  JournalAttachment({
    String? id,
    required this.entryId,
    this.localPath,
    this.imageData,
    this.mimeType = 'image/jpeg',
    this.width,
    this.height,
    this.sortOrder = 0,
    this.fileSize = 0,
    DateTime? createdAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  JournalAttachment copyWith({
    String? entryId,
    String? localPath,
    Uint8List? imageData,
    String? mimeType,
    int? width,
    int? height,
    int? sortOrder,
    int? fileSize,
  }) {
    return JournalAttachment(
      id: id,
      entryId: entryId ?? this.entryId,
      localPath: localPath ?? this.localPath,
      imageData: imageData ?? this.imageData,
      mimeType: mimeType ?? this.mimeType,
      width: width ?? this.width,
      height: height ?? this.height,
      sortOrder: sortOrder ?? this.sortOrder,
      fileSize: fileSize ?? this.fileSize,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uuid': id,
      'entry_uuid': entryId,
      'local_path': localPath,
      'image_data': imageData,
      'mime_type': mimeType,
      'width': width,
      'height': height,
      'sort_order': sortOrder,
      'file_size': fileSize,
      'created_at': createdAt.millisecondsSinceEpoch,
    };
  }

  factory JournalAttachment.fromMap(Map<String, dynamic> map) {
    final rawData = map['image_data'];
    final imageData = rawData is Uint8List
        ? rawData
        : rawData is List<int>
            ? Uint8List.fromList(rawData)
            : null;
    final createdAtMillis = map['created_at'] is num
        ? (map['created_at'] as num).toInt()
        : int.tryParse('${map['created_at']}');
    return JournalAttachment(
      id: map['uuid']?.toString() ?? map['id']?.toString(),
      entryId: map['entry_uuid']?.toString() ?? '',
      localPath: map['local_path']?.toString(),
      imageData: imageData,
      mimeType: map['mime_type']?.toString() ?? 'image/jpeg',
      width: (map['width'] as num?)?.toInt(),
      height: (map['height'] as num?)?.toInt(),
      sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
      fileSize: (map['file_size'] as num?)?.toInt() ?? imageData?.length ?? 0,
      createdAt: createdAtMillis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(createdAtMillis),
    );
  }
}
