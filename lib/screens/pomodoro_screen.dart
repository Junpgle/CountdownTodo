import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models.dart';
import '../storage_service.dart';
import '../services/pomodoro_service.dart';
import '../services/notification_service.dart';
import '../services/pomodoro_sync_service.dart';

// ══════════════════════════════════════════════════════════════
// 动态隐藏的 AppBar 包装器

// ══════════════════════════════════════════════════════════════
// 保持状态的淡入淡出 IndexedStack
// ══════════════════════════════════════════════════════════════
class _FadingIndexedStack extends StatefulWidget {
  final int index;
  final List<Widget> children;
  const _FadingIndexedStack({required this.index, required this.children});

  @override
  State<_FadingIndexedStack> createState() => _FadingIndexedStackState();
}

class _FadingIndexedStackState extends State<_FadingIndexedStack>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;
  int _displayIndex = 0;

  @override
  void initState() {
    super.initState();
    _displayIndex = widget.index;
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 280));
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
    _ctrl.forward();
  }

  @override
  void didUpdateWidget(_FadingIndexedStack old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
      _ctrl.reverse().then((_) {
        if (mounted) {
          setState(() => _displayIndex = widget.index);
          _ctrl.forward();
        }
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: IndexedStack(
        index: _displayIndex,
        children: widget.children,
      ),
    );
  }
}

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
  bool _workbenchReady = false;
  final _statsKey = GlobalKey<_PomodoroStatsState>();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
        length: 2, vsync: this, initialIndex: widget.initialTab);
    _tabController.addListener(() {
      if (_tabController.index == 1 && !_tabController.indexIsChanging) {
        _statsKey.currentState?.reload();
      }
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isFocusingOrWatching = !_workbenchReady
        || _currentPhase == PomodoroPhase.focusing
        || _currentPhase == PomodoroPhase.remoteWatching;

    final int tabIndex = _tabController.index;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // ── 顶部导航栏：淡入淡出 ──
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              height: isFocusingOrWatching ? 0 : kToolbarHeight,
              clipBehavior: Clip.hardEdge,
              decoration: const BoxDecoration(),
              child: AnimatedOpacity(
                opacity: isFocusingOrWatching ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 300),
                child: SizedBox(
                  height: kToolbarHeight,
                  child: Padding(
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
                        if (Navigator.canPop(context))
                          const SizedBox(width: 48),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // ── 主内容区：IndexedStack 保持状态 + AnimatedOpacity 淡入淡出 ──
            Expanded(
              child: _FadingIndexedStack(
                index: tabIndex,
                children: [
                  _PomodoroWorkbench(
                    username: widget.username,
                    onPhaseChanged: (phase) {
                      if (mounted && _currentPhase != phase) {
                        setState(() => _currentPhase = phase);
                      }
                    },
                    onReady: () {
                      if (mounted && !_workbenchReady) {
                        setState(() => _workbenchReady = true);
                      }
                    },
                  ),
                  _PomodoroStats(key: _statsKey, username: widget.username),
                ],
              ),
            ),

            // ── 底部 Tab 导航：淡入淡出 ──
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              height: isFocusingOrWatching ? 0 : null,
              clipBehavior: Clip.hardEdge,
              decoration: const BoxDecoration(),
              child: AnimatedOpacity(
                opacity: isFocusingOrWatching ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 300),
                child: SafeArea(
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
  /// _init 完成后调用，通知外层取消 loading 状态
  final VoidCallback? onReady;

  const _PomodoroWorkbench({
    required this.username,
    required this.onPhaseChanged,
    this.onReady,
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

  // ── 跨端感知 ──
  final _syncService = PomodoroSyncService();
  StreamSubscription<CrossDevicePomodoroState>? _crossDeviceSub;
  CrossDevicePomodoroState? _remoteState;
  bool _showRemoteBanner = false;
  int _remoteRemainingSeconds = 0;
  Timer? _remoteTicker;

  // ── 初始化标志（init 完成前不渲染主 UI，避免闪出"准备开始"界面）──
  bool _initializing = true;

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
    _remoteTicker?.cancel();
    _crossDeviceSub?.cancel();   // 只取消 UI 层订阅，不断开 WebSocket 连接
    // ⚠️ 不调用 _syncService.disconnect()，单例连接保持 App 级生命周期
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
    case AppLifecycleState.resumed:
      _notifyTickCount = 0;
      _recoverFromBackground();
      // 强制重连让服务器推送 SYNC，确保跨端状态最新
      _syncService.resumeSync();
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

    // ── ① 先恢复本地运行状态（确定 _phase），再连接 WebSocket ──
    // 顺序很重要：必须让 _phase 先稳定，SYNC 信号到达时才能正确判断是否展示横幅
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

    // ── ② 本地状态已稳定，再连接 WebSocket ──
    await _connectCrossDevice();

    // 等 400ms 让服务器 SYNC 消息有时间到达并被处理
    await Future.delayed(const Duration(milliseconds: 400));

    if (mounted) {
      setState(() => _initializing = false);
      widget.onReady?.call();
    }
  }

  // ── 跨端感知：连接 & 处理信号 ───────────────────────────────

  Future<void> _connectCrossDevice() async {
    final prefs = await SharedPreferences.getInstance();
    final userIdInt = prefs.getInt('current_user_id');
    if (userIdInt == null || _deviceId.isEmpty) return;
    final userId = userIdInt.toString();

    // ① 先订阅广播流，再 connect——避免 SYNC 消息在订阅建立前到达而丢失
    _crossDeviceSub?.cancel();
    _crossDeviceSub = _syncService.onStateChanged.listen(_handleCrossDeviceSignal);

    // ② 每次进入番茄钟页面都强制重新连接：
    //    服务器的 SYNC 只在新设备上线时推送一次（迟到同步机制），
    //    重连会触发服务器推当前房间的 focusState，接收端才能拿到对方的专注状态。
    await _syncService.forceReconnect(userId, 'flutter_$_deviceId');
  }

  void _handleCrossDeviceSignal(CrossDevicePomodoroState signal) {
    if (!mounted) return;

    // 过滤本机自己发出的信号（服务器 SYNC 可能把本机的专注状态回放给自己）
    final myDeviceId = 'flutter_$_deviceId';
    if (signal.sourceDevice != null && signal.sourceDevice == myDeviceId) return;

    switch (signal.action) {
      case 'START':
      case 'SYNC':
        // 本机正在专注/休息时不覆盖（不打扰自己）
        if (_phase == PomodoroPhase.focusing || _phase == PomodoroPhase.breaking) break;

        // 验证 targetEndMs 仍然有效
        final endMs = signal.targetEndMs;
        if (endMs == null) break;
        final rem = ((endMs - DateTime.now().millisecondsSinceEpoch) / 1000).ceil();
        if (rem <= 0) break; // 对方已结束，忽略

        // 进入"跨端观察"模式，复用现有计时 UI
        final todoTitle = signal.todoTitle;
        final remoteTodo = todoTitle != null && todoTitle.isNotEmpty
            ? TodoItem(id: signal.todoUuid ?? '', title: todoTitle, isDone: false, createdAt: 0)
            : null;

        setState(() {
          _phase = PomodoroPhase.remoteWatching;
          _targetEndMs = endMs;
          _remainingSeconds = rem;
          _boundTodo = remoteTodo;
          _remoteState = signal;
        });
        widget.onPhaseChanged(_phase);
        _startRemoteTicker(endMs);
        break;

      case 'STOP':
      case 'INTERRUPT':
        if (_phase != PomodoroPhase.remoteWatching) break;
        _stopRemoteTicker();
        setState(() {
          _phase = PomodoroPhase.idle;
          _remainingSeconds = _settings.focusMinutes * 60;
          _remoteState = null;
          _boundTodo = null;
        });
        widget.onPhaseChanged(_phase);
        break;

      case 'SWITCH':
        // 仅在观察模式下更新任务信息
        if (_phase != PomodoroPhase.remoteWatching) break;
        if (signal.todoTitle != null && signal.todoTitle!.isNotEmpty) {
          setState(() {
            _boundTodo = TodoItem(
              id: signal.todoUuid ?? '',
              title: signal.todoTitle!,
              isDone: false,
              createdAt: 0,
            );
            _remoteState = CrossDevicePomodoroState(
              action: _remoteState?.action ?? 'SYNC',
              todoUuid: signal.todoUuid ?? _remoteState?.todoUuid,
              todoTitle: signal.todoTitle,
              duration: _remoteState?.duration,
              targetEndMs: _remoteState?.targetEndMs,
              sourceDevice: _remoteState?.sourceDevice,
            );
          });
        }
        break;

      case 'HEARTBEAT':
        break;
    }
  }

  /// 启动跨端观察倒计时（驱动 _remainingSeconds，与本地专注共用同一个字段）
  void _startRemoteTicker(int targetEndMs) {
    _remoteTicker?.cancel();

    _remoteTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) { _remoteTicker?.cancel(); return; }
      final rem = ((targetEndMs - DateTime.now().millisecondsSinceEpoch) / 1000).ceil();
      if (rem <= 0) {
        // 对方专注自然结束
        _remoteTicker?.cancel();
        if (_phase == PomodoroPhase.remoteWatching) {
          setState(() {
            _phase = PomodoroPhase.idle;
            _remainingSeconds = _settings.focusMinutes * 60;
            _remoteState = null;
            _boundTodo = null;
          });
          widget.onPhaseChanged(_phase);
        }
      } else {
        if (_phase == PomodoroPhase.remoteWatching) {
          setState(() => _remainingSeconds = rem);
        }
      }
    });
  }

  /// 停止跨端观察倒计时
  void _stopRemoteTicker() {
    _remoteTicker?.cancel();
    _remoteTicker = null;
    _remoteRemainingSeconds = 0;
  }
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

          // 重新注册保活 Alarm（防止 ReminderService rescheduleAll 覆写后失效）
          final isFocusing = saved.phase == PomodoroPhase.focusing;
          final alarmNotifId = isFocusing ? 40001 : 40002;
          final alarmTitle = isFocusing ? '🍅 专注时间到！' : '☕ 休息结束，继续出发！';
          final alarmText = isFocusing
              ? (saved.todoTitle?.isNotEmpty == true
                  ? '"${saved.todoTitle}" 专注时段已结束'
                  : '本轮专注已结束，做个总结吧')
              : '第 ${saved.currentCycle}/${saved.totalCycles} 轮完成，下一轮专注准备好了';
          NotificationService.scheduleReminders([{
            'triggerAtMs': saved.targetEndMs,
            'title': alarmTitle,
            'text': alarmText,
            'notifId': alarmNotifId,
          }]);
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
    // App 重启后自行处理结束流程，取消保活 Alarm 避免重复弹通知
    NotificationService.cancelReminder(40001);
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
    await PomodoroService.clearRunState();
    await _askCompletionAndRecord(
      durationSeconds: saved.focusSeconds,
      startMs: saved.sessionStartMs,
      endMs: saved.targetEndMs,
    );
    await _proceedAfterRecord();
  }

  Future<void> _handleBreakEndFromBackground(PomodoroRunState saved) async {
    // App 重启后自行处理结束流程，取消保活 Alarm 避免重复弹通知
    NotificationService.cancelReminder(40002);
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
      if (!mounted) return;
      // phase 已切换（对话框期间）则停止推送通知
      if (_phase != PomodoroPhase.focusing && _phase != PomodoroPhase.breaking) return;

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
        setState(() => _remainingSeconds = remaining);

        _notifyTickCount++;
        final int interval = remaining <= 60 ? 1 : 60;
        if (_notifyTickCount >= interval) {
          _notifyTickCount = 0;
          // 再次确认 phase 未切换
          if (_phase == PomodoroPhase.focusing || _phase == PomodoroPhase.breaking) {
            _pushPomodoroNotification(overrideRemaining: remaining);
          }
        }
      }
    });
  }

  // ── 开始专注 ─────────────────────────────────────────────────
  Future<void> _startFocus() async {
    // 若当前处于跨端观察模式，先停止远端计时并清理远端污染的状态
    if (_phase == PomodoroPhase.remoteWatching) {
      _stopRemoteTicker();
      // 从本地持久化恢复用户自己选择的任务和标签
      final prefs = await SharedPreferences.getInstance();
      final savedUuid  = prefs.getString(_keyBoundTodoUuid);
      final savedTitle = prefs.getString(_keyBoundTodoTitle);
      final savedTagsRaw = prefs.getString(_keySelectedTagUuids);
      _selectedTagUuids = savedTagsRaw != null && savedTagsRaw.isNotEmpty
          ? savedTagsRaw.split(',').where((s) => s.isNotEmpty).toList()
          : [];
      TodoItem? localTodo;
      if (savedUuid != null && savedUuid.isNotEmpty) {
        localTodo = _todos.cast<TodoItem?>().firstWhere(
          (t) => t?.id == savedUuid, orElse: () => null);
        if (localTodo == null && savedTitle != null && savedTitle.isNotEmpty) {
          localTodo = TodoItem(id: savedUuid, title: savedTitle, isDone: false, createdAt: 0);
        }
      }
      _boundTodo = localTodo;
      _remoteState = null;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final durationMs = _settings.focusMinutes * 60 * 1000;
    final end = now + durationMs;

    setState(() {
      _phase = PomodoroPhase.focusing;
      _targetEndMs = end;
      _remainingSeconds = _settings.focusMinutes * 60;
      _sessionStartMs = now;
      _showRemoteBanner = false;
      _remoteState = null;
    });
    _stopRemoteTicker();
    widget.onPhaseChanged(_phase);

    // 立即上岛 + 启动计时（不等 IO）
    _pushPomodoroNotification(alertKey: 'pomo_start_$end');
    _startTicker();

    // 保活：注册精确 Alarm，App 被杀后在 end 时刻发出"专注结束"通知
    NotificationService.scheduleReminders([{
      'triggerAtMs': end,
      'title': '🍅 专注时间到！',
      'text': _boundTodo?.title?.isNotEmpty == true
          ? '"${_boundTodo!.title}" 专注时段已结束'
          : '本轮专注已结束，做个总结吧',
      'notifId': 40001,
    }]);

    // 后台：写 RunState / 清 idle 持久化 / 广播（不阻塞 UI）
    PomodoroService.saveRunState(PomodoroRunState(
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
    _persistIdleBoundTodo(null);
    _syncService.sendStartSignal(
      todoUuid: _boundTodo?.id,
      todoTitle: _boundTodo?.title,
      durationSeconds: _settings.focusMinutes * 60,
      targetEndMs: end,
    );
  }
  Future<void> _switchTask(TodoItem newTodo) async {
    if (_phase != PomodoroPhase.focusing) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final actualSeconds = ((now - _sessionStartMs) / 1000).round();

    // 立即切换 UI（不等 IO）
    setState(() {
      _boundTodo = newTodo;
      _sessionStartMs = now;
    });

    // 立即更新通知，让任务名马上跟随切换
    _pushPomodoroNotification();

    // 后台：记录上一段任务 + 保存 RunState（不阻塞 UI）
    if (actualSeconds > 5) {
      PomodoroService.addRecord(PomodoroRecord(
        todoUuid: _boundTodo?.id,
        todoTitle: _boundTodo?.title,
        tagUuids: List.from(_selectedTagUuids),
        startTime: _sessionStartMs - actualSeconds * 1000,
        endTime: now,
        plannedDuration: _settings.focusMinutes * 60,
        actualDuration: actualSeconds,
        status: PomodoroRecordStatus.switched,
        deviceId: _deviceId.isNotEmpty ? _deviceId : null,
      ));
    }

    PomodoroService.saveRunState(PomodoroRunState(
      phase: PomodoroPhase.focusing,
      targetEndMs: _targetEndMs,
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

    _syncService.sendSwitchSignal(todoUuid: newTodo.id, todoTitle: newTodo.title);

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
    // 取消保活 Alarm，避免 App 活着时重复弹出
    NotificationService.cancelReminder(40001);
    NotificationService.cancelReminder(40002);
    final now = DateTime.now().millisecondsSinceEpoch;
    final actualSeconds = ((now - _sessionStartMs) / 1000).round();

    // 先写持久化 / 清状态
    await _persistIdleBoundTodo(_boundTodo);
    await PomodoroService.clearRunState();
    _syncService.sendStopSignal();

    // 弹对话框并写记录（此时 _phase 仍是 focusing，大圆环不跳动）
    await _askCompletionAndRecord(
      durationSeconds: actualSeconds,
      startMs: _sessionStartMs,
      endMs: now,
    );

    // 发结束通知
    NotificationService.sendPomodoroEndAlert(
      alertKey: 'pomo_end_$now',
      todoTitle: _boundTodo?.title,
      isBreak: false,
    );

    // 对话框关闭后才切换 phase & 决定下一步
    await _proceedAfterRecord();
  }

  // ── 专注结束 ─────────────────────────────────────────────────
  Future<void> _onFocusEnd() async {
    // App 活着时自然到点，取消保活 Alarm，避免重复弹出
    NotificationService.cancelReminder(40001);
    final now = DateTime.now().millisecondsSinceEpoch;

    await _persistIdleBoundTodo(_boundTodo);
    await PomodoroService.clearRunState();
    _syncService.sendStopSignal();

    // 弹对话框并写记录（_phase 仍是 focusing）
    await _askCompletionAndRecord(
      durationSeconds: _settings.focusMinutes * 60,
      startMs: _sessionStartMs,
      endMs: now,
    );

    NotificationService.sendPomodoroEndAlert(
      alertKey: 'pomo_end_$now',
      todoTitle: _boundTodo?.title,
      isBreak: false,
    );

    // 对话框关闭后切换 phase & 决定下一步
    await _proceedAfterRecord();
  }

  /// 弹出"是否完成"对话框，写入专注记录，返回用户是否选择完成
  Future<bool> _askCompletionAndRecord({
    required int durationSeconds,
    required int startMs,
    required int endMs,
  }) async {
    if (!mounted) return false;

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

    // 构建记录
    final record = PomodoroRecord(
      todoUuid: (_boundTodo?.id?.isNotEmpty == true) ? _boundTodo!.id : null,
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

    // 本地写入：先保存本地（快），网络上传后台做（不阻塞）
    PomodoroService.addRecord(record);

    // 若用户选择完成，标记待办
    if (completed == true && _boundTodo != null && _boundTodo!.id.isNotEmpty) {
      StorageService.getTodos(widget.username).then((allTodos) async {
        final idx = allTodos.indexWhere((t) => t.id == _boundTodo!.id);
        if (idx != -1) {
          allTodos[idx].isDone = true;
          allTodos[idx].markAsChanged();
          await StorageService.saveTodos(widget.username, allTodos);
        }
      });
      final localIdx = _todos.indexWhere((t) => t.id == _boundTodo!.id);
      if (localIdx != -1 && mounted) {
        setState(() => _todos[localIdx].isDone = true);
      }
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

    return completed ?? false;
  }

  /// 对话框关闭后决定下一步：开始休息 or 全部完成
  Future<void> _proceedAfterRecord() async {
    if (!mounted) return;
    if (_currentCycle < _settings.cycles) {
      // _startBreak 内部会自己 setState(_phase = breaking) + widget.onPhaseChanged
      await _startBreak();
    } else {
      setState(() {
        _phase = PomodoroPhase.finished;
        _currentCycle = 1;
        _remainingSeconds = _settings.focusMinutes * 60;
      });
      widget.onPhaseChanged(_phase);
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

    // 立即上岛 + 启动计时
    _pushPomodoroNotification();
    _startTicker();

    // 保活：注册休息结束 Alarm，先取消专注 Alarm（如果有）
    NotificationService.cancelReminder(40001);
    NotificationService.scheduleReminders([{
      'triggerAtMs': end,
      'title': '☕ 休息结束，继续出发！',
      'text': '第 $_currentCycle/${_settings.cycles} 轮完成，下一轮专注准备好了',
      'notifId': 40002,
    }]);

    // 后台写 RunState（不阻塞 UI）
    PomodoroService.saveRunState(PomodoroRunState(
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
  }

  // ── 休息结束 ─────────────────────────────────────────────────
  Future<void> _onBreakEnd() async {
    // App 活着时自然到点，取消保活 Alarm，避免重复弹出
    NotificationService.cancelReminder(40002);
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
    // ① 先暂停 ticker，防止 dialog 期间触发 _onFocusEnd 弹出第二个对话框
    _ticker?.cancel();
    _ticker = null;

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
      NotificationService.cancelNotification();
      // 取消保活 Alarm
      NotificationService.cancelReminder(40001);
      NotificationService.cancelReminder(40002);
      _syncService.sendStopSignal();
      setState(() {
        _phase = PomodoroPhase.idle;
        _currentCycle = 1;
        _remainingSeconds = _settings.focusMinutes * 60;
      });
      widget.onPhaseChanged(_phase);
      _persistIdleBoundTodo(_boundTodo);
      PomodoroService.clearRunState();
    } else {
      // 用户选"继续专注"：恢复 ticker
      _startTicker();
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
    final isRemote   = _phase == PomodoroPhase.remoteWatching;
    final isActive   = isFocusing || isBreaking || isRemote;
    final totalSeconds = isBreaking
        ? _settings.breakMinutes * 60
        : _settings.focusMinutes * 60;

    final progress = totalSeconds > 0
        ? 1.0 - (_remainingSeconds / totalSeconds).clamp(0.0, 1.0)
        : 0.0;

    final mins = _remainingSeconds ~/ 60;
    final secs = _remainingSeconds % 60;
    final timeStr = _remainingSeconds > 60
        ? "${((_remainingSeconds / 60).ceil())}'"
        : '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';

    Color ringColor = Theme.of(context).colorScheme.primary;
    if (isFocusing) ringColor = const Color(0xFFFF6B6B);
    if (isBreaking) ringColor = const Color(0xFF4ECDC4);
    if (isFinished) ringColor = const Color(0xFFFFD166);
    if (isRemote)   ringColor = const Color(0xFFFF6B6B).withValues(alpha: 0.6);

    final labelColor = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    final timeColor  = Theme.of(context).colorScheme.onSurface;
    final cycleTextColor = Theme.of(context).colorScheme.onSurfaceVariant;
    final cycleBgColor   = Theme.of(context).colorScheme.surfaceContainerHighest;
    final trackColor     = Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5);

    final remoteTotal = _remoteState?.duration;
    final remoteProgress = (isRemote && remoteTotal != null && remoteTotal > 0)
        ? 1.0 - (_remainingSeconds / remoteTotal).clamp(0.0, 1.0)
        : progress;

    final String labelText = isBreaking  ? '☕ 休息中'
        : isFinished ? '🎉 完成！'
        : isFocusing ? '🍅 保持专注'
        : isRemote   ? '👀 ${_remoteState?.sourceDevice?.replaceFirst('flutter_', '') ?? '其他设备'} 专注中'
        : '准备开始';

    final String cycleText = isRemote
        ? '同步观察'
        : '第 $_currentCycle / ${_settings.cycles} 轮';

    // idle: 210, active: 268 — AnimatedContainer 驱动平滑放大/缩小
    final double ringSize = isActive ? 268.0 : 210.0;
    final double strokeW  = isActive ? 12.0 : 10.0;
    final double timeFontSize  = isActive ? 60.0 : 48.0;
    final double labelFontSize = isActive ? 13.0 : 12.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
      width: ringSize,
      height: ringSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          if (isActive)
            BoxShadow(
              color: ringColor.withValues(alpha: 0.2),
              blurRadius: 36,
              spreadRadius: 8,
            ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 底部轨道环
          SizedBox(
            width: ringSize,
            height: ringSize,
            child: CircularProgressIndicator(
              value: 1.0,
              strokeWidth: strokeW,
              valueColor: AlwaysStoppedAnimation<Color>(trackColor),
            ),
          ),
          // 进度环
          SizedBox(
            width: ringSize,
            height: ringSize,
            child: CircularProgressIndicator(
              value: remoteProgress,
              strokeWidth: strokeW,
              strokeCap: StrokeCap.round,
              valueColor: AlwaysStoppedAnimation<Color>(ringColor),
            ),
          ),
          // 中间文字
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(
                  labelText,
                  key: ValueKey(_phase),
                  style: TextStyle(
                    fontSize: labelFontSize,
                    fontWeight: FontWeight.w500,
                    color: labelColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 2),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeInOut,
                style: TextStyle(
                  fontSize: timeFontSize,
                  fontWeight: FontWeight.w300,
                  color: timeColor,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  letterSpacing: -2,
                ),
                child: Text(timeStr),
              ),
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: cycleBgColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  cycleText,
                  style: TextStyle(
                    fontSize: 11,
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
    final bool isRemoteWatching = _phase == PomodoroPhase.remoteWatching;
    final Color contentColor = Theme.of(context).colorScheme.onSurface;

    return SafeArea(
      bottom: false,
      child: AnimatedOpacity(
        opacity: _initializing ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ── 顶部工具栏 ──
              SizedBox(
                height: kToolbarHeight,
                child: Row(
                  children: [
                    AnimatedOpacity(
                      opacity: (isFocusing || isRemoteWatching) ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 300),
                      child: IgnorePointer(
                        ignoring: !(isFocusing || isRemoteWatching),
                        child: Navigator.canPop(context)
                            ? IconButton(
                                icon: const Icon(Icons.arrow_back),
                                onPressed: () => Navigator.pop(context),
                              )
                            : const SizedBox(width: 48),
                      ),
                    ),
                    const Spacer(),
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

              // ── 主内容区 ──
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (child, anim) =>
                      FadeTransition(opacity: anim, child: child),
                  child: isIdle
                      ? KeyedSubtree(
                          key: const ValueKey('layout_idle'),
                          child: _buildIdleLayout(contentColor),
                        )
                      : KeyedSubtree(
                          key: ValueKey('layout_active_$_phase'),
                          child: _buildActiveLayout(isFocusing, isRemoteWatching, contentColor),
                        ),
                ),
              ),

              SafeArea(top: false, child: const SizedBox(height: 8)),
            ],
          ),
        ),
      ),
    );
  }

  // ── idle 布局：圆环偏上，中间标签，底部固定按钮 ──────────────
  Widget _buildIdleLayout(Color contentColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 圆环区域，给一个顶部弹性间距让它偏上
        const Spacer(flex: 2),
        _buildImmersiveTimer(),
        const SizedBox(height: 20),
        // 标签选择区（限高3行，可滚动）
        _buildIdleMiddle(),
        const Spacer(flex: 3),
        // 底部按钮固定
        _buildBottomActions(true, false, false, contentColor),
      ],
    );
  }

  // ── active 布局：圆环居中，下方标签只读 + 任务/按钮 ──────────
  Widget _buildActiveLayout(bool isFocusing, bool isRemoteWatching, Color contentColor) {
    // 专注中已选标签（只读展示）
    final List<PomodoroTag> activeTags = _allTags
        .where((t) => _selectedTagUuids.contains(t.uuid))
        .toList();

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 圆环（active 时大）
        _buildImmersiveTimer(),
        const SizedBox(height: 16),

        // 已选标签（只读小胶囊）
        if (activeTags.isNotEmpty && !isRemoteWatching) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: activeTags.map((tag) {
              final color = _hexToColor(tag.color);
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: color.withValues(alpha: 0.4)),
                ),
                child: Text(
                  tag.name,
                  style: TextStyle(
                    fontSize: 12,
                    color: color.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
        ],

        // 任务胶囊 / 观察提示（专注和休息中显示）
        _buildTaskArea(false, isFocusing, isRemoteWatching, contentColor),
        const SizedBox(height: 24),

        // 操作按钮
        _buildBottomActions(false, isFocusing, isRemoteWatching, contentColor),
      ],
    );
  }

  /// idle 状态中间区：标签（限 3 行，超出可滚动）+ 任务区在底部单独处理
  Widget _buildIdleMiddle() {
    if (_allTags.isEmpty) {
      return const SizedBox.shrink();
    }
    // 计算 chip 高度：每行约 40px，3 行约 140px
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 148),
      child: SingleChildScrollView(
        child: Wrap(
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
                await _persistIdleBoundTodo(_boundTodo);
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  /// 底部固定操作区
  Widget _buildBottomActions(bool isIdle, bool isFocusing, bool isRemoteWatching, Color contentColor) {
    // 观察模式
    if (isRemoteWatching) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.info_outline, size: 18,
                color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
            const SizedBox(width: 6),
            Text(
              '请在专注发起端进行操作',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      );
    }

    if (isIdle) {
      // 并排：[绑定任务(Expanded)]  [开始专注(Expanded)]
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            // 绑定任务按钮
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _showBindTodoDialog,
                icon: Icon(
                  _boundTodo != null ? Icons.task_alt : Icons.add_task,
                  size: 20,
                  color: _boundTodo != null
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                label: Flexible(
                  child: Text(
                    _boundTodo?.title ?? '绑定任务',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: _boundTodo != null ? FontWeight.w600 : FontWeight.normal,
                      color: _boundTodo != null
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  side: BorderSide(
                    color: _boundTodo != null
                        ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.6)
                        : Theme.of(context).colorScheme.outlineVariant,
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // 开始专注按钮
            Expanded(
              child: FilledButton.icon(
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
                icon: const Icon(Icons.play_arrow_rounded, size: 24),
                label: Text(
                  _phase == PomodoroPhase.finished ? '再来一轮' : '开始专注',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: const Color(0xFFFF6B6B),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 2,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (isFocusing) {
      return Column(
        key: const ValueKey('focus_btns'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _finishEarly,
                  icon: const Icon(Icons.check_circle_outline, size: 20),
                  label: const Text('提前完成', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: const Color(0xFF4CAF50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _abandonFocus,
                  icon: const Icon(Icons.stop_circle_outlined, size: 20),
                  label: const Text('放弃专注', style: TextStyle(fontSize: 15)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    }

    // 休息中
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: OutlinedButton.icon(
        key: const ValueKey('skip_break_btn'),
        onPressed: () async {
          _ticker?.cancel();
          NotificationService.cancelNotification();
          // 取消休息保活 Alarm
          NotificationService.cancelReminder(40002);
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
          minimumSize: const Size(double.infinity, 52),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }

  // ── 任务胶囊（active 状态中间区）──────────────────────────────
  Widget _buildTaskArea(bool isIdle, bool isFocusing, bool isRemoteWatching, Color contentColor) {
    if (isRemoteWatching) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.6)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.track_changes_outlined, size: 15,
                color: const Color(0xFFFF6B6B).withValues(alpha: 0.7)),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                _boundTodo?.title ?? '自由专注',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: _boundTodo != null ? FontWeight.w500 : FontWeight.normal,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (isFocusing) {
      // 可点击切换的任务胶囊（全宽）
      return GestureDetector(
        onTap: () => _showBindTodoDialog(isSwitching: _boundTodo != null),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: Row(
            children: [
              Icon(
                _boundTodo != null ? Icons.track_changes_outlined : Icons.add_task,
                size: 16,
                color: _boundTodo != null
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
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
              Icon(
                _boundTodo != null ? Icons.swap_horiz : Icons.chevron_right,
                size: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      );
    }

    // 休息中：只读胶囊
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.track_changes_outlined, size: 15,
              color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              _boundTodo?.title ?? '自由专注',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
        ],
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
              constraints: const BoxConstraints(maxHeight: 360),
              child: ReorderableListView.builder(
                shrinkWrap: true,
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    if (newIndex > oldIndex) newIndex--;
                    final tag = _tags.removeAt(oldIndex);
                    _tags.insert(newIndex, tag);
                  });
                  widget.onChanged(_tags, _selected);
                },
                itemCount: _tags.length,
                itemBuilder: (_, i) {
                  final tag = _tags[i];
                  final color = _hexToColor(tag.color);
                  return ListTile(
                    key: ValueKey(tag.uuid),
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
                        const Icon(Icons.drag_handle, size: 20, color: Colors.grey),
                        const SizedBox(width: 4),
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
  const _PomodoroStats({super.key, required this.username});

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

  /// 外部（TabController 切换）触发刷新：先加载本地，再触发增量同步
  void reload() {
    _loadLocal().then((_) => _syncAndRefresh());
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
    } catch (e) {
      debugPrint('[PomodoroStats] _syncAndRefresh error: $e');
    }
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

  // ── 构建明细列表（月/年维度按天分组，日维度直接列出）──────
  List<Widget> _buildSessionList() {
    // 按开始时间降序（最近的在前）
    final sorted = List<PomodoroSession>.from(_sessions)
      ..sort((a, b) => b.startTime.compareTo(a.startTime));

    if (_dimension == 0) {
      // 日视图：直接列出，只显示时刻
      return sorted.map((s) => _buildSessionCard(s, showDate: false)).toList();
    }

    // 月/年视图：按"本地日期"分组，组内按时间降序
    final Map<String, List<PomodoroSession>> groups = {};
    for (final s in sorted) {
      final local = DateTime.fromMillisecondsSinceEpoch(s.startTime, isUtc: true).toLocal();
      final key = DateFormat('yyyy-MM-dd').format(local);
      groups.putIfAbsent(key, () => []).add(s);
    }

    // 按日期键降序（最近日期在最上）
    final sortedKeys = groups.keys.toList()..sort((a, b) => b.compareTo(a));

    final widgets = <Widget>[];
    for (final key in sortedKeys) {
      final dayDate = DateTime.parse(key);
      final dayLabel = _dimension == 1
          ? DateFormat('MM月dd日').format(dayDate)
          : DateFormat('yyyy年MM月dd日').format(dayDate);
      widgets.add(Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Text(
          dayLabel,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ));
      for (final s in groups[key]!) {
        widgets.add(_buildSessionCard(s, showDate: false));
      }
    }
    return widgets;
  }

  Widget _buildSessionCard(PomodoroSession s, {required bool showDate}) {
    final startLocal = DateTime.fromMillisecondsSinceEpoch(s.startTime, isUtc: true).toLocal();
    final tagNames = s.tagUuids.isNotEmpty
        ? s.tagUuids
            .map((uuid) => _tags.cast<PomodoroTag?>()
                .firstWhere((t) => t?.uuid == uuid, orElse: () => null)
                ?.name ?? uuid)
            .join(', ')
        : null;
    final timeLabel = showDate
        ? DateFormat('MM-dd HH:mm').format(startLocal)
        : DateFormat('HH:mm').format(startLocal);

    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: s.isCompleted
                ? const Color(0xFF4ECDC4).withValues(alpha: 0.2)
                : const Color(0xFFFF6B6B).withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
          child: Icon(
            s.isCompleted ? Icons.check_circle_rounded : Icons.timer_off_rounded,
            color: s.isCompleted ? const Color(0xFF4ECDC4) : const Color(0xFFFF6B6B),
          ),
        ),
        title: Text(s.todoTitle ?? '自由专注',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Text(timeLabel, style: const TextStyle(fontSize: 13)),
              if (tagNames != null) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(tagNames,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11)),
                  ),
                ),
              ],
            ],
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              PomodoroService.formatDuration(s.effectiveDuration),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(width: 4),
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
            // 按日期分组：月/年维度按天分组，日维度直接列出
            ..._buildSessionList(),
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