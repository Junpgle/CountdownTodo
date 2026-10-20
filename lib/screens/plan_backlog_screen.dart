import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../services/database_helper.dart';
import '../services/plan_backlog_repository.dart';
import '../services/plan_todo_guard.dart';
import '../services/pomodoro_service.dart';
import '../services/todo_editor_save_service.dart';
import '../storage_service.dart';
import '../widgets/plan_block_editor_sheet.dart';
import '../widgets/todo_section_widget.dart';
import 'pomodoro_screen.dart';
import 'plan_editor_drafts_screen.dart';
import 'plan_cleanup_screen.dart';

String? _planBacklogDateLocale;
final _planBacklogDateFormatters = <String, DateFormat>{};

DateFormat _planBacklogDateFormat(String pattern) {
  final locale = Intl.defaultLocale;
  if (_planBacklogDateLocale != locale) {
    _planBacklogDateLocale = locale;
    _planBacklogDateFormatters.clear();
  }
  return _planBacklogDateFormatters.putIfAbsent(
    pattern,
    () => DateFormat(pattern, locale),
  );
}

class _PlanBacklogSectionHeader {
  const _PlanBacklogSectionHeader(this.group);

  final int group;
}

class PlanBacklogScreen extends StatefulWidget {
  const PlanBacklogScreen({
    super.key,
    required this.username,
    required this.date,
    this.repository,
    this.clock,
  });
  final String username;
  final DateTime date;
  final PlanBacklogRepository? repository;
  final DateTime Function()? clock;
  @override
  State<PlanBacklogScreen> createState() => _PlanBacklogScreenState();
}

class _PlanBacklogScreenState extends State<PlanBacklogScreen>
    with WidgetsBindingObserver {
  final _search = TextEditingController();
  late DateTime _date;
  late final PlanBacklogRepository _repository;
  PlanTodoIdentity? _identity;
  PlanBacklogPage? _page;
  List<PlanBacklogRow> _rows = [];
  List<Object> _displayRows = [];
  Map<String, String> _groupNamesById = const {};
  bool _scheduled = false,
      _loading = true,
      _opening = false,
      _foreground = true,
      _normalized = false;
  String? _folder, _error;
  int _sequence = 0;
  Timer? _debounce, _boundary;
  StreamSubscription<PomodoroRunState?>? _focus;
  DateTime get _now => widget.clock?.call() ?? DateTime.now();
  @override
  void initState() {
    super.initState();
    _repository =
        widget.repository ?? PlanBacklogRepository(clock: widget.clock);
    final today = DateUtils.dateOnly(_now);
    _date = DateUtils.dateOnly(widget.date);
    if (_date.isBefore(today)) {
      _date = today;
      _normalized = true;
    }
    WidgetsBinding.instance.addObserver(this);
    StorageService.scopedDataRefreshNotifier.addListener(_refresh);
    _focus = PomodoroService.onRunStateChanged.listen((_) => _refresh());
    _load();
  }

  void _refresh() {
    if (mounted && _foreground && !_opening) unawaited(_load());
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

  @override
  void dispose() {
    _sequence++;
    _debounce?.cancel();
    _boundary?.cancel();
    _focus?.cancel();
    StorageService.scopedDataRefreshNotifier.removeListener(_refresh);
    WidgetsBinding.instance.removeObserver(this);
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    final sequence = ++_sequence;
    _boundary?.cancel();
    if (_date.isBefore(DateUtils.dateOnly(_now))) {
      _date = DateUtils.dateOnly(_now);
      _normalized = true;
    }
    setState(() {
      _loading = true;
      _error = null;
      if (!more) {
        _rows = [];
        _displayRows = [];
      }
    });
    try {
      await _identity?.check();
      final page = await _repository.read(
        widget.username,
        _date,
        scheduled: _scheduled,
        search: _search.text,
        folder: _folder,
        cursor: more ? _page?.next : null,
      );
      if (!mounted || sequence != _sequence || !_foreground) return;
      await _identity?.check();
      if (!mounted || sequence != _sequence) return;
      final nextRows = more && !page.restarted
          ? [..._rows, ...page.rows]
          : page.rows;
      final displayRows = _buildDisplayRows(nextRows);
      final groupNamesById = {
        for (final group in page.groups) group.id: group.name,
      };
      _identity ??= page.identity;
      setState(() {
        _rows = nextRows;
        _displayRows = displayRows;
        _page = page;
        _groupNamesById = groupNamesById;
        _loading = false;
      });
      final delay = page.nextBoundary.difference(_now);
      if (!_opening) {
        _boundary = Timer(
          delay.isNegative ? const Duration(milliseconds: 1) : delay,
          _refresh,
        );
      }
    } catch (e) {
      if (mounted && sequence == _sequence) {
        setState(() {
          _error = _message(e);
          _loading = false;
          _page = null;
          _rows = [];
          _displayRows = [];
        });
      }
    }
  }

  String _message(Object e) => e is StateError
      ? e.message.toString()
      : e.toString().replaceFirst('PlanAvailabilityException: ', '');

  bool _cannotPlanOnTargetDay(TodoItem todo) {
    if (todo.dueDate != null && todo.dueDate!.isBefore(_date)) return true;
    final deadline = todo.effectiveDueAt;
    return deadline != null && deadline.isBefore(_now);
  }

  Future<void> _pickDate() async {
    final today = DateUtils.dateOnly(_now);
    final chosen = await showDatePicker(
      context: context,
      initialDate: _date.isBefore(today) ? today : _date,
      firstDate: today,
      lastDate: DateTime(today.year + 10),
    );
    if (chosen != null && mounted) {
      setState(() {
        _date = chosen;
        _normalized = false;
      });
      await _load();
    }
  }

  Future<void> _view(PlanBacklogRow row) async {
    if (_opening || _identity == null) return;
    _opening = true;
    _boundary?.cancel();
    try {
      await _identity!.check();
      final db = await DatabaseHelper.instance.databaseForUser(widget.username);
      final todo = await PlanTodoGuard.read(
        db,
        _identity!,
        row.id,
        requireEligible: false,
      );
      final todos = await StorageService.getTodos(widget.username);
      final groups = await StorageService.getTodoGroups(widget.username);
      await _identity!.check();
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TodoEditScreen(
            todo: todo,
            todos: todos,
            todoGroups: groups,
            username: widget.username,
            onTodosChanged: (items) =>
                StorageService.saveTodos(widget.username, items),
            onEditorSave:
                (items, baselines, {expectedSeriesMembership}) =>
                    TodoEditorSaveService.save(
              username: widget.username,
              changedTodos: items,
              baselines: baselines,
              expectedSeriesMembership: expectedSeriesMembership,
            ),
            onEditorGroupsSave: (items, baselines) =>
                TodoEditorSaveService.saveGroups(
                  username: widget.username,
                  changedGroups: items,
                  baselines: baselines,
                ),
            onGroupsChanged: (items) =>
                StorageService.saveTodoGroups(widget.username, items),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_message(e))));
      }
    } finally {
      _opening = false;
      if (mounted) await _load();
    }
  }

  Future<void> _arrange(PlanBacklogRow row) async {
    if (_opening || _identity == null) return;
    _opening = true;
    _boundary?.cancel();
    try {
      final (todo, saveContext) = await _repository.prepare(_identity!, row.id);
      if (todo.dueDate != null && todo.dueDate!.isBefore(_date)) {
        throw StateError('截止早于目标日期，请先查看／编辑待办');
      }
      if (_cannotPlanOnTargetDay(todo)) {
        throw StateError('待办已截止，请先查看／编辑待办');
      }
      if (_date.isBefore(DateUtils.dateOnly(_now))) {
        throw StateError('目标日期已过去，请重新选择日期');
      }
      if (!mounted) return;
      var saved = false;
      await showPlanBlockEditorPage<void>(
        context: context,
        builder: (_) => PlanBlockEditorSheet(
          username: widget.username,
          todos: [todo],
          todoGroups: _page?.groups ?? [],
          initialTodoId: todo.id,
          startTime: DateTime(_date.year, _date.month, _date.day, 9),
          endTime: DateTime(_date.year, _date.month, _date.day, 9, 30),
          autoRecommendTime: true,
          fullPage: true,
          clock: widget.clock,
          backlogContext: saveContext,
          draftOrigin: 'backlog',
          onManageDrafts: () => openPlanEditorDrafts(
            context,
            widget.username,
            onSaved: () => saved = true,
          ),
          onViewExisting: () => _viewExistingDuringDraft(row),
          onSaved: () => saved = true,
        ),
      );
      if (mounted && saved) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('规划已保存，可在“已有安排”查看')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_message(e))));
      }
    } finally {
      _opening = false;
      if (mounted) await _load();
    }
  }

  Future<void> _viewExistingDuringDraft(PlanBacklogRow row) async {
    // Keep the draft route on the stack; returning from details preserves it.
    _opening = false;
    await _view(row);
    _opening = true;
    _boundary?.cancel();
  }

  Future<void> _viewFocus(PlanBacklogRow row) async {
    if (_opening || _identity == null) return;
    _opening = true;
    _boundary?.cancel();
    try {
      await _identity!.check();
      final db = await DatabaseHelper.instance.databaseForUser(widget.username);
      if (!(await PlanTodoGuard.focusIds(db, _identity!)).contains(row.id)) {
        throw StateError('专注状态已变化，请刷新清单');
      }
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PomodoroScreen(username: widget.username),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_message(error))));
      }
    } finally {
      _opening = false;
      if (mounted) await _load();
    }
  }

  String _heading(int group) => switch (group) {
    0 => '截止早于 ${_planBacklogDateFormat('M月d日').format(_date)}',
    1 => '${_planBacklogDateFormat('M月d日').format(_date)} 到期',
    2 => '之后到期',
    _ => '未设截止',
  };

  List<Object> _buildDisplayRows(List<PlanBacklogRow> rows) {
    final displayRows = <Object>[];
    for (var index = 0; index < rows.length; index++) {
      final row = rows[index];
      if (index == 0 || rows[index - 1].sortGroup != row.sortGroup) {
        displayRows.add(_PlanBacklogSectionHeader(row.sortGroup));
      }
      displayRows.add(row);
    }
    return displayRows;
  }

  String _details(PlanBacklogRow row) {
    if (row.needsReview) {
      return '安排需检查 · 请查看待办处理';
    }
    if (row.focusing) {
      return row.paused ? '已暂停 · 查看当前专注' : '正在专注 · 查看当前专注';
    }
    if (row.legacy) {
      final start = _planBacklogDateFormat('M/d HH:mm')
          .format(row.todo.effectiveStartTime);
      return '旧式时间安排 · $start';
    }
    if (row.planCount > 0) {
      final dateTimeFormat = _planBacklogDateFormat('M/d HH:mm');
      final start = dateTimeFormat.format(
        DateTime.fromMillisecondsSinceEpoch(row.nextStart!),
      );
      final end = dateTimeFormat.format(
        DateTime.fromMillisecondsSinceEpoch(row.nextEnd!),
      );
      final additionalPlanText = row.planCount > 1
          ? ' · 另有 ${row.planCount - 1} 项安排'
          : '';
      return '$start—$end$additionalPlanText';
    }
    final due = row.todo.dueDate;
    if (due == null) return '选择合适的时间开始';
    if (due.isBefore(_date)) return '截止早于目标日期 · 请先查看待办';
    if (_cannotPlanOnTargetDay(row.todo)) return '已截止 · 请先查看待办';
    final duePattern = row.todo.isDateOnly ? 'M月d日' : 'M月d日 HH:mm';
    final dueText = _planBacklogDateFormat(duePattern).format(due);
    return '$dueText 前完成';
  }

  Widget _row(PlanBacklogRow row) {
    final cs = Theme.of(context).colorScheme;
    final expired = _cannotPlanOnTargetDay(row.todo);
    final group = row.todo.groupId == null
        ? '未分组'
        : _groupNamesById[row.todo.groupId] ?? '未分组';
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(row.todo.title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        Text(
          '$group · ${_details(row)}',
          style: TextStyle(
            color: row.needsReview || expired ? cs.error : cs.onSurfaceVariant,
          ),
        ),
      ],
    );
    final buttons = <Widget>[
      if (row.needsReview)
        OutlinedButton(onPressed: () => _view(row), child: const Text('核对待办'))
      else if (row.focusing)
        FilledButton.tonal(
          onPressed: () => _viewFocus(row),
          child: const Text('查看专注'),
        )
      else if (row.arranged || expired)
        OutlinedButton(
          onPressed: () => _view(row),
          child: Text(row.arranged ? '查看安排' : '查看／编辑待办'),
        )
      else
        FilledButton.tonal(
          onPressed: () => _arrange(row),
          child: const Text('安排'),
        ),
      if (row.arranged && !row.needsReview && !row.focusing && !expired)
        TextButton(onPressed: () => _arrange(row), child: const Text('追加规划')),
    ];
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      color: cs.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, c) {
            final compact =
                c.maxWidth >= 600 ||
                (c.maxWidth >= 300 &&
                    MediaQuery.textScalerOf(context).scale(14) <= 20);
            if (compact) {
              return Row(
                children: [
                  Expanded(child: info),
                  const SizedBox(width: 12),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: buttons,
                  ),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                info,
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 4, children: buttons),
              ],
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final groups = _page?.groups ?? const <TodoGroup>[];
    final theme = Theme.of(context);
    final headerChildren = <Widget>[
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          Text('把未安排的事，放进合适的时间', style: theme.textTheme.titleMedium),
          OutlinedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_today_rounded, size: 18),
            label: Text('目标：${_planBacklogDateFormat('M月d日').format(_date)}'),
          ),
        ],
      ),
      if (_normalized)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('原规划日期已过去，目标日期已切换到今天'),
        ),
      const SizedBox(height: 16),
      TextField(
        controller: _search,
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.search_rounded),
          hintText: '搜索待办标题',
          border: OutlineInputBorder(),
        ),
        onChanged: (_) {
          _debounce?.cancel();
          _sequence++;
          _debounce = Timer(const Duration(milliseconds: 250), () => _load());
        },
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 12,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('待安排')),
              ButtonSegment(value: true, label: Text('已有安排')),
            ],
            selected: {_scheduled},
            onSelectionChanged: (value) {
              setState(() => _scheduled = value.single);
              _load();
            },
          ),
          PopupMenuButton<String>(
            tooltip: '筛选文件夹',
            initialValue: _folder ?? '__all',
            onSelected: (value) {
              setState(() => _folder = value == '__all' ? null : value);
              _load();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: '__all', child: Text('全部文件夹')),
              const PopupMenuItem(value: '', child: Text('未分组')),
              for (final group in groups)
                PopupMenuItem(value: group.id, child: Text(group.name)),
            ],
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Text(
                '文件夹：${_folder == null ? '全部' : groups.where((g) => g.id == _folder).firstOrNull?.name ?? '未分组'} ▾',
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      if (_error != null)
        Column(
          children: [
            Text('清单读取失败：$_error'),
            TextButton(onPressed: () => _load(), child: const Text('重试')),
          ],
        )
      else ...[
        if (_page != null && (!_loading || _rows.isNotEmpty))
          Text(
            '${_scheduled ? '已有安排' : '待安排'} ${_page!.total} 项',
            style: theme.textTheme.labelLarge,
          ),
        if (!_loading && _rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Column(
              children: [
                const Icon(Icons.event_available_rounded, size: 40),
                const SizedBox(height: 12),
                Text(
                  _search.text.trim().isNotEmpty || _folder != null
                      ? '没有符合筛选条件的待办'
                      : _scheduled
                      ? '还没有有效安排'
                      : '目前没有待安排的任务',
                ),
                const SizedBox(height: 8),
                const Text('完成、删除的待办不会出现在这里', textAlign: TextAlign.center),
              ],
            ),
          ),
      ],
    ];
    final hasFooter = _error == null && (_loading || _page?.next != null);
    return Scaffold(
      appBar: AppBar(
        title: const Text('待规划'),
        actions: [
          PopupMenuButton<String>(
            tooltip: '更多',
            onSelected: (_) async {
              if (_opening) return;
              final navigator = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(context);
              _opening = true;
              _boundary?.cancel();
              try {
                await _identity?.check();
                if (!mounted) return;
                await navigator.push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        PlanCleanupScreen(username: widget.username),
                  ),
                );
              } catch (error) {
                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(content: Text(_message(error))),
                  );
                }
              } finally {
                _opening = false;
                if (mounted) await _load();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'cleanup', child: Text('已完成待办的剩余规划')),
            ],
          ),
          IconButton(
            tooltip: '刷新清单',
            onPressed: _loading ? null : () => _load(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            itemCount:
                headerChildren.length +
                (_error == null ? _displayRows.length : 0) +
                (hasFooter ? 1 : 0),
            itemBuilder: (context, index) {
              if (index < headerChildren.length) return headerChildren[index];
              final rowIndex = index - headerChildren.length;
              if (_error == null && rowIndex < _displayRows.length) {
                final row = _displayRows[rowIndex];
                if (row is _PlanBacklogSectionHeader) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      _heading(row.group),
                      style: theme.textTheme.titleSmall,
                    ),
                  );
                }
                return _row(row as PlanBacklogRow);
              }
              if (_loading) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  ),
                );
              }
              return TextButton(
                onPressed: () => _load(more: true),
                child: const Text('加载更多'),
              );
            },
          ),
        ),
      ),
    );
  }
}
