import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../models/plan_availability.dart';
import '../models/plan_cleanup.dart';
import '../services/database_helper.dart';
import '../services/plan_cleanup_repository.dart';
import '../services/plan_todo_guard.dart';
import '../services/pomodoro_service.dart';
import '../services/notification_service.dart';
import '../storage_service.dart';
import '../widgets/todo_section_widget.dart';
import 'pomodoro_screen.dart';
import 'settings/calendar_sync_page.dart';

bool _affectsPlanCleanup(
  DataRefreshSignal signal, {
  bool includeTodoGroups = false,
}) =>
    signal.affects(DataRefreshDomain.todos) ||
    (includeTodoGroups && signal.affects(DataRefreshDomain.todoGroups)) ||
    signal.affects(DataRefreshDomain.planBlocks) ||
    signal.affects(DataRefreshDomain.pomodoro) ||
    signal.affects(DataRefreshDomain.timeLogs);

/// The editor's current checkbox is not a persisted completion. The entry
/// checks SQL independently and never treats a failed read as zero plans.
class PlanCleanupEntry extends StatefulWidget {
  const PlanCleanupEntry({
    super.key,
    required this.username,
    required this.todoId,
    required this.completionSaved,
    this.onReturn,
    this.repository,
  });
  final String username, todoId;
  final bool completionSaved;
  final Future<void> Function()? onReturn;
  final PlanCleanupRepository? repository;
  @override
  State<PlanCleanupEntry> createState() => _PlanCleanupEntryState();
}

class _PlanCleanupEntryState extends State<PlanCleanupEntry>
    with WidgetsBindingObserver {
  PlanCleanupSnapshot? _value;
  String? _error;
  bool _loading = true, _opening = false, _foreground = true;
  int _sequence = 0;
  Timer? _boundary;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    StorageService.scopedDataRefreshNotifier.addListener(_onScopedDataRefresh);
    _load();
  }

  @override
  void didUpdateWidget(PlanCleanupEntry oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.todoId != widget.todoId ||
        oldWidget.username != widget.username ||
        oldWidget.completionSaved != widget.completionSaved) {
      _load();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      _refresh();
    } else {
      _boundary?.cancel();
      _sequence++;
    }
  }

  void _refresh() {
    if (mounted && !_opening && _foreground) _load();
  }

  void _onScopedDataRefresh() {
    if (!_affectsPlanCleanup(
      StorageService.scopedDataRefreshNotifier.value,
    )) {
      return;
    }
    _refresh();
  }

  Future<void> _load() async {
    final sequence = ++_sequence;
    _boundary?.cancel();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final value = await (widget.repository ?? const PlanCleanupRepository())
          .detail(widget.username, widget.todoId);
      if (!mounted || sequence != _sequence) return;
      setState(() {
        _value = value;
        _loading = false;
      });
      final now = widget.repository?.clock?.call() ?? DateTime.now();
      final boundary = value.nextBoundary;
      if (_foreground && !_opening && boundary != null) {
        final delay = boundary.difference(now);
        _boundary = Timer(
          delay.isNegative ? const Duration(milliseconds: 1) : delay,
          _refresh,
        );
      }
    } catch (_) {
      if (mounted && sequence == _sequence) {
        setState(() {
          _value = null;
          _error = '剩余规划读取失败，点击重试';
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _sequence++;
    _boundary?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    StorageService.scopedDataRefreshNotifier.removeListener(
      _onScopedDataRefresh,
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.completionSaved) return const Text('请先保存待办完成状态，再处理剩余规划');
    if (_loading) return const Text('正在核对剩余规划…');
    if (_error != null) {
      return TextButton(onPressed: _load, child: Text(_error!));
    }
    final value = _value;
    if (value == null || !value.todo.isDone || value.total == 0) {
      return const SizedBox.shrink();
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        key: const ValueKey('todo-cleanup-plans'),
        icon: const Icon(Icons.event_available_outlined),
        label: Text('处理剩余规划 · ${value.total}段'),
        onPressed: _opening
            ? null
            : () async {
                if (_opening) return;
                setState(() => _opening = true);
                _boundary?.cancel();
                try {
                  await value.identity.check();
                  if (!context.mounted) return;
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PlanCleanupScreen(
                        username: widget.username,
                        todoId: widget.todoId,
                        repository: widget.repository,
                      ),
                    ),
                  );
                  await widget.onReturn?.call();
                } catch (_) {
                  if (mounted) setState(() => _error = '身份或规划已变化，请重新核对');
                } finally {
                  _opening = false;
                  if (mounted) await _load();
                }
              },
      ),
    );
  }
}

class PlanCleanupScreen extends StatefulWidget {
  const PlanCleanupScreen({
    super.key,
    required this.username,
    this.todoId,
    this.repository,
    this.clock,
    this.updateReminders,
  });
  final String username;
  final String? todoId;
  final PlanCleanupRepository? repository;
  final DateTime Function()? clock;
  final Future<void> Function()? updateReminders;
  @override
  State<PlanCleanupScreen> createState() => _PlanCleanupScreenState();
}

class _PlanCleanupScreenState extends State<PlanCleanupScreen>
    with WidgetsBindingObserver {
  final _search = TextEditingController();
  final _selected = <String>{};
  late final PlanCleanupRepository _repository;
  PlanTodoIdentity? _identity;
  PlanCleanupPage? _page;
  PlanCleanupSnapshot? _snapshot;
  List<PlanCleanupTodo> _todos = [];
  List<PlanCleanupItem> _items = [];
  PlanCleanupRequest? _pending, _saved;
  String? _folder, _error, _reminderError, _selectionNotice;
  bool _loading = true,
      _working = false,
      _opening = false,
      _inspecting = false,
      _foreground = true,
      _confirming = false,
      _checkingPendingIdentity = false;
  bool _morePageError = false;
  int _sequence = 0;
  Timer? _boundary, _debounce;
  StreamSubscription<PomodoroRunState?>? _focus;
  DateTime get _now => widget.clock?.call() ?? DateTime.now();
  bool get _detail => widget.todoId != null;

  @override
  void initState() {
    super.initState();
    _repository =
        widget.repository ?? PlanCleanupRepository(clock: widget.clock);
    WidgetsBinding.instance.addObserver(this);
    StorageService.scopedDataRefreshNotifier.addListener(_onScopedDataRefresh);
    _focus = PomodoroService.onRunStateChanged.listen(_onFocusRunStateChanged);
    _load(initial: true);
  }

  @override
  void dispose() {
    _sequence++;
    _boundary?.cancel();
    _debounce?.cancel();
    _focus?.cancel();
    StorageService.scopedDataRefreshNotifier.removeListener(
      _onScopedDataRefresh,
    );
    WidgetsBinding.instance.removeObserver(this);
    _search.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      _refresh();
    } else {
      _boundary?.cancel();
      _sequence++;
    }
  }

  void _refresh({bool preserveSelectionWhenUnchanged = false}) {
    if (!mounted || !_foreground || _working || _opening || _saved != null) {
      return;
    }
    final pending = _pending;
    if (pending != null) {
      if (!_checkingPendingIdentity) {
        unawaited(_checkPendingIdentity(pending));
      }
      return;
    }
    unawaited(
      _load(preserveSelectionWhenUnchanged: preserveSelectionWhenUnchanged),
    );
  }

  void _onScopedDataRefresh() {
    if (!_affectsPlanCleanup(
      StorageService.scopedDataRefreshNotifier.value,
      includeTodoGroups: !_detail,
    )) {
      return;
    }
    _refresh(preserveSelectionWhenUnchanged: true);
  }

  void _onFocusRunStateChanged(PomodoroRunState? state) {
    if (!_detail) {
      _refresh();
      return;
    }
    if (_snapshot?.blockedReason.contains('专注') == true) {
      _refresh();
      return;
    }
    if (state?.phase == PomodoroPhase.focusing &&
        (state?.todoUuid == widget.todoId ||
            _items.any((item) => item.id == state?.planBlockId))) {
      _refresh();
    }
  }

  Future<void> _checkPendingIdentity(PlanCleanupRequest pending) async {
    if (_checkingPendingIdentity) return;
    _checkingPendingIdentity = true;
    try {
      await pending.identity.check();
    } catch (error) {
      if (!mounted || !identical(_pending, pending)) return;
      if (error is PlanAvailabilityException &&
          error.message.contains('身份已切换')) {
        setState(() {
          _error = _message(error);
          _selectionNotice = null;
          _selected.clear();
          _pending = null;
          _snapshot = null;
          _items = [];
          _morePageError = false;
        });
      } else {
        setState(() => _error = '${_message(error)}；原提交仍可重试');
      }
    } finally {
      _checkingPendingIdentity = false;
    }
  }

  String _message(Object error) => error is PlanAvailabilityException
      ? error.message
      : error is StateError
      ? error.message.toString()
      : '处理失败，请重试或重新核对';

  Future<void> _load({
    bool more = false,
    bool initial = false,
    bool preserveSelectionWhenUnchanged = false,
  }) async {
    if (_working || _saved != null) return;
    final sequence = ++_sequence;
    final hadPage = _detail ? _snapshot != null : _page != null;
    final hadSelection = _selected.isNotEmpty, hadPending = _pending != null;
    _boundary?.cancel();
    setState(() {
      _loading = true;
      _error = null;
      _morePageError = false;
      _selectionNotice = null;
    });
    try {
      await _identity?.check();
      if (_detail) {
        final snapshot = await _repository.detail(
          widget.username,
          widget.todoId!,
          cursor: more ? _snapshot?.next : null,
        );
        if (!mounted || sequence != _sequence) return;
        _identity ??= snapshot.identity;
        await _identity!.check();
        if (!mounted || sequence != _sequence) return;
        final previousSnapshot = _snapshot;
        final unchanged =
            preserveSelectionWhenUnchanged &&
            !more &&
            previousSnapshot != null &&
            !snapshot.restarted &&
            snapshot.fingerprint == previousSnapshot.fingerprint;
        setState(() {
          final append =
              more &&
              !snapshot.restarted &&
              snapshot.fingerprint == previousSnapshot?.fingerprint;
          _items = append
              ? [..._items, ...snapshot.rows]
              : unchanged
              ? _items
              : snapshot.rows;
          _snapshot = PlanCleanupSnapshot(
            identity: snapshot.identity,
            todo: snapshot.todo,
            rows: List.unmodifiable(_items),
            total: snapshot.total,
            eligible: snapshot.eligible,
            fingerprint: snapshot.fingerprint,
            blockedReason: snapshot.blockedReason,
            nextBoundary: snapshot.nextBoundary,
            restarted: snapshot.restarted,
            next: unchanged ? previousSnapshot.next : snapshot.next,
          );
          if (!append && !unchanged && (hadSelection || hadPending)) {
            _selectionNotice = snapshot.restarted
                ? '规划列表已变化，已清空原选择，请重新选择'
                : '已重新核对，原有选择已清空，请重新选择';
          }
          if (!append && !unchanged) _selected.clear();
          // Only the first explicitly opened page defaults to selection. New
          // pages and refreshes never silently enlarge the reviewed selection.
          if (initial && snapshot.blockedReason.isEmpty) {
            _selected.addAll(
              snapshot.rows.where((r) => r.eligible).map((r) => r.id),
            );
          }
          if (snapshot.restarted) _error = '数据已变化，已重新加载；请重新选择规划';
          if (!unchanged) _pending = null;
          _loading = false;
        });
        _arm(snapshot.nextBoundary);
      } else {
        final page = await _repository.read(
          widget.username,
          search: _search.text,
          folder: _folder,
          cursor: more ? _page?.next : null,
        );
        if (!mounted || sequence != _sequence) return;
        _identity ??= page.identity;
        await _identity!.check();
        if (!mounted || sequence != _sequence) return;
        setState(() {
          _todos = more && !page.restarted
              ? [..._todos, ...page.rows]
              : page.rows;
          _page = page;
          _loading = false;
        });
        _arm(page.nextBoundary);
      }
    } catch (error) {
      if (!mounted || sequence != _sequence) return;
      final identityChanged =
          error is PlanAvailabilityException && error.message.contains('身份已切换');
      final preservePage =
          hadPage && !identityChanged && (more || _detail);
      setState(() {
        _morePageError = preservePage && more;
        _error = preservePage
            ? '${_message(error)}；已保留当前已加载内容和选择，可重试${more ? '加载更多' : '核对'}'
            : _message(error);
        _loading = false;
        if (!preservePage) {
          _selected.clear();
          _pending = null;
          _snapshot = null;
          _page = null;
          _items = [];
          _todos = [];
        }
      });
    }
  }

  void _arm(DateTime? boundary) {
    _boundary?.cancel();
    if (boundary == null ||
        !_foreground ||
        _opening ||
        _saved != null ||
        _pending != null) {
      return;
    }
    final delay = boundary.difference(_now);
    _boundary = Timer(
      delay.isNegative ? const Duration(milliseconds: 1) : delay,
      _refresh,
    );
  }

  Future<void> _route(Widget Function() builder) async {
    if (_opening || _working || _loading) return;
    _opening = true;
    _boundary?.cancel();
    try {
      await _identity?.check();
      if (!mounted) return;
      await Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => builder()));
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      _opening = false;
      if (mounted && _saved == null) await _load();
    }
  }

  Future<void> _viewTodo() async {
    if (_identity == null ||
        widget.todoId == null ||
        _opening ||
        _working ||
        _loading) {
      return;
    }
    _opening = true;
    _boundary?.cancel();
    try {
      await _identity!.check();
      final db = await DatabaseHelper.instance.databaseForUser(widget.username);
      final todo = await PlanTodoGuard.read(
        db,
        _identity!,
        widget.todoId!,
        requireEligible: false,
      );
      final todos = await StorageService.getTodos(widget.username);
      final groups = await StorageService.getTodoGroups(widget.username);
      await _identity!.check();
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TodoEditScreen(
            username: widget.username,
            todo: todo,
            todos: todos,
            todoGroups: groups,
            onTodosChanged: (items) async {
              await _identity!.check();
              await StorageService.saveTodos(widget.username, items);
            },
            onGroupsChanged: (items) async {
              await _identity!.check();
              await StorageService.saveTodoGroups(widget.username, items);
            },
          ),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      _opening = false;
      if (mounted) await _load();
    }
  }

  Future<void> _cancel() async {
    final snapshot = _snapshot;
    if (_working ||
        _loading ||
        snapshot == null ||
        _saved != null ||
        _selected.isEmpty) {
      return;
    }
    // Confirmation is itself busy: refreshes cannot replace its reviewed set.
    setState(() { _working = true; _confirming = true; });
    _boundary?.cancel();
    try {
      await snapshot.identity.check();
      final preview = _pending ?? snapshot.select(_selected, _now);
      if (!mounted) return;
      var responseSubmitted = false;
      final dates = preview.rows.map((r) => r['start_time'] as int).toList()
        ..sort();
      final ends = preview.rows.map((r) => r['end_time'] as int).toList()
        ..sort();
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) {
          void submit(bool value) {
            if (responseSubmitted) return;
            responseSubmitted = true;
            Navigator.pop(context, value);
          }

          return AlertDialog(
            title: Text('取消这${preview.rows.length}段规划？'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_date(dates.first)} 至 ${_date(ends.last)}\n共${preview.unionMinutes}分钟规划时段；历史投入保留。',
                  ),
                  if (preview.hasCalendarCopy)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text('手机日历副本不会随本次操作删除，需到日历同步中核对。'),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => submit(false),
                child: const Text('返回核对'),
              ),
              FilledButton(
                key: const ValueKey('cleanup-confirm'),
                onPressed: () => submit(true),
                child: const Text('确认取消'),
              ),
            ],
          );
        },
      );
      if (confirmed != true) return;
      if (mounted) setState(() => _confirming = false);
      final request = _pending ??
          PlanCleanupRequest(
            identity: preview.identity,
            todoId: preview.todoId,
            fingerprint: preview.fingerprint,
            rows: preview.rows,
            cancelledAt: _now.millisecondsSinceEpoch,
          );
      _pending = request;
      await _repository.cancel(request);
      if (!mounted) return;
      setState(() {
        _saved = request;
        _error = null;
        _selected.clear();
      });
      await _updateReminders(request);
    } catch (error) {
      if (mounted) {
        final identityChanged =
            error is PlanAvailabilityException &&
            error.message.contains('身份已切换');
        setState(() {
          _error = _message(error);
          if (identityChanged) {
            _selectionNotice = null;
            _selected.clear();
            _pending = null;
            _snapshot = null;
            _items = [];
            _morePageError = false;
          }
        });
      }
    } finally {
      if (mounted) {
        setState(() { _working = false; _confirming = false; });
        if (_saved == null && _snapshot != null) _arm(_snapshot!.nextBoundary);
      }
    }
  }

  Future<void> _updateReminders(PlanCleanupRequest request) async {
    try {
      await request.identity.check();
      await (widget.updateReminders?.call() ??
          NotificationService.removePlanReminders(
            request.ids.toSet(),
            ensureCurrent: request.identity.check,
          ));
      await request.identity.check();
      if (mounted) setState(() => _reminderError = null);
    } catch (error) {
      if (mounted) {
        setState(() => _reminderError = '规划已取消，提醒更新失败：${_message(error)}');
      }
    }
  }

  Future<void> _retryReminders() async {
    if (_working || _saved == null) return;
    setState(() => _working = true);
    await _updateReminders(_saved!);
    if (mounted) setState(() => _working = false);
  }

  String _date(int ms) =>
      DateFormat('yyyy/M/d').format(DateTime.fromMillisecondsSinceEpoch(ms));
  String _range(PlanCleanupItem item) {
    final start = DateTime.fromMillisecondsSinceEpoch(item.start),
        end = DateTime.fromMillisecondsSinceEpoch(item.end);
    final offset = start.timeZoneOffset == end.timeZoneOffset
        ? ''
        : ' · ${start.timeZoneName}→${end.timeZoneName}';
    return '${DateFormat('HH:mm').format(start)}–${DateFormat(DateUtils.isSameDay(start, end) ? 'HH:mm' : 'M/d HH:mm').format(end)}$offset';
  }

  String _reminder(PlanCleanupItem item) => item.row['reminder_minutes'] == 0
      ? '不提醒'
      : '提前${item.row['reminder_minutes']}分钟提醒';
  String _status(PlanCleanupItem item) => switch (item.row['status']) {
    0 => '待执行',
    2 => '已延后',
    4 => '已提醒',
    5 => '专注中',
    _ => '状态待核对',
  };
  Future<void> _viewItem(PlanCleanupItem item) async {
    if (_working || _inspecting) return;
    setState(() => _inspecting = true);
    try {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('规划核对'),
          content: SingleChildScrollView(
            child: Text(
              '${_date(item.start)} ${_range(item)}\n${item.minutes}分钟 · ${item.reason.isEmpty ? '可处理' : item.reason}'
              '\n提前${item.row['reminder_minutes']}分钟提醒'
              '\n累计专注参考：${item.row['actual_focus_seconds']}秒'
              '\n${item.row['remark'] ?? ''}\n以上为本页读取快照，提交前会再次核对。',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('返回'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _inspecting = false);
    }
  }

  Widget _notice(String text, {bool error = false}) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: error ? cs.errorContainer : cs.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          text,
          style: TextStyle(color: error ? cs.onErrorContainer : cs.onSurface),
        ),
      ),
    );
  }

  Widget _item(PlanCleanupItem item) {
    final enabled =
        item.eligible &&
        (_snapshot?.blockedReason.isEmpty ?? false) &&
        !_working &&
        !_loading &&
        _pending == null;
    final checked = _selected.contains(item.id);
    final checkboxLabel = [
      _date(item.start),
      _range(item),
      '${item.minutes}分钟',
      item.reason.isEmpty ? '可处理' : item.reason,
    ].join('，');
    return Card(
      semanticContainer: false,
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  key: ValueKey('cleanup-select-${item.key}'),
                  semanticLabel: checkboxLabel,
                  value: checked,
                  onChanged: enabled
                      ? (value) {
                          if (value == true && _selected.length >= 50) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('一次最多选择50段')),
                            );
                            return;
                          }
                          setState(() {
                            _selectionNotice = null;
                            value == true
                                ? _selected.add(item.id)
                                : _selected.remove(item.id);
                          });
                        }
                      : null,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _range(item),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${item.minutes}分钟 · ${_status(item)} · ${_reminder(item)}',
                      ),
                      if (item.reason.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            item.reason,
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ),
                      if ((item.row['calendar_event_id']?.toString() ?? '')
                          .isNotEmpty)
                        const Text('有手机日历副本'),
                    ],
                  ),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _working || _inspecting
                    ? null
                    : () => _viewItem(item),
                child: const Text('查看详情'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _overview() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('任务完成后，把剩余时间留给下一件事', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 16),
      TextField(
        key: const ValueKey('cleanup-search'),
        controller: _search,
        decoration: const InputDecoration(
          hintText: '搜索已完成待办',
          prefixIcon: Icon(Icons.search),
          border: OutlineInputBorder(),
        ),
        onChanged: (_) {
          _sequence++;
          _debounce?.cancel();
          setState(() {
            _loading = true;
            _error = null;
            _morePageError = false;
          });
          _debounce = Timer(const Duration(milliseconds: 250), () => _load());
        },
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        initialValue: _folder ?? '*',
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: '文件夹',
          border: OutlineInputBorder(),
        ),
        items: [
          const DropdownMenuItem(value: '*', child: Text('全部文件夹')),
          const DropdownMenuItem(value: '', child: Text('未分组')),
          if (_folder != null &&
              _folder!.isNotEmpty &&
              !(_page?.groups.any((g) => g.id == _folder) ?? false))
            DropdownMenuItem(value: _folder, child: const Text('文件夹已不存在')),
          for (final group in _page?.groups ?? <TodoGroup>[])
            DropdownMenuItem(
              value: group.id,
              child: Text(group.name, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (value) {
          setState(() => _folder = value == '*' ? null : value);
          _load();
        },
      ),
      const SizedBox(height: 12),
      if (_page != null) Text('已加载${_todos.length}／总计${_page!.total}个待办'),
      if (_page?.restarted ?? false)
        _notice('待办列表已变化，已从头重新加载，请核对结果'),
      if (!_loading && _error == null && _todos.isEmpty)
        _notice(
          _search.text.isEmpty && _folder == null ? '没有需要收尾的剩余规划' : '当前筛选下没有待办',
        ),
      for (final todo in _todos)
        Card(
          elevation: 0,
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: InkWell(
            key: ValueKey('cleanup-todo-${todo.id}'),
            onTap: _loading ? null : () => _route(
              () => PlanCleanupScreen(
                username: widget.username,
                todoId: todo.id,
                repository: _repository,
                clock: widget.clock,
                updateReminders: widget.updateReminders,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    todo.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${todo.count}段剩余 · 可处理${todo.eligible}段 · 最早${_date(todo.nextStart)}',
                  ),
                  if (todo.reason.isNotEmpty) Text(todo.reason),
                  const SizedBox(height: 6),
                  const Text('查看剩余规划 →'),
                ],
              ),
            ),
          ),
        ),
      if (_morePageError && _page != null)
        _notice(_error ?? '列表读取失败，请重试', error: true),
      if (_page?.next != null)
        TextButton(
          onPressed: _loading ? null : () => _load(more: true),
          child: const Text('加载更多待办'),
        ),
    ],
  );
  Widget _details() {
    final snapshot = _snapshot;
    if (snapshot == null) return const SizedBox.shrink();
    final children = <Widget>[
      Text(
        snapshot.todo.title,
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 6),
      Text(
        snapshot.todo.isDone ? '待办已完成 · 可处理${snapshot.eligible}段' : '待办状态已变化',
      ),
      Text('已加载${_items.length}／总计${snapshot.total}段剩余规划'),
      if (snapshot.blockedReason.isNotEmpty) _notice(snapshot.blockedReason),
      Wrap(
        spacing: 8,
        children: [
          TextButton(
            onPressed: _working || _loading ? null : _viewTodo,
            child: const Text('查看／编辑待办'),
          ),
          if (snapshot.blockedReason.contains('专注'))
            TextButton(
              onPressed: _working || _loading
                  ? null
                  : () =>
                        _route(() => PomodoroScreen(username: widget.username)),
              child: const Text('查看当前专注'),
            ),
          TextButton(
            key: const ValueKey('cleanup-select-loaded'),
            onPressed:
                _loading ||
                    _working ||
                    _pending != null ||
                    snapshot.blockedReason.isNotEmpty
                ? null
                : () => setState(() {
                    _selectionNotice = null;
                    _selected.clear();
                    _selected.addAll(
                      _items.where((r) => r.eligible).take(50).map((r) => r.id),
                    );
                  }),
            child: const Text('选中已加载可处理项（最多50段）'),
          ),
        ],
      ),
      if (_items.isEmpty) _notice('没有未结束的剩余规划'),
    ];
    String? lastDate;
    for (final item in _items) {
      final date = DateFormat('yyyy年M月d日')
          .format(DateTime.fromMillisecondsSinceEpoch(item.start));
      if (date != lastDate) {
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(date, style: Theme.of(context).textTheme.titleSmall),
          ),
        );
        lastDate = date;
      }
      children.add(_item(item));
    }
    if (_morePageError) {
      children.add(_notice(_error ?? '列表读取失败，请重试', error: true));
    }
    if (snapshot.next != null) {
      children.add(
        TextButton(
          onPressed: _loading || _working || _pending != null
              ? null
              : () => _load(more: true),
          child: const Text('加载更多规划（不自动选中）'),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Widget _success() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Icon(
        Icons.check_circle_outline,
        size: 48,
        color: Theme.of(context).colorScheme.primary,
      ),
      const SizedBox(height: 16),
      Text(
        '已取消${_saved!.rows.length}段',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 8),
      Text('应用内释放${_saved!.unionMinutes}分钟规划时段。\n实际可用以重新查找为准，历史投入保留。'),
      if (_saved!.hasCalendarCopy) ...[
        _notice('手机日历副本不会随本次操作删除，副本仍可能占用可用时段。'),
        TextButton(
          onPressed: _working
              ? null
              : () => _route(() => const CalendarSyncPage()),
          child: const Text('前往日历同步核对'),
        ),
      ],
      if (_reminderError != null) ...[
        _notice(_reminderError!, error: true),
        OutlinedButton(
          key: const ValueKey('cleanup-retry-reminders'),
          onPressed: _working ? null : _retryReminders,
          child: const Text('重试更新提醒'),
        ),
      ] else if (!_working)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text('应用提醒已更新'),
        ),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: _working ? null : () => Navigator.of(context).pop(),
        child: const Text('完成'),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final minutes = PlanCleanupRequest.unionMinutesFor(
      _items.where((r) => _selected.contains(r.id)).map((r) => r.row),
    );
    return PopScope(
      canPop: !_working,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _detail ? '剩余规划收尾' : '已完成待办的剩余规划',
            maxLines: 2,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          actions: [
            if (_saved == null)
              IconButton(
                tooltip: '重新核对',
                onPressed: _loading || _working ? null : () => _load(),
                icon: const Icon(Icons.refresh),
              ),
          ],
        ),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_loading || (_working && !_confirming)) const LinearProgressIndicator(),
                if (_error != null) ...[
                  _notice(_error!, error: true),
                  TextButton(
                    onPressed: _working ? null : () => _load(),
                    child: const Text('重新核对'),
                  ),
                ],
                if (_saved != null)
                  _success()
                else if (_detail)
                  _details()
                else
                  _overview(),
              ],
            ),
          ),
        ),
        bottomNavigationBar: !_detail || _saved != null
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('已选${_selected.length}段 · $minutes分钟'),
                      if (_selectionNotice != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          _selectionNotice!,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          key: const ValueKey('cleanup-cancel'),
                          onPressed:
                              _working ||
                                  _loading ||
                                  _selected.isEmpty ||
                                  _snapshot == null
                              ? null
                              : _cancel,
                          child: Text(
                            _pending != null
                                ? '重试本次提交'
                                : '取消选中${_selected.length}段',
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
