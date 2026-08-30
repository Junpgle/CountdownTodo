import '../../../widgets/floating_glass_control.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/journal_entry.dart';
import '../services/journal_media_service.dart';
import '../services/journal_storage.dart';
import 'journal_editor_screen.dart';

class JournalDetailScreen extends StatefulWidget {
  final String accountId;
  final JournalEntry entry;

  const JournalDetailScreen({
    super.key,
    required this.accountId,
    required this.entry,
  });

  @override
  State<JournalDetailScreen> createState() => _JournalDetailScreenState();
}

class _JournalDetailScreenState extends State<JournalDetailScreen> {
  late JournalEntry _entry;

  @override
  void initState() {
    super.initState();
    _entry = widget.entry;
  }

  Future<void> _edit() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => JournalEditorScreen(
          accountId: widget.accountId,
          entry: _entry,
        ),
      ),
    );
    if (changed != true || !mounted) return;
    final refreshed = await JournalStorage.instance.loadEntry(_entry.id);
    if (refreshed == null || !mounted) return;
    setState(() => _entry = refreshed);
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这篇日记？'),
        content: const Text('删除后无法恢复。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final deleted = await JournalStorage.instance.deleteEntry(_entry.id);
      for (final attachment in deleted) {
        try {
          await JournalMediaService.instance.delete(attachment);
        } catch (_) {
          // The entry has been removed. A later media reconciliation will
          // clean any inaccessible leftover file without blocking navigation.
        }
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('删除失败，请稍后重试')),
        );
      }
    }
  }

  void _openImage(int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _JournalGalleryViewer(
          attachments: _entry.attachments,
          initialIndex: index,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: FloatingGlassAppBar(
        flexibleSpace: const FloatingGlassTopBarBackground(),
        title: Text(DateFormat('yyyy年MM月dd日').format(_entry.occurredAt)),
        actions: [
          IconButton(
              tooltip: '编辑',
              onPressed: _edit,
              icon: const Icon(Icons.edit_rounded)),
          IconButton(
              tooltip: '删除',
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline_rounded)),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 880),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 48),
              children: [
                Text(
                  DateFormat('EEEE', 'zh_CN').format(_entry.occurredAt),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _entry.title?.trim().isNotEmpty == true
                      ? _entry.title!
                      : '无题',
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1,
                  ),
                ),
                if (_entry.content.trim().isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text(
                    _entry.content,
                    style: theme.textTheme.bodyLarge?.copyWith(height: 1.75),
                  ),
                ],
                if (_entry.attachments.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  _DetailGallery(
                    attachments: _entry.attachments,
                    onTap: _openImage,
                  ),
                ],
                const SizedBox(height: 36),
                Center(
                  child: Text(
                    '记录于 ${DateFormat('yyyy年MM月dd日 HH:mm').format(_entry.createdAt)}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailGallery extends StatelessWidget {
  final List<JournalAttachment> attachments;
  final ValueChanged<int> onTap;

  const _DetailGallery({required this.attachments, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = attachments.length == 1 ? 400.0 : 250.0;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: attachments.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: attachments.length == 1 ? 1 : 2,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            mainAxisExtent: height,
          ),
          itemBuilder: (_, index) {
            final provider =
                JournalMediaService.instance.provider(attachments[index]);
            return ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: InkWell(
                onTap: () => onTap(index),
                child: provider == null
                    ? ColoredBox(
                        color: scheme.surfaceContainerHighest,
                        child: const Icon(Icons.broken_image_outlined),
                      )
                    : Image(image: provider, fit: BoxFit.cover),
              ),
            );
          },
        );
      },
    );
  }
}

class _JournalGalleryViewer extends StatefulWidget {
  final List<JournalAttachment> attachments;
  final int initialIndex;

  const _JournalGalleryViewer(
      {required this.attachments, required this.initialIndex});

  @override
  State<_JournalGalleryViewer> createState() => _JournalGalleryViewerState();
}

class _JournalGalleryViewerState extends State<_JournalGalleryViewer> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: FloatingGlassAppBar(
        flexibleSpace: const FloatingGlassTopBarBackground(),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text('${_index + 1}/${widget.attachments.length}'),
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.attachments.length,
        onPageChanged: (value) => setState(() => _index = value),
        itemBuilder: (_, index) {
          final provider =
              JournalMediaService.instance.provider(widget.attachments[index]);
          return InteractiveViewer(
            minScale: 0.8,
            maxScale: 4,
            child: Center(
              child: provider == null
                  ? const Icon(Icons.broken_image_outlined, color: Colors.white)
                  : Image(image: provider, fit: BoxFit.contain),
            ),
          );
        },
      ),
    );
  }
}
