import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../services/plan_editor_draft_repository.dart';
import '../services/plan_todo_guard.dart';
import '../widgets/plan_block_editor_sheet.dart';

Future<void> openPlanEditorDrafts(
  BuildContext context,
  String username, {
  VoidCallback? onSaved,
  PlanEditorDraftRepository? repository,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => PlanEditorDraftsScreen(
      username: username,
      onSaved: onSaved,
      repository: repository,
    ),
  ),
);

class PlanEditorDraftsScreen extends StatefulWidget {
  const PlanEditorDraftsScreen({
    super.key,
    required this.username,
    this.onSaved,
    this.repository,
  });
  final String username;
  final VoidCallback? onSaved;
  final PlanEditorDraftRepository? repository;
  @override
  State<PlanEditorDraftsScreen> createState() => _PlanEditorDraftsScreenState();
}

class _PlanEditorDraftsScreenState extends State<PlanEditorDraftsScreen>
    with WidgetsBindingObserver {
  late final PlanEditorDraftRepository _repository;
  PlanTodoIdentity? _identity;
  List<PlanDraftSummary> _rows = [];
  String? _error;
  bool _loading = true, _opening = false;
  int _sequence = 0;
  final Map<(String?, String), DateFormat> _dateFormatters = {};

  DateFormat _cachedDateFormat(String pattern) {
    final locale = Intl.defaultLocale;
    return _dateFormatters.putIfAbsent(
      (locale, pattern),
      () => DateFormat(pattern, locale),
    );
  }

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? PlanEditorDraftRepository();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void dispose() {
    _sequence++;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_opening) unawaited(_load());
  }

  String _message(Object error) =>
      error is StateError ? error.message.toString() : '$error';
  Future<void> _load() async {
    final sequence = ++_sequence;
    setState(() {
      _loading = true;
      _error = null;
      _rows = [];
    });
    try {
      final identity = await PlanTodoIdentity.capture(widget.username);
      final rows = await _repository.list(identity);
      if (!mounted || sequence != _sequence) return;
      setState(() {
        _rows = rows;
        _identity = identity;
        _loading = false;
      });
    } catch (error) {
      if (mounted && sequence == _sequence) {
        setState(() {
          _error = '草稿读取失败：${_message(error)}';
          _loading = false;
        });
      }
    }
  }

  Future<void> _details(PlanDraftSummary row, {String? reason}) async {
    PlanEditorDraft? draft;
    try {
      draft = await _repository.read(_identity!, row.id);
    } catch (error) {
      reason ??= _message(error);
    }
    if (!mounted) return;
    final f = draft?.fields;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(row.title),
        content: SingleChildScrollView(
          child: SelectableText(
            [
              ?reason,
              if (f != null) ...[
                if (f.origin == 'reuse') '沿用规划设置',
                if (f.split == null)
                  '${_time(f.start)} — ${_time(f.end)}'
                else ...[
                  '${f.split!.slots.length}段 · 共${f.split!.query.total}分钟',
                  for (final slot in f.split!.slots)
                    '${_time(slot.start.millisecondsSinceEpoch)} — ${_time(slot.end.millisecondsSinceEpoch)} · ${slot.minutes}分钟',
                ],
                '单轮番茄 ${f.pomodoro}分钟 · ${f.rounds == 0 ? '按规划时长' : '${f.rounds}轮'}',
                f.reminder == 0 ? '不提醒' : '提前${f.reminder}分钟提醒',
                if (f.remark.isNotEmpty) f.remark,
              ],
            ].join('\n\n'),
          ),
        ),
        actions: [
          if (f != null && f.remark.isNotEmpty)
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: f.remark));
                if (c.mounted) {
                  ScaffoldMessenger.of(c)
                      .showSnackBar(const SnackBar(content: Text('备注已复制')));
                }
              },
              child: const Text('复制备注'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _resume(PlanDraftSummary row) async {
    if (_opening || _identity == null) return;
    setState(() => _opening = true);
    try {
      final prepared = await _repository.prepare(
        _identity!,
        row.id,
        row.revision,
      );
      if (!mounted) return;
      if (prepared.saved != null) {
        await _details(
          row,
          reason:
              '这份草稿已保存为规划，不能重复新建。\n'
              '已有规划：${_time(prepared.saved!.startTime)} — ${_time(prepared.saved!.endTime)}',
        );
        return;
      }
      await showPlanBlockEditorPage<void>(
        context: context,
        builder: (_) => PlanBlockEditorSheet(
          username: widget.username,
          fullPage: true,
          todos: [prepared.todo!],
          todoGroups: const [],
          initialTodoId: prepared.todo!.id,
          startTime: DateTime.fromMillisecondsSinceEpoch(
            prepared.draft.fields.start,
          ),
          endTime: DateTime.fromMillisecondsSinceEpoch(
            prepared.draft.fields.end,
          ),
          autoFillEstimateOnTodoChange: false,
          restoredDraft: prepared.draft,
          draftRepository: _repository,
          backlogContext: prepared.backlog,
          clock: _repository.clock,
          onSaved: () => widget.onSaved?.call(),
        ),
      );
    } catch (error) {
      if (mounted) await _details(row, reason: _message(error));
    } finally {
      if (mounted) {
        setState(() => _opening = false);
        await _load();
      }
    }
  }

  Future<void> _delete(PlanDraftSummary row) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('删除本机草稿？'),
        content: Text(row.title),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('删除草稿'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _opening = true);
    try {
      await _repository.delete(_identity!, row.id, row.revision);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_message(error))));
      }
    } finally {
      if (mounted) {
        setState(() => _opening = false);
        await _load();
      }
    }
  }

  String _time(int value) =>
      _cachedDateFormat('M月d日 HH:mm')
          .format(DateTime.fromMillisecondsSinceEpoch(value));
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('规划草稿'),
      actions: [
        IconButton(
          tooltip: '刷新草稿',
          onPressed: _loading || _opening ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!),
                        TextButton(onPressed: _load, child: const Text('重试')),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      '仅保存在本机 · ${_rows.length}/5份',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    if (_rows.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 48),
                        child: Text(
                          '暂无规划草稿\n新建规划时可选择“保留草稿”，稍后继续。',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    for (final row in _rows)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                row.title,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text(
                                row.parts > 1
                                    ? '${row.parts}段 · 共${row.total}分钟 · 日期${_cachedDateFormat('M/d').format(DateTime.fromMillisecondsSinceEpoch(row.start))}至${_cachedDateFormat('M/d').format(DateTime.fromMillisecondsSinceEpoch(row.lastEnd))}'
                                    : '${_time(row.start)} — ${_time(row.end)}',
                              ),
                              Text('保留于 ${_time(row.updatedAt)}'),
                              if (!row.readable) const Text('草稿无法读取，格式暂不支持'),
                              Wrap(
                                spacing: 8,
                                children: [
                                  FilledButton.tonal(
                                    onPressed: _opening
                                        ? null
                                        : () => _resume(row),
                                    child: const Text('继续'),
                                  ),
                                  TextButton(
                                    onPressed: _opening
                                        ? null
                                        : () => _details(row),
                                    child: const Text('查看内容'),
                                  ),
                                  TextButton(
                                    onPressed: _opening
                                        ? null
                                        : () => _delete(row),
                                    child: const Text('删除'),
                                  ),
                                ],
                              ),
                            ],
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
