import 'dart:typed_data';

import 'package:countdown_todo/features/journal/models/journal_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('journal entry round trips its content and timestamps', () {
    final occurredAt = DateTime(2026, 8, 12, 20, 30);
    final createdAt = DateTime(2026, 8, 12, 20, 31);
    final entry = JournalEntry(
      id: 'entry-1',
      title: '夏夜',
      content: '风很轻。',
      occurredAt: occurredAt,
      createdAt: createdAt,
      updatedAt: createdAt,
    );

    final restored = JournalEntry.fromMap(entry.toMap());

    expect(restored.id, entry.id);
    expect(restored.title, entry.title);
    expect(restored.content, entry.content);
    expect(restored.occurredAt, occurredAt);
    expect(restored.createdAt, createdAt);
  });

  test('journal entry round trips its deleted state', () {
    final entry = JournalEntry(
      id: 'entry-in-trash',
      content: '本地回收站',
      isDeleted: true,
    );

    final restored = JournalEntry.fromMap(entry.toMap());

    expect(restored.isDeleted, isTrue);
    expect(entry.copyWith(isDeleted: false).isDeleted, isFalse);
  });

  test('journal attachment preserves browser image bytes', () {
    final bytes = Uint8List.fromList([1, 2, 3]);
    final attachment = JournalAttachment(
      id: 'attachment-1',
      entryId: 'entry-1',
      imageData: bytes,
      mimeType: 'image/png',
      sortOrder: 2,
      fileSize: bytes.length,
    );

    final restored = JournalAttachment.fromMap(attachment.toMap());

    expect(restored.id, attachment.id);
    expect(restored.entryId, attachment.entryId);
    expect(restored.mimeType, 'image/png');
    expect(restored.sortOrder, 2);
    expect(restored.imageData, bytes);
  });
}
