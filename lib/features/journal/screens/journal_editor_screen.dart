import '../../../widgets/floating_glass_control.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';

import '../models/journal_entry.dart';
import '../services/journal_media_service.dart';
import '../services/journal_picker.dart';
import '../services/journal_picker_context.dart';
import '../services/journal_storage.dart';
import '../../../widgets/optional_liquid_glass_surface.dart';

class JournalEditorScreen extends StatefulWidget {
  final String accountId;
  final JournalEntry? entry;
  final List<XFile> recoveredFiles;
  final String? restoredEntryId;
  final String? restoredDraftId;

  const JournalEditorScreen({
    super.key,
    required this.accountId,
    this.entry,
    this.recoveredFiles = const [],
    this.restoredEntryId,
    this.restoredDraftId,
  });

  @override
  State<JournalEditorScreen> createState() => _JournalEditorScreenState();
}

class _JournalEditorScreenState extends State<JournalEditorScreen> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  DateTime _occurredAt = DateTime.now();
  List<JournalAttachment> _attachments = [];
  bool _isSaving = false;
  bool _dirty = false;

  bool get _isEditing => widget.entry != null;
  late final String _entryId =
      widget.entry?.id ?? widget.restoredEntryId ?? JournalEntry().id;
  late final String _draftId = widget.restoredDraftId ?? JournalEntry().id;

  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    if (entry != null) {
      _titleController.text = entry.title ?? '';
      _contentController.text = entry.content;
      _occurredAt = entry.occurredAt;
      _attachments = List.of(entry.attachments);
    }
    _titleController.addListener(_markDirty);
    _contentController.addListener(_markDirty);
    if (widget.restoredDraftId != null || widget.recoveredFiles.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _restoreAfterRestart();
      });
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  void _markDirty() {
    if (!_dirty && mounted) setState(() => _dirty = true);
  }

  Future<void> _pickImages() async {
    try {
      await savePendingJournalPick(_pickerContext);
      final files = await pickJournalImages();
      await _importImages(files);
      await clearPendingJournalPick();
    } catch (_) {
      await clearPendingJournalPick();
      if (mounted) _showMessage('无法打开图片选择器，请重试');
    }
  }

  JournalImagePickContext get _pickerContext => JournalImagePickContext(
        accountId: widget.accountId,
        entryId: _entryId,
        draftId: _draftId,
        isEditing: _isEditing,
      );

  Future<void> _restoreAfterRestart() async {
    if (widget.restoredDraftId != null) {
      final draftAttachments =
          await JournalMediaService.instance.restoreDraftAttachments(
        accountId: widget.accountId,
        draftId: _draftId,
        entryId: _entryId,
      );
      if (!mounted) return;
      if (draftAttachments.isNotEmpty) {
        setState(() {
          _attachments.addAll(draftAttachments);
          _dirty = true;
        });
      }
    }
    if (widget.recoveredFiles.isNotEmpty && mounted) {
      await _importImages(widget.recoveredFiles, recoveredAfterRestart: true);
    }
    if (mounted) await clearPendingJournalPick();
  }

  Future<void> _importImages(
    List<XFile> files, {
    bool recoveredAfterRestart = false,
  }) async {
    if (files.isEmpty) return;
    final remaining = 9 - _attachments.length;
    if (remaining <= 0) {
      _showMessage('最多添加 9 张图片');
      return;
    }
    setState(() => _isSaving = true);
    final added = <JournalAttachment>[];
    try {
      for (final file in files.take(remaining)) {
        added.add(await JournalMediaService.instance.importImage(
          accountId: widget.accountId,
          draftId: _draftId,
          entryId: _entryId,
          file: file,
          sortOrder: _attachments.length + added.length,
        ));
      }
      if (!mounted) {
        for (final attachment in added) {
          await JournalMediaService.instance.delete(attachment);
        }
        return;
      }
      setState(() {
        _attachments.addAll(added);
        _dirty = true;
      });
      if (recoveredAfterRestart) {
        _showMessage('已恢复刚才选择的 ${added.length} 张图片');
      }
    } catch (_) {
      for (final attachment in added) {
        await JournalMediaService.instance.delete(attachment);
      }
      if (mounted) _showMessage('图片添加失败，请重新选择');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _takePhoto() async {
    final isDesktop = Theme.of(context).platform == TargetPlatform.windows ||
        Theme.of(context).platform == TargetPlatform.macOS ||
        Theme.of(context).platform == TargetPlatform.linux;
    XFile? file;
    try {
      await savePendingJournalPick(_pickerContext);
      file = await takeJournalPhoto();
    } catch (_) {
      await clearPendingJournalPick();
      if (mounted) _showMessage('无法打开相机，请检查权限后重试');
      return;
    }
    if (file == null || _attachments.length >= 9) {
      await clearPendingJournalPick();
      if (_attachments.length >= 9) {
        _showMessage('最多添加 9 张图片');
      } else if (isDesktop && mounted) {
        _showMessage('桌面端暂不支持拍照，请从文件中选择图片');
      }
      return;
    }
    await _importImages([file]);
    await clearPendingJournalPick();
  }

  Future<void> _selectDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _occurredAt,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('zh', 'CN'),
    );
    if (date == null || !mounted) return;
    setState(() {
      _occurredAt = DateTime(
        date.year,
        date.month,
        date.day,
        _occurredAt.hour,
        _occurredAt.minute,
      );
      _dirty = true;
    });
  }

  Future<void> _save() async {
    if (_isSaving) return;
    if (_titleController.text.trim().isEmpty &&
        _contentController.text.trim().isEmpty &&
        _attachments.isEmpty) {
      _showMessage('写点文字或添加一张图片吧');
      return;
    }
    setState(() => _isSaving = true);
    final now = DateTime.now();
    final entry = (widget.entry ?? JournalEntry(id: _entryId)).copyWith(
      title: _titleController.text.trim().isEmpty
          ? null
          : _titleController.text.trim(),
      content: _contentController.text,
      occurredAt: _occurredAt,
      updatedAt: now,
      attachments: _attachments,
      clearTitle: _titleController.text.trim().isEmpty,
    );
    JournalMediaCommit? mediaCommit;
    var savedToDatabase = false;
    try {
      mediaCommit = await JournalMediaService.instance.commitDraft(
        accountId: widget.accountId,
        draftId: _draftId,
        entryId: entry.id,
        attachments: _attachments,
      );
      final savedAttachments = mediaCommit.attachments;
      await JournalStorage.instance.saveEntry(entry, savedAttachments);
      savedToDatabase = true;
      final currentIds = savedAttachments.map((item) => item.id).toSet();
      for (final attachment
          in widget.entry?.attachments ?? const <JournalAttachment>[]) {
        if (!currentIds.contains(attachment.id)) {
          try {
            await JournalMediaService.instance.delete(attachment);
          } catch (_) {
            // The database is already correct; the startup reconciliation will
            // remove an inaccessible orphan on the next journal launch.
          }
        }
      }
      try {
        await JournalMediaService.instance.discardDraft(
          accountId: widget.accountId,
          draftId: _draftId,
        );
      } catch (_) {
        // A remaining draft is safe and will be cleared at the next launch.
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!savedToDatabase && mediaCommit != null) {
        for (final attachment in mediaCommit.createdAttachments) {
          await JournalMediaService.instance.delete(attachment);
        }
      }
      if (mounted && !savedToDatabase) {
        _showMessage('保存失败，内容仍保留在当前页面');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<bool> _confirmExit() async {
    if (_isSaving) {
      _showMessage('正在保存，请稍候');
      return false;
    }
    if (!_dirty) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('放弃这篇日记？'),
        content: const Text('目前的内容还没有保存。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('继续编辑'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('放弃'),
          ),
        ],
      ),
    );
    if (discard != true) return false;
    await _removeUnsavedMedia();
    return true;
  }

  Future<void> _removeUnsavedMedia() async {
    await JournalMediaService.instance.discardDraft(
      accountId: widget.accountId,
      draftId: _draftId,
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmExit() && context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
        appBar: FloatingGlassAppBar(
          flexibleSpace: const FloatingGlassTopBarBackground(),
          title: Text(_isEditing ? '编辑日记' : '写日记'),
          leading: IconButton(
            tooltip: '关闭',
            onPressed: () async {
              if (await _confirmExit() && context.mounted) {
                Navigator.pop(context);
              }
            },
            icon: const Icon(Icons.close_rounded),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton(
                onPressed: _isSaving ? null : _save,
                child: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('保存'),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
                children: [
                  TextButton.icon(
                    onPressed: _selectDate,
                    style:
                        TextButton.styleFrom(alignment: Alignment.centerLeft),
                    icon: Icon(Icons.calendar_today_rounded,
                        size: 18, color: scheme.primary),
                    label: Text(
                      DateFormat('yyyy年MM月dd日 · E', 'zh_CN')
                          .format(_occurredAt),
                      style: TextStyle(
                          color: scheme.primary, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: 8),
                  OptionalLiquidGlassCard(
                    borderRadius: 24,
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                    highContrast: true,
                    tint: scheme.primary.withValues(alpha: 0.08),
                    fallbackDecoration: BoxDecoration(
                      color: scheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: scheme.outlineVariant.withValues(alpha: 0.55),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _titleController,
                          textCapitalization: TextCapitalization.sentences,
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                          decoration: const InputDecoration(
                            hintText: '给今天一个标题',
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            isCollapsed: true,
                            contentPadding: EdgeInsets.symmetric(vertical: 4),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Divider(
                          height: 1,
                          thickness: 0.8,
                          color: scheme.outlineVariant.withValues(alpha: 0.35),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _contentController,
                          minLines: 8,
                          maxLines: null,
                          keyboardType: TextInputType.multiline,
                          textCapitalization: TextCapitalization.sentences,
                          style:
                              theme.textTheme.bodyLarge?.copyWith(height: 1.65),
                          decoration: const InputDecoration(
                            hintText: '写下此刻想留下的东西……',
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            isCollapsed: true,
                            contentPadding: EdgeInsets.symmetric(vertical: 4),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_attachments.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _AttachmentEditor(
                      attachments: _attachments,
                      onChanged: (value) => setState(() {
                        _attachments = value;
                        _dirty = true;
                      }),
                    ),
                  ],
                  const SizedBox(height: 24),
                  OptionalLiquidGlassCard(
                    borderRadius: 24,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    highContrast: true,
                    tint: scheme.primary.withValues(alpha: 0.06),
                    fallbackDecoration: BoxDecoration(
                      color: scheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: scheme.outlineVariant.withValues(alpha: 0.55),
                      ),
                    ),
                    child: Row(
                      children: [
                        IconButton.filledTonal(
                          tooltip: '从相册添加',
                          onPressed: _isSaving ? null : _pickImages,
                          icon: const Icon(Icons.photo_library_rounded),
                        ),
                        const SizedBox(width: 4),
                        IconButton.filledTonal(
                          tooltip: '拍照添加',
                          onPressed: _isSaving ? null : _takePhoto,
                          icon: const Icon(Icons.photo_camera_rounded),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _attachments.isEmpty
                                ? '添加几张图片，让这段记忆更完整'
                                : '${_attachments.length}/9 张图片 · 长按可拖动排序',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '日记只保存在本机，不会公开或上传。',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AttachmentEditor extends StatelessWidget {
  final List<JournalAttachment> attachments;
  final ValueChanged<List<JournalAttachment>> onChanged;

  const _AttachmentEditor({required this.attachments, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 120,
      child: ReorderableListView.builder(
        scrollDirection: Axis.horizontal,
        buildDefaultDragHandles: false,
        itemCount: attachments.length,
        onReorderItem: (oldIndex, newIndex) {
          final next = List<JournalAttachment>.of(attachments);
          final item = next.removeAt(oldIndex);
          next.insert(newIndex, item);
          onChanged(next);
        },
        itemBuilder: (context, index) {
          final attachment = attachments[index];
          final provider = JournalMediaService.instance.provider(attachment);
          return Padding(
            key: ValueKey(attachment.id),
            padding: const EdgeInsets.only(right: 10),
            child: ReorderableDragStartListener(
              index: index,
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: SizedBox(
                      width: 120,
                      height: 120,
                      child: provider == null
                          ? const ColoredBox(color: Colors.black12)
                          : Image(image: provider, fit: BoxFit.cover),
                    ),
                  ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: IconButton(
                      visualDensity: VisualDensity.compact,
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black54,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () {
                        final next = List<JournalAttachment>.of(attachments)
                          ..removeAt(index);
                        onChanged(next);
                      },
                      icon: const Icon(Icons.close_rounded, size: 16),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
