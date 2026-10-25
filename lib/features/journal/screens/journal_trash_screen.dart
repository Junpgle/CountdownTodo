import 'dart:async';

import 'package:flutter/material.dart';

import '../../../utils/app_dialogs.dart';
import '../../../utils/time_utils.dart';
import '../../../widgets/floating_glass_control.dart';
import '../models/journal_entry.dart';
import '../services/journal_media_service.dart';
import '../services/journal_storage.dart';

class JournalTrashScreen extends StatefulWidget {
  final String accountId;
  final JournalStorage? storage;

  const JournalTrashScreen({super.key, required this.accountId, this.storage});

  @override
  State<JournalTrashScreen> createState() => _JournalTrashScreenState();
}

class _JournalTrashScreenState extends State<JournalTrashScreen> {
  static const _pageSize = 40;

  JournalStorage get _storage => widget.storage ?? JournalStorage.instance;

  final _scrollController = ScrollController();
  List<JournalEntry> _entries = const [];
  final Set<String> _busyEntryIds = {};
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _loadError;
  int _loadRequest = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_maybeLoadMore);
    _load();
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_maybeLoadMore)
      ..dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = true}) async {
    if (!reset && (_isLoading || _isLoadingMore || !_hasMore)) return;
    final request = ++_loadRequest;
    if (mounted) {
      setState(() {
        if (reset) {
          _isLoading = true;
          _loadError = null;
          _hasMore = true;
        } else {
          _isLoadingMore = true;
        }
      });
    }
    try {
      final entries = await _storage.loadTrashEntries(
        accountId: widget.accountId,
        limit: _pageSize,
        offset: reset ? 0 : _entries.length,
      );
      if (!mounted || request != _loadRequest) return;
      setState(() {
        _entries = reset ? entries : [..._entries, ...entries];
        _hasMore = entries.length == _pageSize;
      });
    } catch (_) {
      if (!mounted || request != _loadRequest) return;
      if (reset) {
        setState(() => _loadError = '回收站暂时无法读取');
      } else {
        AppSnackBars.showSnackBar(
          context,
          const SnackBar(content: Text('加载更多失败，请稍后重试')),
        );
      }
    } finally {
      if (mounted && request == _loadRequest) {
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  void _maybeLoadMore() {
    if (!_scrollController.hasClients ||
        _scrollController.position.extentAfter > 420) {
      return;
    }
    unawaited(_load(reset: false));
  }

  Future<void> _restore(JournalEntry entry) async {
    if (!_busyEntryIds.add(entry.id)) return;
    setState(() {});
    try {
      final restored = await _storage.restoreEntryFromTrash(
        entry.id,
        accountId: widget.accountId,
      );
      if (!mounted) return;
      if (!restored) {
        _showMessage('日记已变化，请刷新回收站后重试');
        await _load();
        return;
      }
      _showMessage('日记已恢复');
      await _load();
    } catch (_) {
      if (mounted) _showMessage('恢复失败，日记仍保留在回收站');
    } finally {
      _busyEntryIds.remove(entry.id);
      if (mounted) setState(() {});
    }
  }

  Future<void> _permanentlyDelete(JournalEntry entry) async {
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('永久删除这篇日记？'),
        content: Text(
          '“${entry.title?.trim().isNotEmpty == true ? entry.title : '无题'}”'
          '及其 ${entry.attachments.length} 张照片将从本机删除，无法恢复。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('永久删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || !_busyEntryIds.add(entry.id)) return;
    setState(() {});
    try {
      final attachments = await _storage.permanentlyDeleteEntryFromTrash(
        entry.id,
        accountId: widget.accountId,
      );
      if (!mounted) return;
      if (attachments == null) {
        _showMessage('日记已变化，请刷新回收站后重试');
        await _load();
        return;
      }

      var mediaCleanupFailed = false;
      for (final attachment in attachments) {
        try {
          await JournalMediaService.instance.delete(attachment);
        } catch (_) {
          mediaCleanupFailed = true;
        }
      }
      if (mediaCleanupFailed) _storage.invalidateMediaReconciliation();
      _showMessage('日记已永久删除');
      await _load();
    } catch (_) {
      if (mounted) _showMessage('永久删除失败，日记仍保留在回收站');
    } finally {
      _busyEntryIds.remove(entry.id);
      if (mounted) setState(() {});
    }
  }

  void _showMessage(String message) {
    AppSnackBars.showSnackBar(context, SnackBar(content: Text(message)));
  }

  Widget _buildEmptyState(ColorScheme colorScheme) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 84),
        Icon(
          Icons.delete_outline_rounded,
          size: 48,
          color: colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 16),
        Text(
          '回收站空空如也',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          '移入回收站的日记和照片会保留在本机，可随时恢复。',
          textAlign: TextAlign.center,
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _buildEntryCard(JournalEntry entry, ColorScheme colorScheme) {
    final busy = _busyEntryIds.contains(entry.id);
    final title = entry.title?.trim().isNotEmpty == true
        ? entry.title!.trim()
        : '无题';
    final excerpt = entry.content.trim();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              AppTimeFormats.format(entry.occurredAt, 'yyyy年MM月dd日 HH:mm'),
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
            if (excerpt.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(excerpt, maxLines: 3, overflow: TextOverflow.ellipsis),
            ],
            if (entry.attachments.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.photo_library_outlined,
                    size: 17,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${entry.attachments.length} 张照片保留在本机',
                    style: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: busy ? null : () => _restore(entry),
                    icon: const Icon(Icons.restore_rounded),
                    label: Text(busy ? '处理中…' : '恢复'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: '永久删除',
                  onPressed: busy ? null : () => _permanentlyDelete(entry),
                  icon: const Icon(Icons.delete_forever_outlined),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final topBarHeight = floatingGlassTopBarHeight(context);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: FloatingGlassAppBar(
        flexibleSpace: const FloatingGlassTopBarBackground(),
        title: const Text('日记回收站'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _isLoading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FloatingGlassTopBarContentFade(
        topBarHeight: topBarHeight,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: SizedBox.expand(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _loadError != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline_rounded, size: 36),
                          const SizedBox(height: 12),
                          const Text('回收站暂时无法读取'),
                          const SizedBox(height: 12),
                          FilledButton.tonalIcon(
                            onPressed: _load,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('重新加载'),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: _entries.isEmpty
                          ? _buildEmptyState(colorScheme)
                          : ListView.builder(
                              controller: _scrollController,
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: EdgeInsets.fromLTRB(
                                16,
                                topBarHeight + 12,
                                16,
                                32,
                              ),
                              itemCount: _entries.length + (_hasMore ? 1 : 0),
                              itemBuilder: (context, index) {
                                if (index >= _entries.length) {
                                  return Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Center(
                                      child: _isLoadingMore
                                          ? const CircularProgressIndicator()
                                          : const SizedBox.shrink(),
                                    ),
                                  );
                                }
                                return _buildEntryCard(
                                  _entries[index],
                                  colorScheme,
                                );
                              },
                            ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
