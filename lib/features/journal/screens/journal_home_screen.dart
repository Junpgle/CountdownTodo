import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/journal_entry.dart';
import '../services/journal_media_service.dart';
import '../services/journal_picker.dart';
import '../services/journal_storage.dart';
import 'journal_detail_screen.dart';
import 'journal_editor_screen.dart';

class JournalHomeScreen extends StatefulWidget {
  final String username;

  const JournalHomeScreen({
    super.key,
    required this.username,
  });

  @override
  State<JournalHomeScreen> createState() => _JournalHomeScreenState();
}

class _JournalHomeScreenState extends State<JournalHomeScreen> {
  static const _pageSize = 40;
  final _storage = JournalStorage.instance;
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  List<JournalEntry> _entries = const [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  bool _isPhotoWall = false;
  String _query = '';
  int _loadRequest = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_maybeLoadMore);
    _initialize();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadEntries({bool reset = true}) async {
    if (!reset && (_isLoading || _isLoadingMore || !_hasMore)) return;
    final request = ++_loadRequest;
    if (mounted) {
      setState(() {
        if (reset) {
          _isLoading = true;
          _hasMore = true;
        } else {
          _isLoadingMore = true;
        }
      });
    }
    try {
      final entries = await _storage.loadEntries(
        accountId: widget.username,
        limit: _pageSize,
        offset: reset ? 0 : _entries.length,
        searchQuery: _query,
      );
      if (!mounted || request != _loadRequest) return;
      setState(() {
        _entries = reset ? entries : [..._entries, ...entries];
        _hasMore = entries.length == _pageSize;
      });
    } catch (_) {
      if (mounted && request == _loadRequest) {
        _showMessage('日记加载失败，请稍后重试');
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
        _scrollController.position.extentAfter > 480) {
      return;
    }
    _loadEntries(reset: false);
  }

  Future<void> _initialize() async {
    await _recoverLostImagePick();
    if (mounted) await _loadEntries();
  }

  Future<void> _createEntry() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => JournalEditorScreen(accountId: widget.username),
      ),
    );
    if (saved == true) await _loadEntries();
  }

  Future<void> _openEntry(JournalEntry entry) async {
    final fullEntry = await _storage.loadEntry(entry.id);
    if (!mounted || fullEntry == null) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => JournalDetailScreen(
          accountId: widget.username,
          entry: fullEntry,
        ),
      ),
    );
    if (changed == true) await _loadEntries();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final entries = _entries;
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 900;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        titleSpacing: 20,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '日记',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            Text(
              _entries.isEmpty
                  ? '给此刻留一个位置'
                  : _hasMore
                      ? '已加载 ${_entries.length} 篇记录'
                      : '${_entries.length} 篇记录',
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '搜索日记',
            onPressed: () => _showSearch(context),
            icon: const Icon(Icons.search_rounded),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              segments: const [
                ButtonSegment(
                    value: false, icon: Icon(Icons.view_agenda_rounded)),
                ButtonSegment(value: true, icon: Icon(Icons.grid_view_rounded)),
              ],
              selected: {_isPhotoWall},
              onSelectionChanged: (values) {
                setState(() => _isPhotoWall = values.first);
              },
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : entries.isEmpty
              ? _JournalEmptyState(
                  hasSearch: _query.isNotEmpty,
                  onCreate: _createEntry,
                  onClearSearch: () async {
                    setState(() {
                      _query = '';
                      _searchController.clear();
                    });
                    await _loadEntries();
                  },
                )
              : RefreshIndicator(
                  onRefresh: _loadEntries,
                  child: _isPhotoWall
                      ? _PhotoWall(
                          entries: entries,
                          isWide: isWide,
                          controller: _scrollController,
                          onTap: _openEntry,
                        )
                      : _Timeline(
                          entries: entries,
                          isWide: isWide,
                          controller: _scrollController,
                          isLoadingMore: _isLoadingMore,
                          onTap: _openEntry,
                        ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createEntry,
        icon: const Icon(Icons.edit_rounded),
        label: const Text('写一篇'),
      ),
    );
  }

  Future<void> _showSearch(BuildContext context) async {
    _searchController.text = _query;
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('搜索日记'),
        content: TextField(
          controller: _searchController,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: '搜索标题或正文',
            prefixIcon: Icon(Icons.search_rounded),
          ),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, ''),
            child: const Text('清除'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _searchController.text),
            child: const Text('搜索'),
          ),
        ],
      ),
    );
    if (value != null && mounted) {
      setState(() => _query = value);
      await _loadEntries();
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _recoverLostImagePick() async {
    final recovered = await recoverPendingJournalPick(widget.username);
    if (!mounted || recovered == null) return;
    if (recovered.error != null) {
      await clearPendingJournalPick();
      _showMessage('未能恢复上次选择的图片，请重新选择');
      return;
    }
    if (recovered.files.isEmpty &&
        !await JournalMediaService.instance.hasDraft(
          accountId: widget.username,
          draftId: recovered.context.draftId,
        )) {
      await clearPendingJournalPick();
      return;
    }

    JournalEntry? entry;
    if (recovered.context.isEditing) {
      entry = await _storage.loadEntry(recovered.context.entryId);
      if (!mounted || entry == null) {
        await clearPendingJournalPick();
        _showMessage('未找到待恢复的日记，图片未导入');
        return;
      }
    }
    if (!mounted) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => JournalEditorScreen(
          accountId: widget.username,
          entry: entry,
          recoveredFiles: recovered.files,
          restoredEntryId: recovered.context.entryId,
          restoredDraftId: recovered.context.draftId,
        ),
      ),
    );
    if (saved == true) await _loadEntries();
  }
}

class _Timeline extends StatelessWidget {
  final List<JournalEntry> entries;
  final bool isWide;
  final ScrollController controller;
  final bool isLoadingMore;
  final ValueChanged<JournalEntry> onTap;

  const _Timeline({
    required this.entries,
    required this.isWide,
    required this.controller,
    required this.isLoadingMore,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<JournalEntry>>{};
    for (final entry in entries) {
      final key = DateFormat('yyyy年MM月').format(entry.occurredAt);
      grouped.putIfAbsent(key, () => []).add(entry);
    }
    return ListView(
      controller: controller,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(isWide ? 40 : 20, 12, isWide ? 40 : 20, 120),
      children: [
        for (final group in grouped.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 18, 4, 12),
            child: Row(
              children: [
                Text(
                  group.key,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Divider(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
              ],
            ),
          ),
          if (isWide)
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: group.value.length,
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 560,
                mainAxisExtent: 220,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              itemBuilder: (_, index) => _JournalCard(
                entry: group.value[index],
                onTap: () => onTap(group.value[index]),
              ),
            )
          else
            for (final entry in group.value) ...[
              _JournalCard(entry: entry, onTap: () => onTap(entry)),
              const SizedBox(height: 14),
            ],
        ],
        if (isLoadingMore)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }
}

class _PhotoWall extends StatelessWidget {
  final List<JournalEntry> entries;
  final bool isWide;
  final ScrollController controller;
  final ValueChanged<JournalEntry> onTap;

  const _PhotoWall({
    required this.entries,
    required this.isWide,
    required this.controller,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final columns = isWide ? 4 : 2;
    return GridView.builder(
      controller: controller,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(isWide ? 40 : 16, 20, isWide ? 40 : 16, 120),
      itemCount: entries.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: isWide ? 0.92 : 0.82,
      ),
      itemBuilder: (_, index) => _PhotoWallCard(
        entry: entries[index],
        onTap: () => onTap(entries[index]),
      ),
    );
  }
}

class _JournalCard extends StatelessWidget {
  final JournalEntry entry;
  final VoidCallback onTap;

  const _JournalCard({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final preview = entry.content.trim().replaceAll(RegExp(r'\s+'), ' ');
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            if (entry.attachments.isNotEmpty)
              SizedBox(
                width: 136,
                height: 188,
                child: _JournalImage(
                  attachment: entry.attachments.first,
                  fit: BoxFit.cover,
                ),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      DateFormat('MM月dd日 · E', 'zh_CN')
                          .format(entry.occurredAt),
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      entry.title?.trim().isNotEmpty == true
                          ? entry.title!.trim()
                          : '无题',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    if (preview.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        preview,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                              height: 1.45,
                            ),
                      ),
                    ],
                    if (entry.attachments.length > 1) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(Icons.collections_rounded,
                              size: 15, color: scheme.onSurfaceVariant),
                          const SizedBox(width: 4),
                          Text('${entry.attachments.length} 张图片',
                              style: Theme.of(context).textTheme.labelSmall),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Icon(Icons.chevron_right_rounded,
                  color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoWallCard extends StatelessWidget {
  final JournalEntry entry;
  final VoidCallback onTap;

  const _PhotoWallCard({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: entry.attachments.isEmpty
                  ? Container(
                      color: scheme.primaryContainer,
                      alignment: Alignment.center,
                      child: Icon(Icons.notes_rounded,
                          size: 42, color: scheme.onPrimaryContainer),
                    )
                  : _JournalImage(
                      attachment: entry.attachments.first,
                      fit: BoxFit.cover,
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    DateFormat('MM月dd日').format(entry.occurredAt),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    entry.title?.trim().isNotEmpty == true
                        ? entry.title!.trim()
                        : entry.content.trim().isNotEmpty
                            ? entry.content.trim()
                            : '图片日记',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _JournalImage extends StatefulWidget {
  final JournalAttachment attachment;
  final BoxFit fit;

  const _JournalImage({required this.attachment, required this.fit});

  @override
  State<_JournalImage> createState() => _JournalImageState();
}

class _JournalImageState extends State<_JournalImage> {
  Future<JournalAttachment?>? _attachmentFuture;

  @override
  void initState() {
    super.initState();
    _resolveAttachment();
  }

  @override
  void didUpdateWidget(covariant _JournalImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachment.id != widget.attachment.id) {
      _resolveAttachment();
    }
  }

  void _resolveAttachment() {
    _attachmentFuture =
        JournalMediaService.instance.provider(widget.attachment) == null
            ? JournalStorage.instance.loadAttachment(widget.attachment.id)
            : null;
  }

  @override
  Widget build(BuildContext context) {
    if (_attachmentFuture == null) {
      return _buildImage(context, widget.attachment);
    }
    return FutureBuilder<JournalAttachment?>(
      future: _attachmentFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return ColoredBox(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        return _buildImage(context, snapshot.data ?? widget.attachment);
      },
    );
  }

  Widget _buildImage(BuildContext context, JournalAttachment attachment) {
    final provider = JournalMediaService.instance.provider(attachment);
    if (provider == null) {
      return ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Center(child: Icon(Icons.broken_image_outlined)),
      );
    }
    return Image(
        image: provider,
        fit: widget.fit,
        width: double.infinity,
        height: double.infinity);
  }
}

class _JournalEmptyState extends StatelessWidget {
  final bool hasSearch;
  final VoidCallback onCreate;
  final VoidCallback onClearSearch;

  const _JournalEmptyState({
    required this.hasSearch,
    required this.onCreate,
    required this.onClearSearch,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 112,
              height: 112,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.primaryContainer,
              ),
              child: Icon(Icons.auto_stories_rounded,
                  size: 52, color: scheme.onPrimaryContainer),
            ),
            const SizedBox(height: 24),
            Text(
              hasSearch ? '没有找到相关日记' : '今天不写也没关系',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              hasSearch ? '换个关键词试试吧' : '想记录的时候，随时回来就好。',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            if (hasSearch)
              OutlinedButton.icon(
                onPressed: onClearSearch,
                icon: const Icon(Icons.close_rounded),
                label: const Text('清除搜索'),
              )
            else
              FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.edit_rounded),
                label: const Text('写下第一篇'),
              ),
          ],
        ),
      ),
    );
  }
}
