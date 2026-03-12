import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models.dart';
import '../services/api_service.dart';
import '../storage_service.dart';
import '../services/pomodoro_service.dart';

// ══════════════════════════════════════════════════════════
// 常量
// ══════════════════════════════════════════════════════════
const double kHourHeight = 72.0;
const double kTimeColW = 56.0;
const double kHeaderH = 60.0;
const double kVPad = 24.0;
const double kTotalH = 24 * kHourHeight + kVPad * 2;
const double kDayColW = 100.0;

const List<String> kPalette = [
  '#EF4444',
  '#F97316',
  '#EAB308',
  '#22C55E',
  '#10B981',
  '#06B6D4',
  '#3B82F6',
  '#8B5CF6',
  '#EC4899',
  '#F43F5E',
];

Color hexColor(String hex, {double opacity = 1.0}) {
  final c = Color(int.parse('FF${hex.replaceAll('#', '')}', radix: 16));
  return c.withOpacity(opacity);
}

DateTime _dayStart(DateTime d) => DateTime(d.year, d.month, d.day);

List<DateTime> _weekDays([DateTime? now]) {
  final n = now ?? DateTime.now();
  final mon = _dayStart(n.subtract(Duration(days: n.weekday - 1)));
  return List.generate(7, (i) => mon.add(Duration(days: i)));
}

// ══════════════════════════════════════════════════════════
// ★ FIX 1: 主题感知颜色助手
// 所有颜色通过 _TC 获取，自动适配亮/暗主题，不再硬编码深色
// ══════════════════════════════════════════════════════════
class _TC {
  static Color surface(BuildContext ctx) => Theme.of(ctx).colorScheme.surface;
  static Color card(BuildContext ctx) =>
      Theme.of(ctx).brightness == Brightness.dark
          ? const Color(0xFF1A1A1A)
          : Theme.of(ctx).colorScheme.surfaceVariant;
  static Color topBar(BuildContext ctx) =>
      Theme.of(ctx).brightness == Brightness.dark
          ? const Color(0xFF0D0D0D)
          : Theme.of(ctx).colorScheme.surface;
  static Color inputFill(BuildContext ctx) =>
      Theme.of(ctx).brightness == Brightness.dark
          ? const Color(0xFF181818)
          : Theme.of(ctx).colorScheme.surfaceVariant;
  static Color text(BuildContext ctx) => Theme.of(ctx).colorScheme.onSurface;
  static Color textSub(BuildContext ctx) =>
      Theme.of(ctx).colorScheme.onSurface.withOpacity(0.55);
  static Color textHint(BuildContext ctx) =>
      Theme.of(ctx).colorScheme.onSurface.withOpacity(0.28);
  static Color divider(BuildContext ctx) => Theme.of(ctx).dividerColor;
  static Color btnBg(BuildContext ctx) =>
      Theme.of(ctx).brightness == Brightness.dark
          ? const Color(0xFF222222)
          : Theme.of(ctx).colorScheme.surfaceVariant;
  static Color btnBorder(BuildContext ctx) =>
      Theme.of(ctx).brightness == Brightness.dark
          ? const Color(0xFF333333)
          : Theme.of(ctx).dividerColor;
  static Color gridMajor(BuildContext ctx) =>
      Theme.of(ctx).brightness == Brightness.dark
          ? const Color(0xFF2A2A2A)
          : const Color(0xFFDDDDDD);
  static Color gridMinor(BuildContext ctx) =>
      Theme.of(ctx).brightness == Brightness.dark
          ? const Color(0xFF111111)
          : const Color(0xFFF0F0F0);
  static Color timeLabel(BuildContext ctx, {bool major = false}) => major
      ? (Theme.of(ctx).brightness == Brightness.dark
          ? const Color(0xFF666666)
          : const Color(0xFF888888))
      : (Theme.of(ctx).brightness == Brightness.dark
          ? const Color(0xFF2C2C2C)
          : const Color(0xFFCCCCCC));
}

// ══════════════════════════════════════════════════════════
// 视图枚举
// ══════════════════════════════════════════════════════════
enum _View { week, day }

// ══════════════════════════════════════════════════════════
// 主屏幕
// ══════════════════════════════════════════════════════════
class TimeLogScreen extends StatefulWidget {
  final String username;
  const TimeLogScreen({Key? key, required this.username}) : super(key: key);

  @override
  State<TimeLogScreen> createState() => _TimeLogScreenState();
}

class _TimeLogScreenState extends State<TimeLogScreen> {
  bool _isLoading = true;
  _View _view = _View.week;
  DateTime _focusedDate = DateTime.now();
  DateTime _currentWeekStart = _dayStart(DateTime.now()).subtract(Duration(days: DateTime.now().weekday - 1));
  bool _crossDay = false;

  List<TimeLogItem> _allLogs = [];
  List<PomodoroTag> _tags = [];
  List<PomodoroRecord> _allPomodoros = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // 增加一个 forceSync 参数，默认打开页面时不强制网络请求（为了秒开），点击刷新按钮时强制请求
  Future<void> _loadData({bool forceSync = false}) async {
    setState(() => _isLoading = true);

    // 🚀 核心修复：先触发云端同步，把新数据拉进本地 SQLite
    if (forceSync) {
      try {
        // 如果你还在调试“回声消除”机制，这里可以传 forceFullSync: true 试试
        await StorageService.syncData(widget.username,
            syncTimeLogs: true,
            syncTodos: false, // 可选，如果只想刷新日志的话
            syncCountdowns: false);
      } catch (e) {
        debugPrint("刷新下拉同步失败: $e");
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('同步失败: $e')));
        }
      }
    }

    // 同步完成后，再从本地读取最新合并后的数据
    final tags = await PomodoroService.getTags();
    final logs = await StorageService.getTimeLogs(widget.username);
    final pomodoros = await PomodoroService.getRecords();

    if (mounted) {
      setState(() {
        _tags = tags;
        _allLogs = logs.where((l) => !l.isDeleted).toList();
        _allPomodoros = pomodoros;
        _isLoading = false;
      });
    }
  }

  void _addLog(TimeLogItem log) {
    setState(() {
      _allLogs.removeWhere((l) => l.id == log.id);
      _allLogs.add(log);
    });
    StorageService.saveTimeLogs(widget.username, _allLogs, sync: true);
  }

  void _deleteLog(String id) async {
    await StorageService.deleteTimeLogGlobally(widget.username, id);
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    // ★ FIX 2: WillPopScope + AppBar 双重返回保障
    // AppBar 提供系统级返回按钮（日视图时显示），WillPopScope 拦截手势/硬件返回键
    return WillPopScope(
      onWillPop: () async {
        if (_view != _View.week) {
          setState(() => _view = _View.week);
          return false;
        }
        return true;
      },
      child: Scaffold(
        // ★ FIX 1: 背景色跟随主题
        backgroundColor: _TC.surface(context),
        appBar: AppBar(
          // 日视图显示返回按钮
          leading: _view == _View.day
              ? IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 18),
            onPressed: () => setState(() => _view = _View.week),
          )
              : null,
          title: _view == _View.week
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                        icon: const Icon(Icons.chevron_left),
                        onPressed: () => setState(() => _currentWeekStart = _currentWeekStart.subtract(const Duration(days: 7))),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                        onTap: () => setState(() => _currentWeekStart = _dayStart(DateTime.now()).subtract(Duration(days: DateTime.now().weekday - 1))),
                        child: Text(
                          '${DateFormat('MM/dd').format(_currentWeekStart)} - ${DateFormat('MM/dd').format(_currentWeekStart.add(const Duration(days: 6)))}',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                        )
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                        icon: const Icon(Icons.chevron_right),
                        onPressed: () => setState(() => _currentWeekStart = _currentWeekStart.add(const Duration(days: 7))),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                    ),
                  ],
                )
              : Text(
                  DateFormat('MM月dd日 补录').format(_focusedDate),
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
          actions: [
            if (_view == _View.day)
              IconButton(
                icon: const Icon(Icons.label_outline, size: 20),
                onPressed: _showTagManager,
                tooltip: '标签管理',
              ),
            IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              onPressed: () => _loadData(forceSync: true),
            ),
          ],
          backgroundColor: _TC.topBar(context),
          elevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _view == _View.week
                ? _WeekView(
                    weekStart: _currentWeekStart,
                    logs: _allLogs,
                    pomodoros: _allPomodoros,
                    tags: _tags,
                    onDayTap: (d) => setState(() {
                      _focusedDate = d;
                      _view = _View.day;
                    }),
                    onTagTap: _showTagDetail,
                    onManageTags: _showTagManager,
                    onAddLog: () => setState(() {
                      _focusedDate = DateTime.now();
                      _view = _View.day;
                    }),
                    onPomodoroTap: _showPomodoroDetail,
                    username: widget.username,
                  )
                : _DayView(
                    date: _focusedDate,
                    crossDay: _crossDay,
                    logs: _allLogs,
                    pomodoros: _allPomodoros,
                    tags: _tags,
                    onBack: () => setState(() => _view = _View.week),
                    onCrossDayChanged: (v) => setState(() => _crossDay = v),
                    onSaveLog: (log) {
                      _addLog(log);
                      setState(() => _view = _View.week);
                    },
                    onPomodoroTap: _showPomodoroDetail,
                  ),
      ),
    );
  }

  // ★ FIX 3: 番茄钟记录点击详情弹窗
  void _showPomodoroDetail(PomodoroRecord pom) {
    // PomodoroRecord 用 tagUuids (List)，取第一个关联标签显示
    final tag = pom.tagUuids.isNotEmpty
        ? _tags.cast<PomodoroTag?>().firstWhere(
            (t) => t?.uuid == pom.tagUuids.first,
            orElse: () => null)
        : null;
    final tc = tag != null ? hexColor(tag.color) : Colors.redAccent;
    final endMs = pom.endTime ?? (pom.startTime + pom.effectiveDuration * 1000);
    final dur = (endMs - pom.startTime) ~/ 60000;
    final startDt = DateTime.fromMillisecondsSinceEpoch(pom.startTime);
    final endDt = DateTime.fromMillisecondsSinceEpoch(endMs);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, MediaQuery.of(context).padding.bottom + 20),
        decoration: BoxDecoration(
          color: _TC.card(context),
          border: Border(
              top: BorderSide(
                  color: Colors.redAccent.withOpacity(0.4), width: 1.5)),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题行
              Row(children: [
                Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                        color: Colors.redAccent,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: Colors.redAccent, blurRadius: 6)
                        ])),
                const SizedBox(width: 10),
                Text('专注记录',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: _TC.text(context))),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withOpacity(0.1),
                    border:
                        Border.all(color: Colors.redAccent.withOpacity(0.4)),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('${dur}min',
                      style: const TextStyle(
                          fontSize: 12,
                          color: Colors.redAccent,
                          fontWeight: FontWeight.w700)),
                ),
                IconButton(
                    icon: Icon(Icons.close,
                        size: 18, color: _TC.textHint(context)),
                    onPressed: () => Navigator.pop(context)),
              ]),
              if (tag != null) ...[
                const SizedBox(height: 10),
                Row(children: [
                  Container(
                      width: 8,
                      height: 8,
                      decoration:
                          BoxDecoration(color: tc, shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Text(tag.name,
                      style: TextStyle(
                          fontSize: 13,
                          color: tc,
                          fontWeight: FontWeight.w600)),
                ]),
              ],
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                    child: _InfoCard(
                        label: '开始',
                        value: DateFormat('HH:mm').format(startDt),
                        sub: DateFormat('MM/dd').format(startDt))),
                const SizedBox(width: 10),
                Expanded(
                    child: _InfoCard(
                        label: '结束',
                        value: DateFormat('HH:mm').format(endDt),
                        sub: DateFormat('MM/dd').format(endDt))),
                const SizedBox(width: 10),
                Expanded(
                    child: _InfoCard(
                        label: '时长',
                        value: '${dur}min',
                        sub: (pom.isCompleted == true) ? '✓ 完成' : '手动停止')),
              ]),
            ]),
      ),
    );
  }

  void _showTagDetail(PomodoroTag tag) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TagDetailSheet(
        tag: tag,
        logs: _allLogs,
        pomodoros: _allPomodoros,
        onDelete: (id) {
          Navigator.pop(context);
          _deleteLog(id);
        },
      ),
    );
  }

  void _showTagManager() async {
    final updated = await showModalBottomSheet<List<PomodoroTag>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TagManagerSheet(tags: _tags),
    );
    if (updated != null) {
      await PomodoroService.saveTags(updated);
      setState(() => _tags = updated);
    }
  }
}

// ══════════════════════════════════════════════════════════
// 周视图
// ══════════════════════════════════════════════════════════
class _WeekView extends StatefulWidget {
  final DateTime weekStart;
  final List<TimeLogItem> logs;
  final List<PomodoroRecord> pomodoros;
  final List<PomodoroTag> tags;
  final void Function(DateTime) onDayTap;
  final void Function(PomodoroTag) onTagTap;
  final VoidCallback onManageTags;
  final VoidCallback onAddLog;
  final void Function(PomodoroRecord) onPomodoroTap;
  final String username;

  const _WeekView({
    required this.weekStart,
    required this.logs,
    required this.pomodoros,
    required this.tags,
    required this.onDayTap,
    required this.onTagTap,
    required this.onManageTags,
    required this.onAddLog,
    required this.onPomodoroTap,
    required this.username,
  });

  @override
  State<_WeekView> createState() => _WeekViewState();
}

class _WeekViewState extends State<_WeekView> {
  @override
  Widget build(BuildContext context) {
    final days = _weekDays(widget.weekStart);
    final todayMs = _dayStart(DateTime.now()).millisecondsSinceEpoch;
    final todayEndMs = todayMs + 86400000;
    final todayLogMin = widget.logs
        .where((l) => l.endTime > todayMs && l.startTime < todayEndMs)
        .fold(0, (s, l) => s + (l.endTime - l.startTime) ~/ 60000);
    final todayPomMin = widget.pomodoros
        .where((p) =>
            p.startTime < todayEndMs &&
            (p.endTime ?? p.startTime + p.effectiveDuration * 1000) > todayMs)
        .fold(0, (s, p) => s + p.effectiveDuration ~/ 60);
    final todayMin = todayLogMin + todayPomMin;
    final weekStart = days.first.millisecondsSinceEpoch;
    final weekEnd = days.last.millisecondsSinceEpoch + 86400000;

    return LayoutBuilder(builder: (ctx, outerConstraints) {
      // ── 宽屏判断（平板/电脑：>= 720px）────────────────
      final isWide = outerConstraints.maxWidth >= 720;
      // 右侧标签栏宽度（仅宽屏）
      const tagSidebarW = 160.0;
      // 实际网格可用宽度
      final gridAreaW = isWide
          ? outerConstraints.maxWidth - tagSidebarW
          : outerConstraints.maxWidth;

      Widget grid = _buildGrid(ctx, days, todayMin, gridAreaW);
      Widget? sidebar =
          isWide ? _buildTagSidebar(days, weekStart, weekEnd) : null;

      return Column(children: [
        // ── 顶部操作栏 ────────────────────────────────
        _buildTopBar(todayMin, isWide),
        // ── 日期头 + 网格（并排标签栏） ────────────────
        Expanded(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: grid),
          if (sidebar != null) sidebar,
        ])),
        // ── 窄屏时标签横向滚动条在底部 ─────────────────
        if (!isWide) _buildTagChips(days, weekStart, weekEnd),
      ]);
    });
  }

  // ── 顶部操作栏 ──────────────────────────────────────────
  Widget _buildTopBar(int todayMin, bool isWide) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      color: _TC.topBar(context),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF22C55E).withOpacity(0.12),
            border:
                Border.all(color: const Color(0xFF22C55E).withOpacity(0.35)),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text('今日 ${todayMin}min',
              style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF4ADE80),
                  fontWeight: FontWeight.w600)),
        ),
        const Spacer(),
        _TinyButton(label: '标签管理', onTap: widget.onManageTags),
        const SizedBox(width: 8),
        _TinyButton(label: '+ 补录', onTap: widget.onAddLog, primary: true),
        const SizedBox(width: 8),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
          onPressed: () async {
            // 1. 重置本地同步时间（让 last_sync_time 归 0）
            await StorageService.resetSyncTime(widget.username);

            // 2. 触发强制全量同步（绕过设备过滤，把云端所有数据强拉下来）
            await StorageService.syncData(
              widget.username,
              forceFullSync: true,
              syncTodos: true,
              syncCountdowns: true,
              syncTimeLogs: true,
            );

            // 3. 提示成功
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('🎉 数据强拉成功！请点击右上角的【刷新图标 ↻】查看界面'),
                duration: Duration(seconds: 4),
              ));
            }
          },
          child: const Text("🚑 一键恢复云端数据",
              style: TextStyle(color: Colors.white, fontSize: 12)),
        )
      ]),
    );
  }

  // ── 网格主体（日期头 + 时间轴 + 7列）──────────────────
  Widget _buildGrid(
      BuildContext ctx, List<DateTime> days, int todayMin, double availW) {
    const totalLogicalW = kTimeColW + kDayColW * 7;
    final scaleW = availW / totalLogicalW;
    final timeColW = kTimeColW * scaleW;
    final dayColW = kDayColW * scaleW;
    final accent = Theme.of(ctx).colorScheme.primary;
    final isDark = Theme.of(ctx).brightness == Brightness.dark;

    // 计算每天的总分钟数（TimeLog + 番茄钟合并）
    int _dayTotalMin(DateTime d) {
      final ds = _dayStart(d).millisecondsSinceEpoch;
      final de = ds + 86400000;
      final logMin = widget.logs
          .where((l) => l.endTime > ds && l.startTime < de)
          .fold(0, (s, l) => s + (l.endTime - l.startTime) ~/ 60000);
      final pomMin = widget.pomodoros
          .where((p) =>
              p.startTime < de &&
              (p.endTime ?? p.startTime + p.effectiveDuration * 1000) > ds)
          .fold(0, (s, p) {
        final pe = p.endTime ?? (p.startTime + p.effectiveDuration * 1000);
        return s + (min(pe, de) - max(p.startTime, ds)) ~/ 60000;
      });
      return logMin + pomMin;
    }

    return Column(children: [
      // 日期头
      Container(
        height: kHeaderH,
        color: _TC.topBar(ctx),
        child: Row(children: [
          SizedBox(width: timeColW),
          ...List.generate(7, (i) {
            final d = days[i];
            final isToday = DateFormat('yyyyMMdd').format(d) ==
                DateFormat('yyyyMMdd').format(DateTime.now());
            final dayMin = _dayTotalMin(d);
            return GestureDetector(
              onTap: () => widget.onDayTap(d),
              child: Container(
                width: dayColW,
                height: kHeaderH,
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: isToday ? accent.withOpacity(0.07) : null,
                  border: Border(
                      right:
                          BorderSide(color: _TC.divider(ctx).withOpacity(0.2))),
                ),
                // 使用 FittedBox 自动缩放适配，避免布局溢出报错
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('周${['一', '二', '三', '四', '五', '六', '日'][i]}',
                            style: TextStyle(
                                fontSize: 9,
                                color: isToday ? accent : _TC.textHint(ctx),
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5)),
                        Text('${d.day}',
                            style: TextStyle(
                                fontSize: 15,
                                color:
                                    isToday ? _TC.text(ctx) : _TC.textSub(ctx),
                                fontWeight: isToday
                                    ? FontWeight.w700
                                    : FontWeight.w400)),
                        if (dayMin > 0)
                          Text('${dayMin}m',
                              style: TextStyle(
                                  fontSize: 8, color: accent.withOpacity(0.5))),
                      ]),
                ),
              ),
            );
          }),
        ]),
      ),
      // 时间轴 + 7列
      Expanded(child: LayoutBuilder(builder: (ctx2, gridConstraints) {
        final availH = gridConstraints.maxHeight;
        final hourH = availH / 24;
        final totalH = hourH * 24;
        return SizedBox(
          height: totalH,
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // 时间轴
            SizedBox(
              width: timeColW,
              height: totalH,
              child: Stack(
                  clipBehavior: Clip.none,
                  children: List.generate(
                      24,
                      (h) => Positioned(
                            top: h * hourH - 8,
                            right: 4,
                            child: Text('${h.toString().padLeft(2, '0')}:00',
                                style: TextStyle(
                                  fontSize: (timeColW * 0.16).clamp(7.0, 11.0),
                                  color: _TC.timeLabel(ctx2, major: h % 6 == 0),
                                  fontWeight: FontWeight.w700,
                                )),
                          ))),
            ),
            // 7天列
            ...days.map((d) {
              final ds = _dayStart(d).millisecondsSinceEpoch;
              final de = ds + 86400000;
              final dayLogs = widget.logs
                  .where((l) => l.endTime > ds && l.startTime < de)
                  .toList();
              final dayPoms = widget.pomodoros.where((p) {
                final pe =
                    p.endTime ?? (p.startTime + p.effectiveDuration * 1000);
                return pe > ds && p.startTime < de;
              }).toList();

              return GestureDetector(
                onTap: () => widget.onDayTap(d),
                child: SizedBox(
                  width: dayColW,
                  height: totalH,
                  child: Stack(children: [
                    // 网格线 + TimeLogItem 块
                    CustomPaint(
                      size: Size(dayColW, totalH),
                      painter: _WeekColumnPainterV2(
                        dayLogs: dayLogs,
                        // ★ 把番茄钟也传入，在 painter 里铺满绘制
                        dayPoms: dayPoms,
                        tags: widget.tags,
                        dayStartMs: ds,
                        isDark: isDark,
                        hourH: hourH,
                      ),
                    ),
                    // 番茄钟点击层（透明覆盖在绘制好的色块上，仅处理点击）
                    ...dayPoms.map((pom) {
                      final pomEnd = pom.endTime ??
                          (pom.startTime + pom.effectiveDuration * 1000);
                      final rs = max(pom.startTime, ds);
                      final re = min(pomEnd, de);
                      final top = (rs - ds) / 3600000 * hourH;
                      final h =
                          ((re - rs) / 3600000 * hourH).clamp(3.0, 9999.0);
                      return Positioned(
                        top: top,
                        left: 0,
                        right: 0,
                        height: h,
                        child: GestureDetector(
                          onTap: () => widget.onPomodoroTap(pom),
                          behavior: HitTestBehavior.opaque,
                          child: const SizedBox.expand(),
                        ),
                      );
                    }),
                  ]),
                ),
              );
            }),
          ]),
        );
      })),
    ]);
  }

  // ── 宽屏右侧标签栏 ─────────────────────────────────────
  Widget _buildTagSidebar(List<DateTime> days, int weekStart, int weekEnd) {
    // 计算标签本周总分钟（TimeLog + 番茄钟）
    int _tagWeekMin(PomodoroTag t) {
      final logMin = widget.logs
          .where((l) =>
              l.tagUuids.contains(t.uuid) &&
              l.endTime > weekStart &&
              l.startTime < weekEnd)
          .fold(0, (s, l) => s + (l.endTime - l.startTime) ~/ 60000);
      final pomMin = widget.pomodoros
          .where((p) =>
              p.tagUuids.contains(t.uuid) &&
              p.startTime < weekEnd &&
              (p.endTime ?? p.startTime + p.effectiveDuration * 1000) >
                  weekStart)
          .fold(0, (s, p) => s + p.effectiveDuration ~/ 60);
      return logMin + pomMin;
    }

    return Container(
      width: 160,
      decoration: BoxDecoration(
        color: _TC.card(context),
        border: Border(left: BorderSide(color: _TC.divider(context))),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
          child: Text('本周标签',
              style: TextStyle(
                  fontSize: 10,
                  color: _TC.textHint(context),
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5)),
        ),
        Expanded(
            child: ListView(
          padding: const EdgeInsets.only(bottom: 8),
          children: widget.tags.map((t) {
            final tw = _tagWeekMin(t);
            final c = hexColor(t.color);
            return GestureDetector(
              onTap: () => widget.onTagTap(t),
              child: Container(
                margin: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: c.withOpacity(0.07),
                  border: Border.all(color: c.withOpacity(0.25)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(children: [
                  Container(
                      width: 8,
                      height: 8,
                      decoration:
                          BoxDecoration(color: c, shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(t.name,
                            style: TextStyle(
                                fontSize: 11,
                                color: c,
                                fontWeight: FontWeight.w700),
                            overflow: TextOverflow.ellipsis),
                        Text('${(tw / 60).toStringAsFixed(1)}h',
                            style: TextStyle(
                                fontSize: 13,
                                color: _TC.text(context),
                                fontWeight: FontWeight.w700)),
                      ])),
                ]),
              ),
            );
          }).toList(),
        )),
      ]),
    );
  }

  // ── 窄屏底部标签横向条 ─────────────────────────────────
  Widget _buildTagChips(List<DateTime> days, int weekStart, int weekEnd) {
    // 同样合并 TimeLog + 番茄钟
    int _tagWeekMin(PomodoroTag t) {
      final logMin = widget.logs
          .where((l) =>
              l.tagUuids.contains(t.uuid) &&
              l.endTime > weekStart &&
              l.startTime < weekEnd)
          .fold(0, (s, l) => s + (l.endTime - l.startTime) ~/ 60000);
      final pomMin = widget.pomodoros
          .where((p) =>
              p.tagUuids.contains(t.uuid) &&
              p.startTime < weekEnd &&
              (p.endTime ?? p.startTime + p.effectiveDuration * 1000) >
                  weekStart)
          .fold(0, (s, p) => s + p.effectiveDuration ~/ 60);
      return logMin + pomMin;
    }

    return Container(
      height: 56,
      color: _TC.topBar(context),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: widget.tags.map((t) {
          final tw = _tagWeekMin(t);
          final c = hexColor(t.color);
          return GestureDetector(
            onTap: () => widget.onTagTap(t),
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: c.withOpacity(0.08),
                border: Border.all(color: c.withOpacity(0.3)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(t.name,
                        style: TextStyle(
                            fontSize: 9,
                            color: c,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8)),
                    Text('${(tw / 60).toStringAsFixed(1)}h',
                        style: TextStyle(
                            fontSize: 11,
                            color: _TC.text(context),
                            fontWeight: FontWeight.w700)),
                  ]),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── 周视图单日列 ──────────────────────────────────────────
class _WeekDayColumn extends StatelessWidget {
  final DateTime date;
  final List<TimeLogItem> logs;
  final List<PomodoroRecord> pomodoros;
  final List<PomodoroTag> tags;
  final VoidCallback onTap;
  final void Function(PomodoroRecord) onPomodoroTap;

  const _WeekDayColumn({
    required this.date,
    required this.logs,
    required this.pomodoros,
    required this.tags,
    required this.onTap,
    required this.onPomodoroTap,
  });

  @override
  Widget build(BuildContext context) {
    final ds = _dayStart(date).millisecondsSinceEpoch;
    final de = ds + 86400000;
    final dayLogs =
        logs.where((l) => l.endTime > ds && l.startTime < de).toList();
    final dayPoms = pomodoros.where((p) {
      final pe = p.endTime ?? (p.startTime + p.effectiveDuration * 1000);
      return pe > ds && p.startTime < de;
    }).toList();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        height: kTotalH,
        child: Stack(children: [
          // 底层绘制
          CustomPaint(
            size: Size(kDayColW, kTotalH),
            painter: _WeekColumnPainter(
                dayLogs: dayLogs, tags: tags, dayStartMs: ds, isDark: isDark),
          ),
          // ★ FIX 3: 番茄钟可点击交互层（右侧细条，GestureDetector 覆盖）
          ...dayPoms.map((pom) {
            final pomEnd =
                pom.endTime ?? (pom.startTime + pom.effectiveDuration * 1000);
            final rs = max(pom.startTime, ds);
            final re = min(pomEnd, de);
            final top = (rs - ds) / 3600000 * kHourHeight + kVPad;
            final h = ((re - rs) / 3600000 * kHourHeight).clamp(4.0, 9999.0);
            return Positioned(
              top: top,
              right: 0,
              width: 14,
              height: h,
              child: GestureDetector(
                onTap: () => onPomodoroTap(pom),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withOpacity(0.55),
                    borderRadius:
                        const BorderRadius.horizontal(left: Radius.circular(2)),
                  ),
                ),
              ),
            );
          }),
        ]),
      ),
    );
  }
}

class _WeekColumnPainter extends CustomPainter {
  final List<TimeLogItem> dayLogs;
  final List<PomodoroTag> tags;
  final int dayStartMs;
  final bool isDark;

  _WeekColumnPainter(
      {required this.dayLogs,
      required this.tags,
      required this.dayStartMs,
      required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final dayEndMs = dayStartMs + 86400000;
    for (int h = 0; h <= 24; h++) {
      final y = kVPad + h * kHourHeight;
      canvas.drawLine(
          Offset(0, y),
          Offset(size.width, y),
          Paint()
            ..color = h % 6 == 0
                ? (isDark ? const Color(0xFF2A2A2A) : const Color(0xFFDDDDDD))
                : (isDark ? const Color(0xFF111111) : const Color(0xFFF0F0F0))
            ..strokeWidth = 0.5);
    }
    for (final log in dayLogs) {
      final rs = max(log.startTime, dayStartMs);
      final re = min(log.endTime, dayEndMs);
      final top = (rs - dayStartMs) / 3600000 * kHourHeight + kVPad;
      final bottom = (re - dayStartMs) / 3600000 * kHourHeight + kVPad;
      if (bottom <= top + 1) continue;
      Color c = const Color(0xFF3B82F6).withOpacity(0.45);
      if (log.tagUuids.isNotEmpty) {
        final t = tags.cast<PomodoroTag?>().firstWhere(
            (t) => log.tagUuids.contains(t?.uuid),
            orElse: () => null);
        if (t != null) c = hexColor(t.color, opacity: 0.45);
      }
      canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTRB(0, top + 0.5, 3, bottom - 0.5),
              const Radius.circular(2)),
          Paint()..color = c.withOpacity(0.9));
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTRB(3, top + 0.5, size.width - 1, bottom - 0.5),
              const Radius.circular(3)),
          Paint()..color = c.withOpacity(0.28));
    }
  }

  @override
  bool shouldRepaint(covariant _WeekColumnPainter old) =>
      old.isDark != isDark || old.dayLogs.length != dayLogs.length;
}

// ── 周视图新版 Painter（动态 hourH，无 kVPad）────────────
class _WeekColumnPainterV2 extends CustomPainter {
  final List<TimeLogItem> dayLogs;
  final List<PomodoroRecord> dayPoms; // ★ 新增
  final List<PomodoroTag> tags;
  final int dayStartMs;
  final bool isDark;
  final double hourH;

  _WeekColumnPainterV2({
    required this.dayLogs,
    this.dayPoms = const [], // ★ 默认空
    required this.tags,
    required this.dayStartMs,
    required this.isDark,
    required this.hourH,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final dayEndMs = dayStartMs + 86400000;

    // ── 网格线 ──────────────────────────────────────────
    for (int h = 0; h <= 24; h++) {
      final y = h * hourH;
      canvas.drawLine(
          Offset(0, y),
          Offset(size.width, y),
          Paint()
            ..color = h % 6 == 0
                ? (isDark ? const Color(0xFF2A2A2A) : const Color(0xFFDDDDDD))
                : (isDark ? const Color(0xFF111111) : const Color(0xFFF2F2F2))
            ..strokeWidth = 0.5);
    }
    canvas.drawLine(
      Offset(size.width - 0.5, 0),
      Offset(size.width - 0.5, size.height),
      Paint()
        ..color = isDark ? const Color(0xFF1A1A1A) : const Color(0xFFE5E5E5)
        ..strokeWidth = 0.5,
    );

    // ── 番茄钟块（铺满全列，半透明，左侧红色条）─────────
    for (final pom in dayPoms) {
      final pomEnd =
          pom.endTime ?? (pom.startTime + pom.effectiveDuration * 1000);
      final rs = max(pom.startTime, dayStartMs);
      final re = min(pomEnd, dayEndMs);
      final top = (rs - dayStartMs) / 3600000 * hourH;
      final bottom = (re - dayStartMs) / 3600000 * hourH;
      if (bottom <= top + 1) continue;

      // 找关联标签颜色，有标签用标签色，否则用红色
      Color c = Colors.redAccent.withOpacity(0.45);
      if (pom.tagUuids.isNotEmpty) {
        final t = tags.cast<PomodoroTag?>().firstWhere(
            (t) => pom.tagUuids.contains(t?.uuid),
            orElse: () => null);
        if (t != null) c = hexColor(t.color, opacity: 0.45);
      }

      // 左侧细色条
      canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTRB(0, top + 0.5, 3, bottom - 0.5),
              const Radius.circular(2)),
          Paint()..color = c.withOpacity(0.9));
      // 主体填充
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTRB(3, top + 0.5, size.width - 1, bottom - 0.5),
              const Radius.circular(3)),
          Paint()..color = c.withOpacity(0.22));
    }

    // ── TimeLogItem 块（叠加在番茄钟上，更不透明）──────
    for (final log in dayLogs) {
      final rs = max(log.startTime, dayStartMs);
      final re = min(log.endTime, dayEndMs);
      final top = (rs - dayStartMs) / 3600000 * hourH;
      final bottom = (re - dayStartMs) / 3600000 * hourH;
      if (bottom <= top + 1) continue;

      Color c = const Color(0xFF3B82F6).withOpacity(0.45);
      if (log.tagUuids.isNotEmpty) {
        final t = tags.cast<PomodoroTag?>().firstWhere(
            (t) => log.tagUuids.contains(t?.uuid),
            orElse: () => null);
        if (t != null) c = hexColor(t.color, opacity: 0.45);
      }
      canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTRB(0, top + 0.5, 3, bottom - 0.5),
              const Radius.circular(2)),
          Paint()..color = c.withOpacity(0.9));
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTRB(3, top + 0.5, size.width - 1, bottom - 0.5),
              const Radius.circular(3)),
          Paint()..color = c.withOpacity(0.35));
    }
  }

  @override
  bool shouldRepaint(covariant _WeekColumnPainterV2 old) =>
      old.isDark != isDark ||
      old.hourH != hourH ||
      old.dayLogs.length != dayLogs.length ||
      old.dayPoms.length != dayPoms.length;
}

// ── 时间轴 ────────────────────────────────────────────────
class _TimeAxis extends StatelessWidget {
  const _TimeAxis();
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: kTimeColW,
      height: kTotalH,
      child: Stack(
          children: List.generate(
              24,
              (h) => Positioned(
                    top: kVPad + h * kHourHeight - 8,
                    right: 8,
                    child: Text('${h.toString().padLeft(2, '0')}:00',
                        style: TextStyle(
                            fontSize: 9,
                            color: _TC.timeLabel(context, major: h % 6 == 0),
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5)),
                  ))),
    );
  }
}

// ══════════════════════════════════════════════════════════
// 日视图（补录）
// ══════════════════════════════════════════════════════════
class _DayView extends StatefulWidget {
  final DateTime date;
  final bool crossDay;
  final List<TimeLogItem> logs;
  final List<PomodoroRecord> pomodoros;
  final List<PomodoroTag> tags;
  final VoidCallback onBack;
  final ValueChanged<bool> onCrossDayChanged;
  final void Function(TimeLogItem) onSaveLog;
  final void Function(PomodoroRecord) onPomodoroTap;

  const _DayView({
    required this.date,
    required this.crossDay,
    required this.logs,
    required this.pomodoros,
    required this.tags,
    required this.onBack,
    required this.onCrossDayChanged,
    required this.onSaveLog,
    required this.onPomodoroTap,
  });

  @override
  State<_DayView> createState() => _DayViewState();
}

// ══════════════════════════════════════════════════════════
// 日视图（补录）- 状态类
// ══════════════════════════════════════════════════════════
class _DayViewState extends State<_DayView> {
  int _minutesPerBlock = 15;
  int? _dragStart, _dragEnd;
  String? _selectedTagId;

  @override
  void initState() {
    super.initState();
    if (widget.tags.isNotEmpty) _selectedTagId = widget.tags.first.uuid;
  }

  int get _bpr => 60 ~/ _minutesPerBlock;
  int get _totalBlocks => 24 * _bpr;

  int? _getIndex(Offset pos, double width, double hourH) {
    final bw = width / _bpr;
    final y = pos.dy;
    if (y < 0 || y > 24 * hourH) return null;
    final hr = (y / hourH).floor().clamp(0, 23);
    final col = (pos.dx / bw).floor().clamp(0, _bpr - 1);
    return (hr * _bpr + col).clamp(0, _totalBlocks - 1);
  }

  DateTime get _gridStart => widget.crossDay
      ? _dayStart(widget.date.subtract(const Duration(days: 1)))
      : _dayStart(widget.date);

  int get _ss =>
      _dragStart != null && _dragEnd != null ? min(_dragStart!, _dragEnd!) : 0;
  int get _se =>
      _dragStart != null && _dragEnd != null ? max(_dragStart!, _dragEnd!) : 0;
  int get _durMin =>
      _dragStart != null ? (_se - _ss + 1) * _minutesPerBlock : 0;

  void _openEntry() {
    if (_dragStart == null) return;
    final gs = _gridStart;
    final st = gs.add(Duration(minutes: _ss * _minutesPerBlock));
    final en = gs.add(Duration(minutes: (_se + 1) * _minutesPerBlock));
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LogEntrySheet(
        initialStart: st,
        initialEnd: en,
        initialTagId: _selectedTagId,
        tags: widget.tags,
        onSave: (log) {
          Navigator.pop(context);
          widget.onSaveLog(log);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _buildCrossDayBar(),
      Expanded(
          child: Row(children: [
        // 使用 LayoutBuilder 获取屏幕剩余高度，实现一屏铺满无滚动
        Expanded(child: LayoutBuilder(builder: (ctx, constraints) {
          final availH = constraints.maxHeight;
          final hourH = availH / 24;
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: kTimeColW,
              height: availH,
              child: Stack(
                clipBehavior: Clip.none,
                children: List.generate(
                    24,
                    (h) => Positioned(
                          top: h * hourH - 8,
                          right: 8,
                          child: Text('${h.toString().padLeft(2, '0')}:00',
                              style: TextStyle(
                                  fontSize: 9,
                                  color:
                                      _TC.timeLabel(context, major: h % 6 == 0),
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5)),
                        )),
              ),
            ),
            Expanded(child: _buildGrid(hourH, availH)),
          ]);
        })),
        _buildTagSidebar(),
      ])),
      if (_dragStart != null) _buildBottomBar(),
    ]);
  }

  Widget _buildCrossDayBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      color: _TC.topBar(context),
      child: Row(children: [
        Text('从昨晚开始',
            style: TextStyle(fontSize: 11, color: _TC.textSub(context))),
        Transform.scale(
          scale: 0.78,
          alignment: Alignment.centerLeft,
          child: Switch(
            value: widget.crossDay,
            onChanged: widget.onCrossDayChanged,
            activeColor: Theme.of(context).colorScheme.primary,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        if (widget.crossDay) ...[
          const SizedBox(width: 2),
          Text(
              '${DateFormat('MM/dd').format(_gridStart)} → ${DateFormat('MM/dd').format(widget.date)}',
              style: TextStyle(fontSize: 10, color: _TC.textHint(context))),
        ],
        const Spacer(),
        ...([5, 10, 15, 30].map((m) => Padding(
              padding: const EdgeInsets.only(left: 4),
              child: GestureDetector(
                onTap: () => setState(() {
                  _minutesPerBlock = m;
                  _dragStart = null;
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _minutesPerBlock == m
                        ? Theme.of(context).colorScheme.primary
                        : _TC.btnBg(context),
                    border: Border.all(
                        color: _minutesPerBlock == m
                            ? Theme.of(context).colorScheme.primary
                            : _TC.btnBorder(context)),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('${m}分',
                      style: TextStyle(
                          fontSize: 10,
                          color: _minutesPerBlock == m
                              ? Colors.white
                              : _TC.textSub(context),
                          fontWeight: FontWeight.w600)),
                ),
              ),
            ))),
      ]),
    );
  }

  Widget _buildGrid(double hourH, double totalH) {
    return LayoutBuilder(builder: (ctx, constraints) {
      final w = constraints.maxWidth;
      final isDark = Theme.of(ctx).brightness == Brightness.dark;
      final accent = Theme.of(ctx).colorScheme.primary;
      final selTag = widget.tags
          .cast<PomodoroTag?>()
          .firstWhere((t) => t?.uuid == _selectedTagId, orElse: () => null);

      return GestureDetector(
        onPanStart: (d) {
          final idx = _getIndex(d.localPosition, w, hourH);
          if (idx != null)
            setState(() {
              _dragStart = idx;
              _dragEnd = idx;
            });
        },
        onPanUpdate: (d) {
          final idx = _getIndex(d.localPosition, w, hourH);
          if (idx != null) setState(() => _dragEnd = idx);
        },
        onTapDown: (d) {
          final idx = _getIndex(d.localPosition, w, hourH);
          if (idx != null)
            setState(() {
              _dragStart = idx;
              _dragEnd = idx;
            });
        },
        child: Stack(children: [
          SizedBox(
            height: totalH,
            child: CustomPaint(
              size: Size(w, totalH),
              painter: _DayGridPainter(
                minutesPerBlock: _minutesPerBlock, dragStart: _dragStart, dragEnd: _dragEnd,
                logs: widget.logs, tags: widget.tags, gridStart: _gridStart,
                selColor: selTag != null ? hexColor(selTag.color, opacity: 0.48) : accent.withOpacity(0.45),
                isDark: isDark,
                hourH: hourH,
              ),
            ),
          ),
          ..._pomodoroTapTargets(w, hourH),
        ]),
      );
    });
  }

  List<Widget> _pomodoroTapTargets(double width, double hourH) {
    final gsMs = _gridStart.millisecondsSinceEpoch;
    final geMs = gsMs + 86400000;
    
    List<Widget> targets = [];
    
    for (final pom in widget.pomodoros) {
      final pomEnd = pom.endTime ?? (pom.startTime + pom.effectiveDuration * 1000);
      if (pomEnd <= gsMs || pom.startTime >= geMs) continue;
      
      final rs = max(pom.startTime, gsMs);
      final re = min(pomEnd, geMs);
      
      final double startFraction = (rs - gsMs) / 3600000;
      final double endFraction = (re - gsMs) / 3600000;
      
      int sH = startFraction.floor();
      int eH = endFraction.floor();
      if (eH > sH && endFraction == eH.toDouble()) {
        eH--;
      }
      
      PomodoroTag? tag;
      if (pom.tagUuids.isNotEmpty) {
        tag = widget.tags.cast<PomodoroTag?>().firstWhere((t) => pom.tagUuids.contains(t?.uuid), orElse: () => null);
      }
      
      final isDark = Theme.of(context).brightness == Brightness.dark;
      final Color baseColor = tag != null ? hexColor(tag.color) : Colors.redAccent;
      final Color fillColor = baseColor.withOpacity(isDark ? 0.35 : 0.45);
      final Color markColor = baseColor.withOpacity(0.85);

      for (int h = sH; h <= eH; h++) {
        double hStart = max(h.toDouble(), startFraction);
        double hEnd = min((h + 1).toDouble(), endFraction);
        
        double left = (hStart - h) * width;
        double right = (hEnd - h) * width;
        double boxWidth = right - left;
        if (boxWidth <= 0) continue;
        
        targets.add(Positioned(
          top: h * hourH + 1,
          left: left + 1,
          width: boxWidth - 1,
          height: hourH - 2,
          child: GestureDetector(
            onTap: () => widget.onPomodoroTap(pom),
            behavior: HitTestBehavior.opaque,
            child: Container(
              decoration: BoxDecoration(
                color: fillColor,
                borderRadius: BorderRadius.circular(4),
                border: Border(left: BorderSide(color: markColor, width: 3)),
              ),
              child: boxWidth > 20 ? Icon(Icons.timer_outlined, size: 12, color: markColor) : null,
            ),
          ),
        ));
      }
    }
    return targets;
  }

  Widget _buildTagSidebar() {
    return Container(
      width: 78,
      color: _TC.topBar(context),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text('TAGS',
              style: TextStyle(
                  fontSize: 8, color: _TC.textHint(context), letterSpacing: 2)),
        ),
        Expanded(
            child: ListView.builder(
          itemCount: widget.tags.length,
          itemBuilder: (ctx, i) {
            final t = widget.tags[i];
            final c = hexColor(t.color);
            final sel = _selectedTagId == t.uuid;
            return GestureDetector(
              onTap: () => setState(() => _selectedTagId = t.uuid),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: sel ? c.withOpacity(0.2) : _TC.card(ctx),
                  border: Border.all(
                      color: sel ? c : c.withOpacity(0.2),
                      width: sel ? 1.5 : 1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(children: [
                  Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          boxShadow:
                              sel ? [BoxShadow(color: c, blurRadius: 5)] : [])),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(t.name,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 9,
                            color: sel ? c : _TC.textSub(ctx),
                            fontWeight:
                                sel ? FontWeight.w700 : FontWeight.w400),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ),
                ]),
              ),
            );
          },
        )),
      ]),
    );
  }

  Widget _buildBottomBar() {
    final gs = _gridStart;
    final st = gs.add(Duration(minutes: _ss * _minutesPerBlock));
    final en = gs.add(Duration(minutes: (_se + 1) * _minutesPerBlock));
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 14, 16, MediaQuery.of(context).padding.bottom + 14),
      decoration: BoxDecoration(
        color: _TC.card(context),
        border: Border(top: BorderSide(color: _TC.divider(context))),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, -4))
        ],
      ),
      child: Row(children: [
        Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
              Text('$_durMin 分钟',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: _TC.text(context))),
              Text(
                  '${DateFormat('HH:mm').format(st)} → ${DateFormat('HH:mm').format(en)}',
                  style: TextStyle(fontSize: 11, color: _TC.textSub(context))),
            ])),
        TextButton(
          onPressed: () => setState(() {
            _dragStart = null;
            _dragEnd = null;
          }),
          child: Text('取消', style: TextStyle(color: _TC.textSub(context))),
        ),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: _openEntry,
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            elevation: 0,
          ),
          child:
              const Text('详情录入', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════
// 补录网格绘制
// ══════════════════════════════════════════════════════════
class _DayGridPainter extends CustomPainter {
  final int minutesPerBlock;
  final int? dragStart, dragEnd;
  final List<TimeLogItem> logs;
  final List<PomodoroTag> tags;
  final DateTime gridStart;
  final Color selColor;
  final bool isDark;
  final double hourH;

  _DayGridPainter({
    required this.minutesPerBlock,
    this.dragStart,
    this.dragEnd,
    required this.logs,
    required this.tags,
    required this.gridStart,
    required this.selColor,
    required this.isDark,
    required this.hourH,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bpr = 60 ~/ minutesPerBlock;
    final bw = size.width / bpr;
    final gsMs = gridStart.millisecondsSinceEpoch;
    final geMs = gsMs + 86400000;

    final mj = Paint()
      ..color = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFDDDDDD)
      ..strokeWidth = 0.5;
    final mn = Paint()
      ..color = isDark ? const Color(0xFF0E0E0E) : const Color(0xFFF2F2F2)
      ..strokeWidth = 0.5;

    for (int h = 0; h <= 24; h++) {
      final y = h * hourH;
      canvas.drawLine(
          Offset(0, y), Offset(size.width, y), h % 6 == 0 ? mj : mn);
    }
    for (int c = 0; c <= bpr; c++) {
      canvas.drawLine(
          Offset(c * bw, 0), Offset(c * bw, size.height), c % 4 == 0 ? mj : mn);
    }

    for (final log in logs) {
      if (log.endTime <= gsMs || log.startTime >= geMs) continue;
      final sMs = max(log.startTime, gsMs);
      final eMs = min(log.endTime, geMs);
      final sIdx = (sMs - gsMs) ~/ (60000 * minutesPerBlock);
      final eIdx = ((eMs - gsMs - 1) ~/ (60000 * minutesPerBlock))
          .clamp(0, 24 * bpr - 1);
      PomodoroTag? tag;
      if (log.tagUuids.isNotEmpty) {
        tag = tags.cast<PomodoroTag?>().firstWhere(
            (t) => log.tagUuids.contains(t?.uuid),
            orElse: () => null);
      }
      final fill = tag != null
          ? hexColor(tag.color, opacity: isDark ? 0.14 : 0.1)
          : (isDark ? const Color(0x18888888) : const Color(0x0F000000));
      final bar = tag != null
          ? hexColor(tag.color, opacity: 0.5)
          : (isDark ? const Color(0x44888888) : const Color(0x44000000));
      _fill(canvas, sIdx, eIdx, bpr, bw, Paint()..color = fill);
      for (int i = sIdx; i <= eIdx; i++) {
        canvas.drawRect(
            Rect.fromLTWH(i % bpr * bw + 1, i ~/ bpr * hourH + 1, 3, hourH - 2),
            Paint()..color = bar);
      }
    }

    if (dragStart != null && dragEnd != null) {
      _fill(canvas, min(dragStart!, dragEnd!), max(dragStart!, dragEnd!), bpr,
          bw, Paint()..color = selColor);
    }

    final now = DateTime.now();
    if (now.isAfter(gridStart) &&
        now.isBefore(gridStart.add(const Duration(days: 1)))) {
      final y = now.difference(gridStart).inMinutes / 60 * hourH;
      canvas.drawLine(
          Offset(0, y),
          Offset(size.width, y),
          Paint()
            ..color = Colors.redAccent.withOpacity(0.7)
            ..strokeWidth = 1.5);
      canvas.drawCircle(Offset(3, y), 3, Paint()..color = Colors.redAccent);
    }
  }

  void _fill(Canvas canvas, int s, int e, int bpr, double bw, Paint p) {
    for (int i = s; i <= e; i++) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(
                  i % bpr * bw + 1, i ~/ bpr * hourH + 1, bw - 2, hourH - 2),
              const Radius.circular(3)),
          p);
    }
  }

  @override
  bool shouldRepaint(covariant _DayGridPainter old) => true;
}

// ══════════════════════════════════════════════════════════
// 补录详情面板
// ══════════════════════════════════════════════════════════
class _LogEntrySheet extends StatefulWidget {
  final DateTime initialStart, initialEnd;
  final String? initialTagId;
  final List<PomodoroTag> tags;
  final void Function(TimeLogItem) onSave;

  const _LogEntrySheet(
      {required this.initialStart,
      required this.initialEnd,
      this.initialTagId,
      required this.tags,
      required this.onSave});

  @override
  State<_LogEntrySheet> createState() => _LogEntrySheetState();
}

class _LogEntrySheetState extends State<_LogEntrySheet> {
  late DateTime _start, _end;
  late String? _tagId;
  late TextEditingController _tc;

  @override
  void initState() {
    super.initState();
    _start = widget.initialStart;
    _end = widget.initialEnd;
    _tagId = widget.initialTagId;
    final tag = widget.tags
        .cast<PomodoroTag?>()
        .firstWhere((t) => t?.uuid == _tagId, orElse: () => null);
    _tc = TextEditingController(text: tag?.name ?? '');
  }

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  String _durLabel() {
    final m = _end.difference(_start).inMinutes;
    if (m <= 0) return '--';
    return m >= 60 ? '${m ~/ 60}h ${m % 60}m' : '${m}m';
  }

  Future<void> _pickTime(bool isStart) async {
    final t = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(isStart ? _start : _end));
    if (t == null) return;
    setState(() {
      if (isStart)
        _start =
            DateTime(_start.year, _start.month, _start.day, t.hour, t.minute);
      else
        _end = DateTime(_end.year, _end.month, _end.day, t.hour, t.minute);
    });
  }

  Future<void> _pickDate(bool isStart) async {
    final d = await showDatePicker(
        context: context,
        initialDate: isStart ? _start : _end,
        firstDate: DateTime(2020),
        lastDate: DateTime.now().add(const Duration(days: 1)));
    if (d == null) return;
    setState(() {
      if (isStart)
        _start = DateTime(d.year, d.month, d.day, _start.hour, _start.minute);
      else
        _end = DateTime(d.year, d.month, d.day, _end.hour, _end.minute);
    });
  }

  void _save() {
    if (!_end.isAfter(_start)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('结束时间必须晚于开始时间')));
      return;
    }
    final tag = widget.tags
        .cast<PomodoroTag?>()
        .firstWhere((t) => t?.uuid == _tagId, orElse: () => null);
    widget.onSave(TimeLogItem(
      title: _tc.text.isNotEmpty ? _tc.text : (tag?.name ?? '未命名补录'),
      tagUuids: _tagId != null ? [_tagId!] : [],
      startTime: _start.millisecondsSinceEpoch,
      endTime: _end.millisecondsSinceEpoch,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          left: 20,
          right: 20,
          top: 20),
      decoration: BoxDecoration(
        color: _TC.card(context),
        border: Border(top: BorderSide(color: _TC.divider(context))),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text('补录事件',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: _TC.text(context))),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF22C55E).withOpacity(0.12),
                  border: Border.all(
                      color: const Color(0xFF22C55E).withOpacity(0.35)),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(_durLabel(),
                    style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF4ADE80),
                        fontWeight: FontWeight.w600)),
              ),
            ]),
            const SizedBox(height: 16),
            Text('CATEGORY',
                style: TextStyle(
                    fontSize: 9,
                    color: _TC.textHint(context),
                    letterSpacing: 2)),
            const SizedBox(height: 8),
            Wrap(
                spacing: 8,
                runSpacing: 6,
                children: widget.tags.map((t) {
                  final c = hexColor(t.color);
                  final sel = _tagId == t.uuid;
                  return GestureDetector(
                    onTap: () => setState(() {
                      _tagId = t.uuid;
                      _tc.text = t.name;
                    }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: sel ? c.withOpacity(0.2) : c.withOpacity(0.06),
                        border: Border.all(color: sel ? c : c.withOpacity(0.3)),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(t.name,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: sel ? c : c.withOpacity(0.7))),
                    ),
                  );
                }).toList()),
            const SizedBox(height: 16),
            Text('TITLE',
                style: TextStyle(
                    fontSize: 9,
                    color: _TC.textHint(context),
                    letterSpacing: 2)),
            const SizedBox(height: 6),
            TextField(
              controller: _tc,
              style: TextStyle(color: _TC.text(context), fontSize: 13),
              decoration: InputDecoration(
                hintText: '事件名称（留空使用标签名）',
                hintStyle:
                    TextStyle(color: _TC.textHint(context), fontSize: 13),
                filled: true,
                fillColor: _TC.inputFill(context),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: _TC.divider(context))),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: _TC.divider(context))),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: accent)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                  child: _TimePickerCard(
                      label: '开始时间',
                      dt: _start,
                      onTapTime: () => _pickTime(true),
                      onTapDate: () => _pickDate(true))),
              const SizedBox(width: 10),
              Expanded(
                  child: _TimePickerCard(
                      label: '结束时间',
                      dt: _end,
                      onTapTime: () => _pickTime(false),
                      onTapDate: () => _pickDate(false))),
            ]),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: const Text('保存记录',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
    );
  }
}

class _TimePickerCard extends StatelessWidget {
  final String label;
  final DateTime dt;
  final VoidCallback onTapTime, onTapDate;
  const _TimePickerCard(
      {required this.label,
      required this.dt,
      required this.onTapTime,
      required this.onTapDate});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTapTime,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: _TC.inputFill(context),
            border: Border.all(color: _TC.divider(context)),
            borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: TextStyle(
                  fontSize: 9, color: _TC.textHint(context), letterSpacing: 1)),
          const SizedBox(height: 4),
          GestureDetector(
            onTap: onTapDate,
            child: Text(DateFormat('MM月dd日').format(dt),
                style: TextStyle(fontSize: 11, color: _TC.textSub(context))),
          ),
          const SizedBox(height: 4),
          Row(children: [
            Text(DateFormat('HH:mm').format(dt),
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: _TC.text(context))),
            const SizedBox(width: 6),
            Icon(Icons.access_time, size: 14, color: _TC.textHint(context)),
          ]),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════
// 标签详情面板
// ══════════════════════════════════════════════════════════
class _TagDetailSheet extends StatelessWidget {
  final PomodoroTag tag;
  final List<TimeLogItem> logs;
  final List<PomodoroRecord> pomodoros; // ★ 新增
  final void Function(String) onDelete;

  const _TagDetailSheet({
    required this.tag,
    required this.logs,
    this.pomodoros = const [], // ★ 默认空，向后兼容
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    // ── 合并 TimeLogItem + PomodoroRecord 统一为展示用记录 ──
    final tagLogs = logs.where((l) => l.tagUuids.contains(tag.uuid)).toList();
    final tagPoms =
        pomodoros.where((p) => p.tagUuids.contains(tag.uuid)).toList();

    // 统一成一个列表，按 startTime 降序
    // 用 Map 方便后面渲染，区分类型
    final allRecords = <_TagRecord>[
      ...tagLogs.map((l) => _TagRecord(
            isPomodoro: false,
            title: l.title.isNotEmpty ? l.title : tag.name,
            startTime: l.startTime,
            endTime: l.endTime,
            durationMin: (l.endTime - l.startTime) ~/ 60000,
            id: l.id,
          )),
      ...tagPoms.map((p) {
        final end = p.endTime ?? (p.startTime + p.effectiveDuration * 1000);
        return _TagRecord(
          isPomodoro: true,
          title: (p.todoTitle?.isNotEmpty ?? false) ? p.todoTitle! : tag.name,
          startTime: p.startTime,
          endTime: end,
          durationMin: (end - p.startTime) ~/ 60000,
          id: p.uuid,
          isCompleted: p.isCompleted,
        );
      }),
    ]..sort((a, b) => b.startTime.compareTo(a.startTime));

    final totalMin = allRecords.fold(0, (s, r) => s + r.durationMin);
    final avgMin = allRecords.isEmpty ? 0 : totalMin ~/ allRecords.length;
    final maxMin = allRecords.isEmpty
        ? 0
        : allRecords.map((r) => r.durationMin).reduce(max);
    final c = hexColor(tag.color);
    final chartData = allRecords.reversed.take(14).toList();

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      decoration: BoxDecoration(
        color: _TC.card(context),
        border: Border(top: BorderSide(color: c.withOpacity(0.35), width: 1.5)),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: c, blurRadius: 8)])),
              const SizedBox(width: 10),
              Text(tag.name,
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: _TC.text(context))),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                    color: c.withOpacity(0.12),
                    border: Border.all(color: c.withOpacity(0.3)),
                    borderRadius: BorderRadius.circular(20)),
                child: Text('${(totalMin / 60).toStringAsFixed(1)}h 累计',
                    style: TextStyle(
                        fontSize: 11, color: c, fontWeight: FontWeight.w600)),
              ),
              IconButton(
                  icon:
                      Icon(Icons.close, color: _TC.textHint(context), size: 20),
                  onPressed: () => Navigator.pop(context)),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              _StatCard(
                  label: '记录次数', value: '${allRecords.length}次', color: c),
              const SizedBox(width: 10),
              _StatCard(label: '平均时长', value: '${avgMin}min', color: c),
              const SizedBox(width: 10),
              _StatCard(label: '最长一次', value: '${maxMin}min', color: c),
            ]),
            const SizedBox(height: 20),
            Text('DURATION TREND',
                style: TextStyle(
                    fontSize: 9,
                    color: _TC.textHint(context),
                    letterSpacing: 2)),
            const SizedBox(height: 8),
            if (chartData.length >= 2)
              _MiniLineChart(
                  data: chartData.map((r) => r.durationMin).toList(),
                  color: c,
                  height: 80)
            else
              Text('数据采集中...',
                  style: TextStyle(fontSize: 11, color: _TC.textHint(context))),
            const SizedBox(height: 16),
            Text('START TIME TREND',
                style: TextStyle(
                    fontSize: 9,
                    color: _TC.textHint(context),
                    letterSpacing: 2)),
            const SizedBox(height: 8),
            if (chartData.length >= 2)
              _MiniLineChart(
                data: chartData.map((r) {
                  final d = DateTime.fromMillisecondsSinceEpoch(r.startTime);
                  return d.hour * 60 + d.minute;
                }).toList(),
                color: _TC.textSub(context),
                height: 55,
              ),
            const SizedBox(height: 16),
            Text('RECENT RECORDS',
                style: TextStyle(
                    fontSize: 9,
                    color: _TC.textHint(context),
                    letterSpacing: 2)),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: allRecords.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (ctx, i) {
                  final r = allRecords[i];
                  final startDt =
                      DateTime.fromMillisecondsSinceEpoch(r.startTime);
                  final endDt = DateTime.fromMillisecondsSinceEpoch(r.endTime);
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: _TC.inputFill(ctx),
                      border: Border(
                          left: BorderSide(
                              color: r.isPomodoro ? Colors.redAccent : c,
                              width: 3)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(children: [
                      if (r.isPomodoro) ...[
                        Icon(Icons.timer_outlined,
                            size: 12, color: Colors.redAccent.withOpacity(0.6)),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(r.title,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: _TC.text(ctx),
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text(
                                '${DateFormat('MM/dd').format(startDt)} ${DateFormat('HH:mm').format(startDt)} → ${DateFormat('HH:mm').format(endDt)}',
                                style: TextStyle(
                                    fontSize: 10, color: _TC.textHint(ctx))),
                          ])),
                      Text('${r.durationMin}min',
                          style: TextStyle(
                              fontSize: 13,
                              color: r.isPomodoro ? Colors.redAccent : c,
                              fontWeight: FontWeight.w700)),
                      // 只有 TimeLogItem 才能删除（番茄钟不在这里管理）
                      if (!r.isPomodoro)
                        IconButton(
                          icon: Icon(Icons.delete_outline,
                              color: Colors.red.withOpacity(0.55), size: 18),
                          onPressed: () => onDelete(r.id),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        )
                      else
                        const SizedBox(width: 40),
                    ]),
                  );
                },
              ),
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
          ]),
    );
  }
}

// 统一记录模型（供 _TagDetailSheet 内部使用）
class _TagRecord {
  final bool isPomodoro;
  final String title;
  final int startTime;
  final int endTime;
  final int durationMin;
  final String id;
  final bool isCompleted;

  const _TagRecord({
    required this.isPomodoro,
    required this.title,
    required this.startTime,
    required this.endTime,
    required this.durationMin,
    required this.id,
    this.isCompleted = false,
  });
}

// ── 折线图 ────────────────────────────────────────────────
class _MiniLineChart extends StatelessWidget {
  final List<int> data;
  final Color color;
  final double height;
  const _MiniLineChart(
      {required this.data, required this.color, this.height = 80});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
        height: height,
        child:
            CustomPaint(painter: _LineChartPainter(data: data, color: color)));
  }
}

class _LineChartPainter extends CustomPainter {
  final List<int> data;
  final Color color;
  _LineChartPainter({required this.data, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;
    final minV = data.reduce(min).toDouble();
    final maxV = data.reduce(max).toDouble();
    final range = (maxV - minV) < 1 ? 1.0 : maxV - minV;
    final pts = List.generate(
        data.length,
        (i) => Offset(
              (i / (data.length - 1)) * (size.width - 20) + 10,
              size.height -
                  10 -
                  ((data[i] - minV) / range) * (size.height - 20),
            ));
    final path = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (int i = 1; i < pts.length; i++) path.lineTo(pts[i].dx, pts[i].dy);
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round);
    for (final p in pts) {
      canvas.drawCircle(
          p,
          4,
          Paint()
            ..color = color.withOpacity(0.15)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
      canvas.drawCircle(p, 3, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter old) => true;
}

class _StatCard extends StatelessWidget {
  final String label, value;
  final Color color;
  const _StatCard(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
        child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
          color: _TC.inputFill(context),
          borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: TextStyle(fontSize: 10, color: _TC.textHint(context))),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w700, color: color)),
      ]),
    ));
  }
}

class _InfoCard extends StatelessWidget {
  final String label, value, sub;
  const _InfoCard(
      {required this.label, required this.value, required this.sub});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
          color: _TC.inputFill(context),
          borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: TextStyle(
                fontSize: 9, color: _TC.textHint(context), letterSpacing: 1)),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _TC.text(context))),
        Text(sub, style: TextStyle(fontSize: 10, color: _TC.textSub(context))),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════
// 标签管理面板
// ══════════════════════════════════════════════════════════
class _TagManagerSheet extends StatefulWidget {
  final List<PomodoroTag> tags;
  const _TagManagerSheet({required this.tags});

  @override
  State<_TagManagerSheet> createState() => _TagManagerSheetState();
}

class _TagManagerSheetState extends State<_TagManagerSheet> {
  late List<PomodoroTag> _list;
  final _nc = TextEditingController();
  String _newColor = kPalette[0];

  @override
  void initState() {
    super.initState();
    _list = widget.tags
        .map((t) => PomodoroTag(uuid: t.uuid, name: t.name, color: t.color))
        .toList();
  }

  @override
  void dispose() {
    _nc.dispose();
    super.dispose();
  }

  void _add() {
    if (_nc.text.trim().isEmpty) return;
    setState(() {
      _list.add(PomodoroTag(
          uuid: 'tag_${DateTime.now().millisecondsSinceEpoch}',
          name: _nc.text.trim(),
          color: _newColor));
      _nc.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          left: 20,
          right: 20,
          top: 20),
      decoration: BoxDecoration(
        color: _TC.card(context),
        border: Border(top: BorderSide(color: _TC.divider(context))),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text('标签管理',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: _TC.text(context))),
              const Spacer(),
              IconButton(
                  icon:
                      Icon(Icons.close, color: _TC.textHint(context), size: 20),
                  onPressed: () => Navigator.pop(context)),
            ]),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _list.length,
                itemBuilder: (ctx, i) {
                  final t = _list[i];
                  final c = hexColor(t.color);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      Container(
                          width: 10,
                          height: 10,
                          decoration:
                              BoxDecoration(color: c, shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: TextEditingController(text: t.name)
                            ..selection =
                                TextSelection.collapsed(offset: t.name.length),
                          onChanged: (v) => _list[i] = PomodoroTag(
                              uuid: t.uuid, name: v, color: t.color),
                          style: TextStyle(fontSize: 12, color: _TC.text(ctx)),
                          decoration: InputDecoration(
                            isDense: true,
                            filled: true,
                            fillColor: _TC.inputFill(ctx),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide:
                                    BorderSide(color: _TC.divider(ctx))),
                            enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide:
                                    BorderSide(color: _TC.divider(ctx))),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Wrap(
                          spacing: 3,
                          children: kPalette
                              .map((pc) => GestureDetector(
                                    onTap: () => setState(() => _list[i] =
                                        PomodoroTag(
                                            uuid: t.uuid,
                                            name: t.name,
                                            color: pc)),
                                    child: Container(
                                        width: 14,
                                        height: 14,
                                        decoration: BoxDecoration(
                                            color: hexColor(pc),
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                                color: t.color == pc
                                                    ? Colors.white
                                                    : Colors.transparent,
                                                width: 1.5))),
                                  ))
                              .toList()),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () => setState(() => _list.removeAt(i)),
                        child: Icon(Icons.delete_outline,
                            color: Colors.red.withOpacity(0.55), size: 18),
                      ),
                    ]),
                  );
                },
              ),
            ),
            Divider(color: _TC.divider(context), height: 24),
            Text('NEW TAG',
                style: TextStyle(
                    fontSize: 9,
                    color: _TC.textHint(context),
                    letterSpacing: 2)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _nc,
                  onSubmitted: (_) => _add(),
                  style: TextStyle(fontSize: 13, color: _TC.text(context)),
                  decoration: InputDecoration(
                    hintText: '标签名称',
                    hintStyle: TextStyle(color: _TC.textHint(context)),
                    isDense: true,
                    filled: true,
                    fillColor: _TC.inputFill(context),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: _TC.divider(context))),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: _TC.divider(context))),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _add,
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent.withOpacity(0.15),
                  foregroundColor: accent,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('+ 添加',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ]),
            const SizedBox(height: 8),
            Wrap(
                spacing: 6,
                children: kPalette.map((pc) {
                  final cc = hexColor(pc);
                  return GestureDetector(
                    onTap: () => setState(() => _newColor = pc),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                          color: cc,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: _newColor == pc
                                  ? Colors.white
                                  : Colors.transparent,
                              width: 2),
                          boxShadow: _newColor == pc
                              ? [BoxShadow(color: cc, blurRadius: 6)]
                              : []),
                    ),
                  );
                }).toList()),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context, _list),
                style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0),
                child: const Text('保存',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              ),
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 4),
          ]),
    );
  }
}

// ── 按钮组件 ──────────────────────────────────────────────
class _TinyButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool primary;
  const _TinyButton(
      {required this.label, required this.onTap, this.primary = false});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: primary ? accent : _TC.btnBg(context),
          border: Border.all(
              color: primary ? Colors.transparent : _TC.btnBorder(context)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: primary ? FontWeight.w700 : FontWeight.w400,
              color: primary ? Colors.white : _TC.textSub(context),
            )),
      ),
    );
  }
}
