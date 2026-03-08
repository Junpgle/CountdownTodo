import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models.dart';
import '../storage_service.dart';
import '../services/pomodoro_service.dart';
import '../services/notification_service.dart';

// ══════════════════════════════════════════════════════════════
// 动态隐藏的 AppBar 包装器

// ══════════════════════════════════════════════════════════════
// 番茄钟主页（TabBar: 专注工作台 + 统计看板）
// ══════════════════════════════════════════════════════════════
class PomodoroScreen extends StatefulWidget {
  final String username;
  /// 0 = 工作台（默认），1 = 统计看板
  final int initialTab;
  const PomodoroScreen({super.key, required this.username, this.initialTab = 0});

  @override
  State<PomodoroScreen> createState() => _PomodoroScreenState();
}

class _PomodoroScreenState extends State<PomodoroScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  PomodoroPhase _currentPhase = PomodoroPhase.idle;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
        length: 2, vsync: this, initialIndex: widget.initialTab);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isFocusing = _currentPhase == PomodoroPhase.focusing;

    return Scaffold(
      body: SafeArea(
        bottom: false, // 底部由内部自己处理
        child: Column(
          children: [
            // ── 顶部导航栏（专注时只留返回箭头，非专注时显示完整）──
            if (!isFocusing)
              Container(
                height: kToolbarHeight,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    if (Navigator.canPop(context))
                      IconButton(
                        icon: const Icon(Icons.arrow_back),
                        onPressed: () => Navigator.pop(context),
                      ),
                    const Expanded(
                      child: Center(
                        child: Text('🍅 番茄钟',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    // 右侧占位，保持标题居中
                    if (Navigator.canPop(context))
                      const SizedBox(width: 48),
                  ],
                ),
              ),
            // ── 主内容区 ──
            Expanded(
              child: TabBarView(
                physics: const NeverScrollableScrollPhysics(),
                controller: _tabController,
                children: [
                  _PomodoroWorkbench(
                    username: widget.username,
                    onPhaseChanged: (phase) {
                      if (mounted && _currentPhase != phase) {
                        setState(() => _currentPhase = phase);
                      }
                    },
                  ),
                  _PomodoroStats(username: widget.username),
                ],
              ),
            ),
            // ── 底部 Tab 导航（专注时隐藏）──
            if (!isFocusing)
              SafeArea(
                top: false,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: Theme.of(context)
                            .colorScheme
                            .outlineVariant
                            .withValues(alpha: 0.5),
                        width: 1,
                      ),
                    ),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    indicatorSize: TabBarIndicatorSize.label,
                    dividerColor: Colors.transparent,
                    tabs: const [
                      Tab(
                        icon: Icon(Icons.timer_outlined),
                        text: '工作台',
                        iconMargin: EdgeInsets.only(bottom: 2),
                      ),
                      Tab(
                        icon: Icon(Icons.bar_chart_rounded),
                        text: '统计看板',
                        iconMargin: EdgeInsets.only(bottom: 2),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// 专注工作台
// ══════════════════════════════════════════════════════════════
class _PomodoroWorkbench extends StatefulWidget {
  final String username;
  final ValueChanged<PomodoroPhase> onPhaseChanged;

  const _PomodoroWorkbench({
    required this.username,
    required this.onPhaseChanged,
  });

  @override
  State<_PomodoroWorkbench> createState() => _PomodoroWorkbenchState();
}

class _PomodoroWorkbenchState extends State<_PomodoroWorkbench>
    with WidgetsBindingObserver {
  // ── 设置 ──
  PomodoroSettings _settings = PomodoroSettings();

  // ── 运行状态 ──
  PomodoroPhase _phase = PomodoroPhase.idle;
  int _targetEndMs = 0;    // 本阶段绝对结束时间戳
  int _remainingSeconds = 0;
  int _currentCycle = 1;
  int _sessionStartMs = 0; // 当前专注开始时间戳

  // ── 任务绑定 ──
  TodoItem? _boundTodo;
  List<PomodoroTag> _allTags = [];
  List<String> _selectedTagUuids = [];

  // ── Timer ──
  Timer? _ticker;

  // ── 省电：锁屏时降低通知刷新频率，每秒 +1，达到阈值时才推一次通知 ──
  int _notifyTickCount = 0;

  // ── Todos（可选绑定） ──
  List<TodoItem> _todos = [];
  String _deviceId = '';

  static const _keyBoundTodoUuid  = 'pomodoro_idle_bound_todo_uuid';
  static const _keyBoundTodoTitle = 'pomodoro_idle_bound_todo_title'; // 兜底标题
  static const _keySelectedTagUuids = 'pomodoro_idle_selected_tag_uuids'; // 标签持久化

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _notifyTickCount = 0;
        _recoverFromBackground();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        break;
      case AppLifecycleState.detached:
        break;
    }
  }

  Future<void> _init() async {
    _settings = await PomodoroService.getSettings();
    _allTags = await PomodoroService.getTags();
    _deviceId = await StorageService.getDeviceId();
    _todos = (await StorageService.getTodos(widget.username))
        .where((t) => !t.isDeleted && !t.isDone)
        .toList();

    // 尝试恢复运行状态
    final saved = await PomodoroService.loadRunState();
    if (saved != null && saved.phase != PomodoroPhase.idle) {
      await _recoverState(saved);
    } else {
      // 空闲状态：恢复用户上次选择的绑定任务 + 标签
      final prefs = await SharedPreferences.getInstance();
      final savedUuid    = prefs.getString(_keyBoundTodoUuid);
      final savedTitle   = prefs.getString(_keyBoundTodoTitle);
      final savedTagsRaw = prefs.getString(_keySelectedTagUuids);

      // 直接恢复标签 uuid 列表，不做过滤（标签被删只影响显示，不影响持久化）
      final restoredTagUuids = savedTagsRaw != null && savedTagsRaw.isNotEmpty
          ? savedTagsRaw.split(',').where((s) => s.isNotEmpty).toList()
          : <String>[];

      TodoItem? restoredTodo;
      if (savedUuid != null && savedUuid.isNotEmpty) {
        restoredTodo = _todos.cast<TodoItem?>().firstWhere(
          (t) => t?.id == savedUuid,
          orElse: () => null,
        );
        // 任务已完成/被删，但 title 还在 → 构造占位，让界面仍能显示绑定
        if (restoredTodo == null && savedTitle != null && savedTitle.isNotEmpty) {
          restoredTodo = TodoItem(
            id: savedUuid,
            title: savedTitle,
            isDone: false,
            createdAt: 0,
          );
        }
      }
      if (mounted) {
        setState(() {
          _remainingSeconds = _settings.focusMinutes * 60;
          _boundTodo = restoredTodo;
          _selectedTagUuids = restoredTagUuids;
        });
      }
    }
  }

  /// 持久化或清除空闲绑定任务（uuid + title + tagUuids 一并保存）
  Future<void> _persistIdleBoundTodo(TodoItem? todo, {List<String>? tagUuids}) async {
    final prefs = await SharedPreferences.getInstance();
    if (todo != null) {
      await prefs.setString(_keyBoundTodoUuid,  todo.id);
      await prefs.setString(_keyBoundTodoTitle, todo.title);
    } else {
      await prefs.remove(_keyBoundTodoUuid);
      await prefs.remove(_keyBoundTodoTitle);
    }
    // 标签无论任务是否存在都单独保存（自由专注也可以有标签）
    final tags = tagUuids ?? _selectedTagUuids;
    if (tags.isNotEmpty) {
      await prefs.setString(_keySelectedTagUuids, tags.join(','));
    } else {
      await prefs.remove(_keySelectedTagUuids);
    }
  }

  // ── 从持久化状态恢复（防误杀核心逻辑）──────────────
  Future<void> _recoverState(PomodoroRunState saved) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final remaining = ((saved.targetEndMs - now) / 1000).ceil();

    if (saved.phase == PomodoroPhase.focusing || saved.phase == PomodoroPhase.breaking) {
      if (remaining <= 0) {
        if (saved.phase == PomodoroPhase.focusing) {
          await _handleFocusEndFromBackground(saved);
        } else {
          await _handleBreakEndFromBackground(saved);
        }
      } else {
        // 先从 _todos 里精确匹配；找不到时用 savedTitle 兜底，避免绑定任务丢失
        TodoItem? boundTodo;
        if (saved.todoUuid != null) {
          boundTodo = _todos.cast<TodoItem?>().firstWhere(
            (t) => t?.id == saved.todoUuid,
            orElse: () => null,
          );
          // 任务已完成或被删除，但标题还在 RunState 里 → 构造只读占位，让界面能显示
          if (boundTodo == null && saved.todoTitle != null && saved.todoTitle!.isNotEmpty) {
            boundTodo = TodoItem(
              id: saved.todoUuid!,
              title: saved.todoTitle!,
              isDone: false,
              createdAt: 0,
            );
          }
        }
        if (mounted) {
          setState(() {
            _phase = saved.phase;
            _targetEndMs = saved.targetEndMs;
            _remainingSeconds = remaining;
            _currentCycle = saved.currentCycle;
            _settings.focusMinutes = saved.focusSeconds ~/ 60;
            _settings.breakMinutes = saved.breakSeconds ~/ 60;
            _settings.cycles = saved.totalCycles;
            _boundTodo = boundTodo;
            _selectedTagUuids = saved.tagUuids;
            _sessionStartMs = saved.sessionStartMs;
          });
          widget.onPhaseChanged(_phase);
          _pushPomodoroNotification(overrideRemaining: remaining); // 立即上岛
          _startTicker();
        }
      }
    }
  }

  Future<void> _recoverFromBackground() async {
    if (_phase == PomodoroPhase.focusing || _phase == PomodoroPhase.breaking) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final remaining = ((_targetEndMs - now) / 1000).ceil();
      if (remaining <= 0) {
        _ticker?.cancel();
        if (_phase == PomodoroPhase.focusing) {
          await _onFocusEnd();
        } else {
          await _onBreakEnd();
        }
      } else {
        setState(() => _remainingSeconds = remaining);
      }
    }
  }

  Future<void> _handleFocusEndFromBackground(PomodoroRunState saved) async {
    TodoItem? boundTodo;
    if (saved.todoUuid != null) {
      boundTodo = _todos.cast<TodoItem?>().firstWhere(
        (t) => t?.id == saved.todoUuid,
        orElse: () => null,
      );
      if (boundTodo == null && saved.todoTitle != null && saved.todoTitle!.isNotEmpty) {
        boundTodo = TodoItem(
          id: saved.todoUuid!,
          title: saved.todoTitle!,
          isDone: false,
          createdAt: 0,
        );
      }
    }
    setState(() {
      _phase = PomodoroPhase.idle;
      _currentCycle = saved.currentCycle;
      _boundTodo = boundTodo;
      _selectedTagUuids = saved.tagUuids;
      _remainingSeconds = _settings.focusMinutes * 60;
    });
    widget.onPhaseChanged(_phase);
    await PomodoroService.clearRunState();
    _askCompletionAndRecord(
      durationSeconds: saved.focusSeconds,
      startMs: saved.sessionStartMs,
      endMs: saved.targetEndMs,
    );
  }

  Future<void> _handleBreakEndFromBackground(PomodoroRunState saved) async {
    // 从 saved 中恢复 boundTodo（与 _recoverState 相同的兜底逻辑）
    TodoItem? boundTodo;
    if (saved.todoUuid != null) {
      boundTodo = _todos.cast<TodoItem?>().firstWhere(
        (t) => t?.id == saved.todoUuid,
        orElse: () => null,
      );
      if (boundTodo == null && saved.todoTitle != null && saved.todoTitle!.isNotEmpty) {
        boundTodo = TodoItem(
          id: saved.todoUuid!,
          title: saved.todoTitle!,
          isDone: false,
          createdAt: 0,
        );
      }
    }
    // 先写 idle 持久化，再清 RunState
    await _persistIdleBoundTodo(boundTodo, tagUuids: saved.tagUuids);
    await PomodoroService.clearRunState();
    if (mounted) {
      setState(() {
        _phase = PomodoroPhase.idle;
        _boundTodo = boundTodo;
        _selectedTagUuids = saved.tagUuids;
        _currentCycle = saved.currentCycle + 1;
        _remainingSeconds = saved.focusSeconds;
      });
      widget.onPhaseChanged(_phase);
    }
  }

  // ── 立即推送一次番茄钟通知（上岛）────────────────────────────
  void _pushPomodoroNotification({int? overrideRemaining, String alertKey = ''}) {
    final remaining = overrideRemaining ?? _remainingSeconds;
    final tagNames = _allTags
        .where((t) => _selectedTagUuids.contains(t.uuid))
        .map((t) => t.name)
        .toList();
    NotificationService.updatePomodoroNotification(
      remainingSeconds: remaining,
      phase: _phase == PomodoroPhase.breaking ? 'breaking' : 'focusing',
      todoTitle: _boundTodo?.title,
      currentCycle: _currentCycle,
      totalCycles: _settings.cycles,
      tagNames: tagNames,
      alertKey: alertKey,
    );
  }

  // ── Ticker ──────────────────────────────────────────────────
  void _startTicker() {
    _ticker?.cancel();
    _notifyTickCount = 0;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final remaining = ((_targetEndMs - now) / 1000).ceil();
      if (remaining <= 0) {
        _ticker?.cancel();
        NotificationService.cancelNotification();
        if (_phase == PomodoroPhase.focusing) {
          await _onFocusEnd();
        } else {
          await _onBreakEnd();
        }
      } else {
        if (mounted) {
          setState(() => _remainingSeconds = remaining);

          // ── 省电：动态通知刷新间隔 ────────────────────────────
          // 最后60秒：每秒刷（倒计时精确显示 MM:SS）
          // 超过1分钟：每60秒刷一次（通知只显示分钟数，分钟数不变就不推）
          _notifyTickCount++;
          final int interval = remaining <= 60 ? 1 : 60;
          if (_notifyTickCount >= interval) {
            _notifyTickCount = 0;
            _pushPomodoroNotification(overrideRemaining: remaining);
          }
        }
      }
    });
  }

  // ── 开始专注 ─────────────────────────────────────────────────
  Future<void> _startFocus() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final durationMs = _settings.focusMinutes * 60 * 1000;
    final end = now + durationMs;

    setState(() {
      _phase = PomodoroPhase.focusing;
      _targetEndMs = end;
      _remainingSeconds = _settings.focusMinutes * 60;
      _sessionStartMs = now;
    });
    widget.onPhaseChanged(_phase);

    // ① 先写 RunState（防止被杀后数据丢失）
    await PomodoroService.saveRunState(PomodoroRunState(
      phase: PomodoroPhase.focusing,
      targetEndMs: end,
      currentCycle: _currentCycle,
      totalCycles: _settings.cycles,
      focusSeconds: _settings.focusMinutes * 60,
      breakSeconds: _settings.breakMinutes * 60,
      todoUuid: _boundTodo?.id,
      todoTitle: _boundTodo?.title,
      tagUuids: _selectedTagUuids,
      sessionStartMs: now,
      plannedFocusSeconds: _settings.focusMinutes * 60,
    ));
    // ② RunState 已安全写入，再清除 idle 持久化（避免重进时读到旧 idle 数据）
    await _persistIdleBoundTodo(null);

    _pushPomodoroNotification(alertKey: 'pomo_start_$end');
    _startTicker();
  }

  // ── 中途切换任务 ─────────────────────────────────────────────
  Future<void> _switchTask(TodoItem newTodo) async {
    if (_phase != PomodoroPhase.focusing) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final actualSeconds = ((now - _sessionStartMs) / 1000).round();

    // 记录上一段任务的时长（状态 switched）
    if (actualSeconds > 5) {
      final record = PomodoroRecord(
        todoUuid: _boundTodo?.id,
        todoTitle: _boundTodo?.title,
        tagUuids: List.from(_selectedTagUuids),
        startTime: _sessionStartMs,
        endTime: now,
        plannedDuration: _settings.focusMinutes * 60,
        actualDuration: actualSeconds,
        status: PomodoroRecordStatus.switched,
        deviceId: _deviceId.isNotEmpty ? _deviceId : null,
      );
      await PomodoroService.addRecord(record);
    }

    // ⚠️ 不重置 _targetEndMs，倒计时继续，仅切换绑定任务和片段起点
    setState(() {
      _boundTodo = newTodo;
      _sessionStartMs = now;
    });

    await PomodoroService.saveRunState(PomodoroRunState(
      phase: PomodoroPhase.focusing,
      targetEndMs: _targetEndMs,   // 保持原有结束时间
      currentCycle: _currentCycle,
      totalCycles: _settings.cycles,
      focusSeconds: _settings.focusMinutes * 60,
      breakSeconds: _settings.breakMinutes * 60,
      todoUuid: newTodo.id,
      todoTitle: newTodo.title,
      tagUuids: _selectedTagUuids,
      sessionStartMs: now,
      plannedFocusSeconds: _settings.focusMinutes * 60,
    ));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已切换至: ${newTodo.title}'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ── 提前完成本轮专注 ────────────────────────────────────────
  Future<void> _finishEarly() async {
    _ticker?.cancel();
    NotificationService.cancelNotification();
    final now = DateTime.now().millisecondsSinceEpoch;
    final actualSeconds = ((now - _sessionStartMs) / 1000).round();
    NotificationService.sendPomodoroEndAlert(
      alertKey: 'pomo_end_${_targetEndMs}',
      todoTitle: _boundTodo?.title,
      isBreak: false,
    );
    setState(() => _phase = PomodoroPhase.idle);
    widget.onPhaseChanged(_phase);
    // 先写 idle 持久化，再清 RunState
    await _persistIdleBoundTodo(_boundTodo);
    await PomodoroService.clearRunState();
    await _askCompletionAndRecord(
      durationSeconds: actualSeconds,
      startMs: _sessionStartMs,
      endMs: now,
    );
  }

  // ── 专注结束 ─────────────────────────────────────────────────
  Future<void> _onFocusEnd() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    NotificationService.sendPomodoroEndAlert(
      alertKey: 'pomo_end_${_targetEndMs}',
      todoTitle: _boundTodo?.title,
      isBreak: false,
    );
    setState(() => _phase = PomodoroPhase.idle);
    widget.onPhaseChanged(_phase);
    // 先 await 写 idle 持久化，再清 RunState
    await _persistIdleBoundTodo(_boundTodo);
    PomodoroService.clearRunState();
    _askCompletionAndRecord(
      durationSeconds: _settings.focusMinutes * 60,
      startMs: _sessionStartMs,
      endMs: now,
    );
  }

  Future<void> _askCompletionAndRecord({
    required int durationSeconds,
    required int startMs,
    required int endMs,
  }) async {
    if (!mounted) return;
    final completed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('🍅 专注完成！'),
        content: Text(
          _boundTodo != null
              ? '"${_boundTodo!.title}" 是否已完成？'
              : '专注时段已结束，该任务是否已完成？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('未完成'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('已完成 ✓'),
          ),
        ],
      ),
    );

    final record = PomodoroRecord(
      todoUuid: _boundTodo?.id,
      todoTitle: _boundTodo?.title,
      tagUuids: List.from(_selectedTagUuids),
      startTime: startMs,
      endTime: endMs,
      plannedDuration: _settings.focusMinutes * 60,
      actualDuration: durationSeconds,
      status: (completed ?? false)
          ? PomodoroRecordStatus.completed
          : PomodoroRecordStatus.interrupted,
      deviceId: _deviceId.isNotEmpty ? _deviceId : null,
    );
    await PomodoroService.addRecord(record);

    if (completed == true && _boundTodo != null) {
      _boundTodo!.isDone = true;
      _boundTodo!.markAsChanged();
      final allTodos = await StorageService.getTodos(widget.username);
      final idx = allTodos.indexWhere((t) => t.id == _boundTodo!.id);
      if (idx != -1) allTodos[idx] = _boundTodo!;
      await StorageService.saveTodos(widget.username, allTodos);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ "${_boundTodo!.title}" 已标记完成'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }

    if (_currentCycle < _settings.cycles) {
      _startBreak();
    } else {
      setState(() {
        _phase = PomodoroPhase.finished;
        _currentCycle = 1;
        _remainingSeconds = _settings.focusMinutes * 60;
      });
      widget.onPhaseChanged(_phase);
      // 全部轮次完成，写回 idle 持久化，下次进入仍能恢复绑定
      await _persistIdleBoundTodo(_boundTodo);
    }
  }

  // ── 开始休息 ─────────────────────────────────────────────────
  Future<void> _startBreak() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final end = now + _settings.breakMinutes * 60 * 1000;
    setState(() {
      _phase = PomodoroPhase.breaking;
      _targetEndMs = end;
      _remainingSeconds = _settings.breakMinutes * 60;
    });
    widget.onPhaseChanged(_phase);

    await PomodoroService.saveRunState(PomodoroRunState(
      phase: PomodoroPhase.breaking,
      targetEndMs: end,
      currentCycle: _currentCycle,
      totalCycles: _settings.cycles,
      focusSeconds: _settings.focusMinutes * 60,
      breakSeconds: _settings.breakMinutes * 60,
      todoUuid: _boundTodo?.id,
      todoTitle: _boundTodo?.title,
      tagUuids: _selectedTagUuids,
      sessionStartMs: now,
      plannedFocusSeconds: _settings.focusMinutes * 60,
    ));
    _pushPomodoroNotification(alertKey: 'pomo_start_$end'); // 立即上岛
    _startTicker();
  }

  // ── 休息结束 ─────────────────────────────────────────────────
  Future<void> _onBreakEnd() async {
    NotificationService.sendPomodoroEndAlert(
      alertKey: 'pomo_end_${_targetEndMs}',
      todoTitle: _boundTodo?.title,
      isBreak: true,
    );
    setState(() {
      _phase = PomodoroPhase.idle;
      _currentCycle += 1;
      _remainingSeconds = _settings.focusMinutes * 60;
    });
    widget.onPhaseChanged(_phase);
    PomodoroService.clearRunState();
    // await 确保写入完成
    await _persistIdleBoundTodo(_boundTodo);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('☕ 休息结束，准备开始下一轮！'),
          duration: Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ── 放弃当前专注 ─────────────────────────────────────────────
  Future<void> _abandonFocus() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('放弃本次专注？'),
        content: const Text('本次专注记录将被丢弃。'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('继续专注')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade400),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('放弃'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      _ticker?.cancel();
      NotificationService.cancelNotification();
      setState(() {
        _phase = PomodoroPhase.idle;
        _currentCycle = 1;
        _remainingSeconds = _settings.focusMinutes * 60;
      });
      widget.onPhaseChanged(_phase);
      // 先写 idle 持久化，再清 RunState
      await _persistIdleBoundTodo(_boundTodo);
      await PomodoroService.clearRunState();
    }
  }

  // ── 设置弹窗 ─────────────────────────────────────────────────
  void _showSettingsDialog() {
    final focusCtrl = TextEditingController(text: _settings.focusMinutes.toString());
    final breakCtrl = TextEditingController(text: _settings.breakMinutes.toString());
    final cyclesCtrl = TextEditingController(text: _settings.cycles.toString());

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('⚙️ 番茄钟设置'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _settingField('专注时长 (分钟)', focusCtrl),
            const SizedBox(height: 16),
            _settingField('休息时长 (分钟)', breakCtrl),
            const SizedBox(height: 16),
            _settingField('循环次数', cyclesCtrl),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              final f = int.tryParse(focusCtrl.text) ?? 25;
              final b = int.tryParse(breakCtrl.text) ?? 5;
              final c = int.tryParse(cyclesCtrl.text) ?? 4;
              final ns = PomodoroSettings(
                focusMinutes: f.clamp(1, 120),
                breakMinutes: b.clamp(1, 60),
                cycles: c.clamp(1, 20),
              );
              await PomodoroService.saveSettings(ns);
              setState(() {
                _settings = ns;
                if (_phase == PomodoroPhase.idle) {
                  _remainingSeconds = ns.focusMinutes * 60;
                }
              });
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Widget _settingField(String label, TextEditingController ctrl) {
    return TextField(
      controller: ctrl,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  // ── 标签管理弹窗 ─────────────────────────────────────────────
  void _showTagsDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _TagManagerSheet(
        allTags: _allTags,
        selectedUuids: _selectedTagUuids,
        onChanged: (tags, selected) async {
          await PomodoroService.saveTags(tags); // 本地保存，立即完成
          PomodoroService.syncTagsToCloud().catchError((_) => null); // 后台同步
          setState(() {
            _allTags = tags;
            _selectedTagUuids = selected;
          });
          await _persistIdleBoundTodo(_boundTodo);
        },
      ),
    );
  }

  // ── 绑定任务弹窗 ─────────────────────────────────────────────
  void _showBindTodoDialog({bool isSwitching = false}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, controller) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                isSwitching ? '切换专注任务' : '选择专注任务',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  if (!isSwitching)
                    ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.clear, size: 20),
                      ),
                      title: const Text('不绑定任务（自由专注）'),
                      onTap: () async {
                        setState(() => _boundTodo = null);
                        await _persistIdleBoundTodo(null);
                        Navigator.pop(ctx);
                      },
                    ),
                  ..._todos.map((t) => ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.check,
                        size: 20,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    title: Text(t.title, style: const TextStyle(fontWeight: FontWeight.w500)),
                    subtitle: t.remark != null && t.remark!.isNotEmpty
                        ? Text(t.remark!, maxLines: 1, overflow: TextOverflow.ellipsis)
                        : null,
                    selected: t.id == _boundTodo?.id,
                    selectedTileColor: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                    onTap: () async {
                      Navigator.pop(ctx);
                      if (isSwitching) {
                        await _switchTask(t);
                      } else {
                        setState(() => _boundTodo = t);
                        await _persistIdleBoundTodo(t);
                      }
                    },
                  )),
                  if (_todos.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(Icons.inbox_outlined, size: 48, color: Colors.grey),
                            SizedBox(height: 16),
                            Text('没有未完成的待办', style: TextStyle(color: Colors.grey)),
                          ],
                        ),
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

  // ── 沉浸式环形进度画 ─────────────────────────────────────────────
  Widget _buildImmersiveTimer() {
    final isFocusing = _phase == PomodoroPhase.focusing;
    final isBreaking = _phase == PomodoroPhase.breaking;
    final isFinished = _phase == PomodoroPhase.finished;
    final totalSeconds = isBreaking
        ? _settings.breakMinutes * 60
        : _settings.focusMinutes * 60;

    final progress = totalSeconds > 0
        ? 1.0 - (_remainingSeconds / totalSeconds).clamp(0.0, 1.0)
        : 0.0;

    final mins = _remainingSeconds ~/ 60;
    final secs = _remainingSeconds % 60;
    // >60s 只显示分钟（如 "25'"），最后60s 显示 MM:SS
    final timeStr = _remainingSeconds > 60
        ? "${((_remainingSeconds / 60).ceil())}'"
        : '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';

    Color ringColor = Theme.of(context).colorScheme.primary;
    if (isFocusing) ringColor = const Color(0xFFFF6B6B);
    if (isBreaking) ringColor = const Color(0xFF4ECDC4);
    if (isFinished) ringColor = const Color(0xFFFFD166);

    final labelColor = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    final timeColor = Theme.of(context).colorScheme.onSurface;
    final cycleTextColor = Theme.of(context).colorScheme.onSurfaceVariant;
    final cycleBgColor = Theme.of(context).colorScheme.surfaceContainerHighest;
    final trackColor = Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
      width: 280,
      height: 280,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          if (isFocusing || isBreaking)
            BoxShadow(
              color: ringColor.withValues(alpha: 0.2),
              blurRadius: 40,
              spreadRadius: 8,
            ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 底部灰色细环
          SizedBox(
            width: 280,
            height: 280,
            child: CircularProgressIndicator(
              value: 1.0,
              strokeWidth: 12,
              valueColor: AlwaysStoppedAnimation<Color>(trackColor),
            ),
          ),
          // 进度粗环（带圆角）
          SizedBox(
            width: 280,
            height: 280,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 12,
              strokeCap: StrokeCap.round,
              valueColor: AlwaysStoppedAnimation<Color>(ringColor),
            ),
          ),
          // 中间文字区域
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(
                  isBreaking ? '☕ 休息中'
                      : isFinished ? '🎉 完成！'
                      : isFocusing ? '🍅 保持专注'
                      : '准备开始',
                  key: ValueKey(_phase),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: labelColor,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                timeStr,
                style: TextStyle(
                  fontSize: 64,
                  fontWeight: FontWeight.w300,
                  color: timeColor,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  letterSpacing: -2,
                ),
              ),
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: cycleBgColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '第 $_currentCycle / ${_settings.cycles} 轮',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: cycleTextColor,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isIdle = _phase == PomodoroPhase.idle || _phase == PomodoroPhase.finished;
    final bool isFocusing = _phase == PomodoroPhase.focusing;
    final Color contentColor = Theme.of(context).colorScheme.onSurface;

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 顶部工具栏
            SizedBox(
              height: kToolbarHeight,
              child: Row(
                children: [
                  // 专注时显示返回按钮
                  if (isFocusing && Navigator.canPop(context))
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.pop(context),
                    )
                  else
                    const SizedBox(width: 48),
                  const Spacer(),
                  // idle 时显示设置和标签
                  AnimatedOpacity(
                    opacity: isIdle ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 300),
                    child: IgnorePointer(
                      ignoring: !isIdle,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.settings_outlined),
                            tooltip: '设置',
                            onPressed: isIdle ? _showSettingsDialog : null,
                          ),
                          IconButton(
                            icon: const Icon(Icons.label_outline),
                            tooltip: '标签',
                            onPressed: isIdle ? _showTagsDialog : null,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 主内容区：Expanded 撑满剩余空间，Column 居中，不可滚动
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildImmersiveTimer(),
                  const SizedBox(height: 32),
                  _buildTaskArea(isIdle, isFocusing, contentColor),
                  const SizedBox(height: 40),
                  _buildActionButtons(isIdle, isFocusing, contentColor),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 任务绑定区域（抽成独立方法，保持 build 整洁）────────────
  Widget _buildTaskArea(bool isIdle, bool isFocusing, Color contentColor) {
    if (isIdle) {
      return Column(
        children: [
          // 标签选择
          if (_allTags.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: _allTags.map((tag) {
                final selected = _selectedTagUuids.contains(tag.uuid);
                final color = _hexToColor(tag.color);
                return FilterChip(
                  label: Text(tag.name, style: const TextStyle(fontSize: 13)),
                  selected: selected,
                  showCheckmark: false,
                  selectedColor: color.withValues(alpha: 0.2),
                  side: BorderSide(
                    color: selected ? color : Theme.of(context).colorScheme.outlineVariant,
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  onSelected: (val) async {
                    setState(() {
                      if (val) {
                        _selectedTagUuids.add(tag.uuid);
                      } else {
                        _selectedTagUuids.remove(tag.uuid);
                      }
                    });
                    // await 确保写入完成，防止快速离开导致持久化丢失
                    await _persistIdleBoundTodo(_boundTodo);
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
          ],
          // 任务绑定卡片
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: _showBindTodoDialog,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _boundTodo != null
                          ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
                          : Theme.of(context).colorScheme.surfaceContainerHighest,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _boundTodo != null ? Icons.task_alt : Icons.add_task,
                      color: _boundTodo != null
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _boundTodo?.title ?? '点击绑定专注任务',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight:
                                _boundTodo != null ? FontWeight.bold : FontWeight.normal,
                            color: _boundTodo == null
                                ? Theme.of(context).colorScheme.onSurfaceVariant
                                : null,
                          ),
                        ),
                        if (_boundTodo?.remark != null && _boundTodo!.remark!.isNotEmpty)
                          Text(
                            _boundTodo!.remark!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // 专注/休息中：始终显示任务胶囊，无论是否已绑定
    return GestureDetector(
      onTap: isFocusing ? () => _showBindTodoDialog(isSwitching: _boundTodo != null) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _boundTodo != null ? Icons.track_changes_outlined : Icons.add_task,
              size: 16,
              color: _boundTodo != null
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                _boundTodo?.title ?? '点击绑定任务',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: _boundTodo != null ? FontWeight.w500 : FontWeight.normal,
                  color: _boundTodo != null
                      ? contentColor
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (isFocusing) ...[
              const SizedBox(width: 8),
              Icon(
                _boundTodo != null ? Icons.swap_horiz : Icons.chevron_right,
                size: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── 底部操作按钮 ──────────────────────────────────────────────
  Widget _buildActionButtons(bool isIdle, bool isFocusing, Color contentColor) {
    if (isIdle) {
      return FilledButton.icon(
        key: const ValueKey('start_btn'),
        onPressed: () {
          if (_phase == PomodoroPhase.finished) {
            setState(() {
              _currentCycle = 1;
              _remainingSeconds = _settings.focusMinutes * 60;
            });
          }
          _startFocus();
        },
        icon: const Icon(Icons.play_arrow_rounded, size: 28),
        label: Text(
          _phase == PomodoroPhase.finished ? '再来一轮' : '开始专注',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        style: FilledButton.styleFrom(
          minimumSize: const Size(220, 56),
          backgroundColor: const Color(0xFFFF6B6B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          elevation: 4,
        ),
      );
    }

    if (isFocusing) {
      return Column(
        key: const ValueKey('focus_btns'),
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton.icon(
            onPressed: _finishEarly,
            icon: const Icon(Icons.check_circle_outline, size: 22),
            label: const Text('提前完成',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            style: FilledButton.styleFrom(
              minimumSize: const Size(220, 52),
              backgroundColor: const Color(0xFF4CAF50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            ),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: _abandonFocus,
            icon: const Icon(Icons.stop_circle_outlined, size: 20),
            label: const Text('放弃本次专注', style: TextStyle(fontSize: 15)),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      );
    }

    // 休息中
    return OutlinedButton.icon(
      key: const ValueKey('skip_break_btn'),
      onPressed: () async {
        _ticker?.cancel();
        NotificationService.cancelNotification();
        // 先写 idle 持久化，再清 RunState，保留绑定任务和标签
        await _persistIdleBoundTodo(_boundTodo);
        await PomodoroService.clearRunState();
        setState(() {
          _phase = PomodoroPhase.idle;
          _currentCycle += 1;
          _remainingSeconds = _settings.focusMinutes * 60;
        });
        widget.onPhaseChanged(_phase);
      },
      icon: const Icon(Icons.skip_next_rounded),
      label: const Text('跳过休息', style: TextStyle(fontSize: 16)),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// 标签管理 BottomSheet
// ══════════════════════════════════════════════════════════════
class _TagManagerSheet extends StatefulWidget {
  final List<PomodoroTag> allTags;
  final List<String> selectedUuids;
  final void Function(List<PomodoroTag>, List<String>) onChanged;

  const _TagManagerSheet({
    required this.allTags,
    required this.selectedUuids,
    required this.onChanged,
  });

  @override
  State<_TagManagerSheet> createState() => _TagManagerSheetState();
}

class _TagManagerSheetState extends State<_TagManagerSheet> {
  late List<PomodoroTag> _tags;
  late List<String> _selected;

  static const List<String> _presetColors = [
    '#F44336', '#E91E63', '#9C27B0', '#3F51B5',
    '#2196F3', '#009688', '#4CAF50', '#FF9800',
    '#607D8B', '#795548',
  ];

  @override
  void initState() {
    super.initState();
    _tags = List.from(widget.allTags);
    _selected = List.from(widget.selectedUuids);
  }

  void _addTag() {
    final ctrl = TextEditingController();
    String pickedColor = _presetColors[0];
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, sd) => AlertDialog(
          title: const Text('新增标签'),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                decoration: InputDecoration(
                  labelText: '标签名称',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: _presetColors.map((c) {
                  final col = _hexToColor(c);
                  return GestureDetector(
                    onTap: () => sd(() => pickedColor = c),
                    child: CircleAvatar(
                      radius: 18,
                      backgroundColor: col,
                      child: pickedColor == c
                          ? const Icon(Icons.check, color: Colors.white, size: 20)
                          : null,
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () {
                if (ctrl.text.trim().isNotEmpty) {
                  final tag = PomodoroTag(name: ctrl.text.trim(), color: pickedColor);
                  setState(() => _tags.add(tag));
                  widget.onChanged(_tags, _selected);
                  Navigator.pop(ctx);
                }
              },
              child: const Text('添加'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: MediaQuery.of(context).viewInsets,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('管理标签', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.add_circle),
                  color: Theme.of(context).colorScheme.primary,
                  iconSize: 28,
                  onPressed: _addTag,
                ),
              ],
            ),
          ),
          const Divider(),
          if (_tags.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Text('还没有标签，点击右上角添加', style: TextStyle(color: Colors.grey)),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _tags.length,
                itemBuilder: (_, i) {
                  final tag = _tags[i];
                  final color = _hexToColor(tag.color);
                  return ListTile(
                    leading: CircleAvatar(radius: 8, backgroundColor: color),
                    title: Text(tag.name),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Checkbox(
                          value: _selected.contains(tag.uuid),
                          activeColor: color,
                          onChanged: (val) {
                            setState(() {
                              if (val == true) {
                                _selected.add(tag.uuid);
                              } else {
                                _selected.remove(tag.uuid);
                              }
                            });
                            widget.onChanged(_tags, _selected);
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20, color: Colors.grey),
                          onPressed: () {
                            setState(() {
                              _selected.remove(tag.uuid);
                              _tags.removeAt(i);
                            });
                            widget.onChanged(_tags, _selected);
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// 统计看板
// ══════════════════════════════════════════════════════════════
class _PomodoroStats extends StatefulWidget {
  final String username;
  const _PomodoroStats({required this.username});

  @override
  State<_PomodoroStats> createState() => _PomodoroStatsState();
}

class _PomodoroStatsState extends State<_PomodoroStats> {
  int _dimension = 1;
  DateTime _selected = DateTime.now();
  List<PomodoroSession> _sessions = [];
  List<PomodoroTag> _tags = [];
  List<TodoItem> _todos = [];
  bool _loading = true;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _loadLocal().then((_) => _syncIfDue());
  }

  /// 按设置里的同步频率决定是否触发增量同步（与主页 checkAutoSync 逻辑一致）
  Future<void> _syncIfDue() async {
    final interval = await StorageService.getSyncInterval(); // 0=关闭,1=每次,2=30min,3=1h,4=1d
    if (interval == 0) return; // 关闭自动同步
    final lastSync = await StorageService.getLastAutoSyncTime();
    final now = DateTime.now();
    bool due = false;
    if (lastSync == null) {
      due = true;
    } else {
      switch (interval) {
        case 1: due = true; break;
        case 2: due = now.difference(lastSync).inMinutes >= 30; break;
        case 3: due = now.difference(lastSync).inHours >= 1; break;
        case 4: due = now.difference(lastSync).inHours >= 24; break;
        default: due = false;
      }
    }
    if (due) _syncAndRefresh();
  }

  /// 优先加载本地数据，快速展示
  Future<void> _loadLocal() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final tags = await PomodoroService.getTags();
    final todos = await StorageService.getTodos(widget.username);
    final DateTimeRange range = _getRange();
    final sessions = await PomodoroService.getSessionsInRange(range.start, range.end);
    if (!mounted) return;
    setState(() {
      _tags = tags;
      _todos = todos.where((t) => !t.isDeleted).toList();
      _sessions = sessions;
      _loading = false;
    });
  }

  /// 后台增量同步云端，完成后刷新 UI
  Future<void> _syncAndRefresh() async {
    if (!mounted) return;
    setState(() => _syncing = true);
    try {
      await PomodoroService.syncTagsFromCloud();
      await PomodoroService.syncRecordsFromCloud();
    } catch (_) {}
    if (!mounted) return;
    setState(() => _syncing = false);
    await _loadLocal();
  }

  /// 全量拉取（覆盖本地）
  Future<void> _fullPull() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      await PomodoroService.syncTagsFromCloud();
      // 全量：拉取全部时间范围
      await PomodoroService.syncRecordsFromCloud(fromMs: 0);
    } catch (_) {}
    await _loadLocal();
  }

  DateTimeRange _getRange() {
    if (_dimension == 0) {
      final d = DateTime(_selected.year, _selected.month, _selected.day);
      return DateTimeRange(start: d, end: d.add(const Duration(days: 1)));
    } else if (_dimension == 1) {
      final start = DateTime(_selected.year, _selected.month, 1);
      final end = DateTime(_selected.year, _selected.month + 1, 1);
      return DateTimeRange(start: start, end: end);
    } else {
      final start = DateTime(_selected.year, 1, 1);
      final end = DateTime(_selected.year + 1, 1, 1);
      return DateTimeRange(start: start, end: end);
    }
  }

  String _rangeLabel() {
    if (_dimension == 0) return DateFormat('yyyy年MM月dd日').format(_selected);
    if (_dimension == 1) return DateFormat('yyyy年MM月').format(_selected);
    return '${_selected.year}年';
  }

  // ── 编辑专注记录 ────────────────────────────────────────────
  Future<void> _editSession(PomodoroSession session) async {
    List<String> editTags = List.from(session.tagUuids);
    String? editTodoUuid = session.todoUuid;
    String? editTodoTitle = session.todoTitle;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, sd) {
          return Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
              left: 20, right: 20, top: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('编辑专注记录',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await _deleteSession(session);
                    },
                  ),
                ],
              ),
              const Divider(),
              const SizedBox(height: 8),

              // 绑定任务
              const Text('绑定任务', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () async {
                  final picked = await showDialog<TodoItem?>(
                    context: ctx,
                    builder: (dctx) => AlertDialog(
                      title: const Text('选择任务'),
                      content: SizedBox(
                        width: double.maxFinite,
                        child: ListView(
                          shrinkWrap: true,
                          children: [
                            ListTile(
                              title: const Text('自由专注（无绑定）'),
                              leading: const Icon(Icons.clear),
                              onTap: () => Navigator.pop(dctx, null),
                            ),
                            const Divider(),
                            ..._todos.map((t) => ListTile(
                                  title: Text(t.title),
                                  subtitle: t.remark != null ? Text(t.remark!) : null,
                                  leading: Icon(t.isDone
                                      ? Icons.check_circle_outline
                                      : Icons.radio_button_unchecked),
                                  onTap: () => Navigator.pop(dctx, t),
                                )),
                          ],
                        ),
                      ),
                    ),
                  );
                  if (picked != null) {
                    sd(() {
                      editTodoUuid = picked.id;
                      editTodoTitle = picked.title;
                    });
                  } else if (picked == null &&
                      (editTodoUuid != null)) {
                    // 用户选了"自由专注"
                    sd(() {
                      editTodoUuid = null;
                      editTodoTitle = null;
                    });
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.task_alt_outlined, size: 18),
                      const SizedBox(width: 8),
                      Text(editTodoTitle ?? '自由专注（点击选择）'),
                      const Spacer(),
                      const Icon(Icons.chevron_right, size: 18),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 标签
              const Text('标签', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              if (_tags.isEmpty)
                const Text('暂无标签', style: TextStyle(color: Colors.grey))
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _tags.map((tag) {
                    final sel = editTags.contains(tag.uuid);
                    final color = _hexToColor(tag.color);
                    return FilterChip(
                      label: Text(tag.name, style: const TextStyle(fontSize: 13)),
                      selected: sel,
                      showCheckmark: false,
                      selectedColor: color.withValues(alpha: 0.2),
                      side: BorderSide(color: sel ? color : Colors.grey.shade300),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                      onSelected: (v) => sd(() {
                        if (v) {
                          editTags.add(tag.uuid);
                        } else {
                          editTags.remove(tag.uuid);
                        }
                      }),
                    );
                  }).toList(),
                ),

              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    final updated = PomodoroSession(
                      uuid: session.uuid,
                      todoUuid: editTodoUuid,
                      todoTitle: editTodoTitle,
                      tagUuids: editTags,
                      startTime: session.startTime,
                      endTime: session.endTime,
                      plannedDuration: session.plannedDuration,
                      actualDuration: session.actualDuration,
                      status: session.status,
                      deviceId: session.deviceId,
                      isDeleted: session.isDeleted,
                      version: session.version + 1,
                      createdAt: session.createdAt,
                      updatedAt: DateTime.now().millisecondsSinceEpoch,
                    );
                    await PomodoroService.updateSession(updated); // 本地保存，极快
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (mounted) await _loadLocal();
                  },
                  child: const Text('保存'),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
        },
      ),
    );
  }

  Future<void> _deleteSession(PomodoroSession session) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除记录'),
        content: const Text('确定要删除这条专注记录吗？'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await PomodoroService.deleteSession(session.uuid);
      _loadLocal();
    }
  }

  void _prev() {    setState(() {
      if (_dimension == 0) {
        _selected = _selected.subtract(const Duration(days: 1));
      } else if (_dimension == 1) {
        _selected = DateTime(_selected.year, _selected.month - 1, 1);
      } else {
        _selected = DateTime(_selected.year - 1, 1, 1);
      }
    });
    _loadLocal();
  }

  void _next() {
    setState(() {
      if (_dimension == 0) {
        _selected = _selected.add(const Duration(days: 1));
      } else if (_dimension == 1) {
        _selected = DateTime(_selected.year, _selected.month + 1, 1);
      } else {
        _selected = DateTime(_selected.year + 1, 1, 1);
      }
    });
    _loadLocal();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final totalSecs = PomodoroService.totalFocusSeconds(_sessions);
    final byTag = PomodoroService.focusByTag(_sessions);
    final completedCount = _sessions.where((s) => s.isCompleted).length;

    return MediaQuery.removePadding(
      context: context,
      removeTop: true,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 维度切换 ──
          Center(
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('日'))),
                ButtonSegment(value: 1, label: Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('月'))),
                ButtonSegment(value: 2, label: Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('年'))),
              ],
              selected: {_dimension},
              onSelectionChanged: (s) {
                setState(() => _dimension = s.first);
                _loadLocal();
              },
            ),
          ),
          const SizedBox(height: 20),

          // ── 日期导航 + 同步按钮 ──
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton.filledTonal(icon: const Icon(Icons.chevron_left), onPressed: _prev),
              Text(_rangeLabel(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              IconButton.filledTonal(icon: const Icon(Icons.chevron_right), onPressed: _next),
            ],
          ),
          const SizedBox(height: 8),
          // 同步状态行
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (_syncing)
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(width: 14, height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 6),
                    Text('同步中...', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                )
              else
                TextButton.icon(
                  onPressed: _syncAndRefresh,
                  icon: const Icon(Icons.sync, size: 16),
                  label: const Text('增量同步', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.grey,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              const SizedBox(width: 4),
              TextButton.icon(
                onPressed: _syncing ? null : _fullPull,
                icon: const Icon(Icons.cloud_download_outlined, size: 16),
                label: const Text('全量拉取', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.grey,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── 总览卡片 ──
          Row(
            children: [
              _StatCard(
                label: '总专注时长',
                value: PomodoroService.formatDuration(totalSecs),
                icon: Icons.timer_rounded,
                color: const Color(0xFFFF6B6B),
              ),
              const SizedBox(width: 16),
              _StatCard(
                label: '完成次数',
                value: '$completedCount 次',
                icon: Icons.check_circle_rounded,
                color: const Color(0xFF4ECDC4),
              ),
            ],
          ),
          const SizedBox(height: 32),

          // ── 标签分布 ──
          if (byTag.isNotEmpty) ...[
            const Text('标签分布', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: byTag.entries.map((e) {
                  final tagUuid = e.key;
                  final secs = e.value;
                  final tag = tagUuid == '__none__'
                      ? null
                      : _tags.cast<PomodoroTag?>().firstWhere(
                          (t) => t?.uuid == tagUuid,
                      orElse: () => null);
                  final color = tag != null ? _hexToColor(tag.color) : Colors.grey;
                  final ratio = totalSecs > 0 ? secs / totalSecs : 0.0;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(radius: 6, backgroundColor: color),
                            const SizedBox(width: 8),
                            Text(tag?.name ?? '未分类', style: const TextStyle(fontWeight: FontWeight.w500)),
                            const Spacer(),
                            Text(PomodoroService.formatDuration(secs),
                                style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: ratio,
                            minHeight: 10,
                            backgroundColor: color.withValues(alpha: 0.15),
                            valueColor: AlwaysStoppedAnimation<Color>(color),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],

          const SizedBox(height: 32),

          // ── 明细列表 ──
          if (_sessions.isNotEmpty) ...[
            const Text('专注明细', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ..._sessions.map((s) {
              final startLocal = DateTime.fromMillisecondsSinceEpoch(
                      s.startTime, isUtc: true)
                  .toLocal();
              final tagNames = s.tagUuids.isNotEmpty
                  ? s.tagUuids
                      .map((uuid) => _tags
                          .cast<PomodoroTag?>()
                          .firstWhere((t) => t?.uuid == uuid,
                              orElse: () => null)
                          ?.name ?? uuid)
                      .join(', ')
                  : null;
              return Card(
                elevation: 0,
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.3),
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: s.isCompleted
                          ? const Color(0xFF4ECDC4).withValues(alpha: 0.2)
                          : const Color(0xFFFF6B6B).withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      s.isCompleted
                          ? Icons.check_circle_rounded
                          : Icons.timer_off_rounded,
                      color: s.isCompleted
                          ? const Color(0xFF4ECDC4)
                          : const Color(0xFFFF6B6B),
                    ),
                  ),
                  title: Text(s.todoTitle ?? '自由专注',
                      style:
                          const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        Text(DateFormat('HH:mm').format(startLocal),
                            style: const TextStyle(fontSize: 13)),
                        if (tagNames != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(tagNames,
                                style: const TextStyle(fontSize: 11)),
                          ),
                        ]
                      ],
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        PomodoroService.formatDuration(s.effectiveDuration),
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(width: 4),
                      // 编辑按钮
                      IconButton(
                        icon: const Icon(Icons.more_vert, size: 20),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => _editSession(s),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ] else
            Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(
                  children: [
                    Icon(Icons.coffee_outlined, size: 64, color: Theme.of(context).colorScheme.surfaceContainerHighest),
                    const SizedBox(height: 16),
                    const Text('此时段暂无专注记录', style: TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
            ),
        ],
        ),
      ),
    );
  }
}

// ── 统计小卡片 ──────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.2), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 16),
            Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

// ── 工具：hex 颜色转 Color ──────────────────────────────────
Color _hexToColor(String hex) {
  try {
    final h = hex.replaceAll('#', '');
    return Color(int.parse('FF$h', radix: 16));
  } catch (_) {
    return Colors.blueGrey;
  }
}