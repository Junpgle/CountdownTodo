import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models.dart';
import '../storage_service.dart';
import '../services/pomodoro_service.dart';
import 'dart:ui' as ui;

part 'time_log_components.dart';

// ══════════════════════════════════════════════════════════
// 常量
// ══════════════════════════════════════════════════════════
const double kTimeAxisW = 46.0; // 左侧时间标签列宽（固定）
const double kRowH = 52.0; // 每行（1小时）高度
const int kColsPerH = 10; // 每小时几列（60/6=10）→ 24×10=240格
const int kMinsPerCol = 6; // 每列代表多少分钟（60/10=6）
const int kTotalRows = 24; // 总行数（24小时）
const int kTotalCols = 24 * kColsPerH; // 总列数 = 240

// 周视图常量
const double kWeekTimeW = 44.0;
const double kWeekDayW = 100.0;

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
// 主题色助手
// ══════════════════════════════════════════════════════════
class _TC {
  static Color surface(BuildContext c) => Theme.of(c).colorScheme.surface;

  static Color card(BuildContext c) => Theme.of(c).brightness == Brightness.dark
      ? const Color(0xFF1A1A1A)
      : Theme.of(c).colorScheme.surfaceVariant;

  static Color topBar(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark
          ? const Color(0xFF0D0D0D)
          : Theme.of(c).colorScheme.surface;

  static Color inputFill(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark
          ? const Color(0xFF181818)
          : Theme.of(c).colorScheme.surfaceVariant;

  static Color text(BuildContext c) => Theme.of(c).colorScheme.onSurface;

  static Color textSub(BuildContext c) =>
      Theme.of(c).colorScheme.onSurface.withOpacity(0.55);

  static Color textHint(BuildContext c) =>
      Theme.of(c).colorScheme.onSurface.withOpacity(0.28);

  static Color divider(BuildContext c) => Theme.of(c).dividerColor;

  static Color btnBg(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark
          ? const Color(0xFF222222)
          : Theme.of(c).colorScheme.surfaceVariant;

  static Color btnBorder(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark
          ? const Color(0xFF333333)
          : Theme.of(c).dividerColor;

  static Color timeLabel(BuildContext c, {bool major = false}) => major
      ? (Theme.of(c).brightness == Brightness.dark
          ? const Color(0xFF888888)
          : const Color(0xFF666666))
      : (Theme.of(c).brightness == Brightness.dark
          ? const Color(0xFF444444)
          : const Color(0xFFAAAAAA));
}

// ══════════════════════════════════════════════════════════
// 视图枚举
// ══════════════════════════════════════════════════════════
enum _ViewMode { week, day }

enum _DayMode { view, edit }

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
  _ViewMode _view = _ViewMode.week;
  _DayMode _dayMode = _DayMode.view;
  DateTime _focusedDate = DateTime.now();
  late DateTime _weekStart;
  bool _crossDay = false;

  List<TimeLogItem> _allLogs = [];
  List<PomodoroTag> _tags = [];
  List<PomodoroRecord> _allPomodoros = [];

  // 打开编辑面板
  void _editTimeLog(TimeLogItem log) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LogEntrySheet(
        initialStart: DateTime.fromMillisecondsSinceEpoch(log.startTime),
        initialEnd: DateTime.fromMillisecondsSinceEpoch(log.endTime),
        tags: _tags,
        existingLog: log,
        onSave: (updatedLog) {
          Navigator.pop(context);
          _addLog(updatedLog);
        },
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _weekStart = _dayStart(DateTime.now())
        .subtract(Duration(days: DateTime.now().weekday - 1));
    _loadData();
  }

  Future<void> _loadData({bool forceSync = false}) async {
    setState(() => _isLoading = true);
    if (forceSync) {
      try {
        await StorageService.syncData(widget.username,
            syncTimeLogs: true, syncTodos: false, syncCountdowns: false);
      } catch (e) {
        if (mounted)
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('同步失败: $e')));
      }
    }
    final tags = await PomodoroService.getTags();
    final logs = await StorageService.getTimeLogs(widget.username);
    final pomodoros = await PomodoroService.getRecords();
    if (mounted)
      setState(() {
        _tags = tags;
        _allLogs = logs.where((l) => !l.isDeleted).toList();
        _allPomodoros = pomodoros;
        _isLoading = false;
      });
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

  void _goDay(DateTime d, {_DayMode mode = _DayMode.view}) => setState(() {
        _focusedDate = d;
        _view = _ViewMode.day;
        _dayMode = mode;
      });

  void _goWeek() => setState(() => _view = _ViewMode.week);

  Widget _buildTitle() {
    if (_view == _ViewMode.week) {
      final we = _weekStart.add(const Duration(days: 6));
      return Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
            icon: const Icon(Icons.chevron_left),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => setState(() =>
                _weekStart = _weekStart.subtract(const Duration(days: 7)))),
        const SizedBox(width: 4),
        GestureDetector(
          onTap: () => setState(() => _weekStart = _dayStart(DateTime.now())
              .subtract(Duration(days: DateTime.now().weekday - 1))),
          child: Text(
              '${DateFormat('MM/dd').format(_weekStart)} - ${DateFormat('MM/dd').format(we)}',
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: 4),
        IconButton(
            icon: const Icon(Icons.chevron_right),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => setState(
                () => _weekStart = _weekStart.add(const Duration(days: 7)))),
      ]);
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton(
          icon: const Icon(Icons.chevron_left, size: 20),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          onPressed: () => setState(() =>
              _focusedDate = _focusedDate.subtract(const Duration(days: 1)))),
      GestureDetector(
        onTap: () async {
          final p = await showDatePicker(
              context: context,
              initialDate: _focusedDate,
              firstDate: DateTime(2020),
              lastDate: DateTime.now().add(const Duration(days: 1)));
          if (p != null) setState(() => _focusedDate = p);
        },
        child: Text(
            DateFormat('MM月dd日').format(_focusedDate) +
                (_dayMode == _DayMode.edit ? ' · 补录' : ''),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      IconButton(
          icon: const Icon(Icons.chevron_right, size: 20),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          onPressed: () => setState(
              () => _focusedDate = _focusedDate.add(const Duration(days: 1)))),
    ]);
  }

  List<Widget> _buildActions() {
    final acts = <Widget>[];
    if (_view == _ViewMode.day) {
      acts.add(TextButton(
        onPressed: () => setState(() => _dayMode =
            _dayMode == _DayMode.view ? _DayMode.edit : _DayMode.view),
        child: Text(_dayMode == _DayMode.view ? '补录' : '查看',
            style: TextStyle(
                fontSize: 13,
                color: _dayMode == _DayMode.view
                    ? Theme.of(context).colorScheme.primary
                    : _TC.textSub(context))),
      ));
      if (_dayMode == _DayMode.edit)
        acts.add(IconButton(
            icon: const Icon(Icons.label_outline, size: 20),
            onPressed: _showTagManager,
            tooltip: '标签管理'));
    }
    acts.add(IconButton(
        icon: const Icon(Icons.refresh, size: 20),
        onPressed: () => _loadData(forceSync: true)));
    return acts;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_view != _ViewMode.week) {
          _goWeek();
          return false;
        }
        return true;
      },
      child: Scaffold(
        backgroundColor: _TC.surface(context),
        appBar: AppBar(
          leading: _view == _ViewMode.day
              ? IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                  onPressed: _goWeek)
              : null,
          title: _buildTitle(),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(34),
            child: Container(
              height: 34,
              color: _TC.topBar(context),
              child:
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                _ViewTab(
                    label: '周',
                    selected: _view == _ViewMode.week,
                    onTap: () {
                      if (_view != _ViewMode.week) _goWeek();
                    }),
                const SizedBox(width: 6),
                _ViewTab(
                    label: '日',
                    selected: _view == _ViewMode.day,
                    onTap: () {
                      if (_view != _ViewMode.day)
                        _goDay(DateTime.now(), mode: _DayMode.view);
                    }),
              ]),
            ),
          ),
          actions: _buildActions(),
          backgroundColor: _TC.topBar(context),
          elevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _view == _ViewMode.week
                ? _WeekView(
                    weekStart: _weekStart,
                    logs: _allLogs,
                    pomodoros: _allPomodoros,
                    tags: _tags,
                    onDayTap: (d) => _goDay(d),
                    onTagTap: _showTagDetail,
                    onManageTags: _showTagManager,
                    onAddLog: () => _goDay(DateTime.now(), mode: _DayMode.edit),
                    onPomodoroTap: _showPomodoroDetail,
                    onTimeLogTap: _showTimeLogDetail,
                    username: widget.username)
                : _dayMode == _DayMode.view
                    ? _DayGridView(
                        date: _focusedDate,
                        logs: _allLogs,
                        pomodoros: _allPomodoros,
                        tags: _tags,
                        onPomodoroTap: _showPomodoroDetail,
                        onTimeLogTap: _showTimeLogDetail,
                        onSwitchEdit: () =>
                            setState(() => _dayMode = _DayMode.edit))
                    : _DayView(
                        date: _focusedDate,
                        crossDay: _crossDay,
                        logs: _allLogs,
                        pomodoros: _allPomodoros,
                        tags: _tags,
                        onBack: _goWeek,
                        onCrossDayChanged: (v) => setState(() => _crossDay = v),
                        onSaveLog: (log) {
                          _addLog(log);
                          setState(() => _dayMode = _DayMode.view);
                        },
                        onPomodoroTap: _showPomodoroDetail,
                        onDeleteLog: _deleteLog),
      ),
    );
  }

  // ── 共用弹窗容器 ─────────────────────────────────────
  Widget _sheet(Color borderColor, Widget child) => Container(
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, MediaQuery.of(context).padding.bottom + 20),
        decoration: BoxDecoration(
            color: _TC.card(context),
            border: Border(top: BorderSide(color: borderColor, width: 1.5)),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20))),
        child: child,
      );

  void _showPomodoroDetail(PomodoroRecord pom) {
    final tag = pom.tagUuids.isNotEmpty
        ? _tags.cast<PomodoroTag?>().firstWhere(
            (t) => t?.uuid == pom.tagUuids.first,
            orElse: () => null)
        : null;
    final tc = tag != null ? hexColor(tag.color) : Colors.redAccent;
    final endMs = pom.endTime ?? (pom.startTime + pom.effectiveDuration * 1000);
    final dur = (endMs - pom.startTime) ~/ 60000;
    final s = DateTime.fromMillisecondsSinceEpoch(pom.startTime);
    final e = DateTime.fromMillisecondsSinceEpoch(endMs);
    showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) => _sheet(
              Colors.redAccent.withOpacity(0.4),
              Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      _glow(Colors.redAccent),
                      const SizedBox(width: 10),
                      Text('专注记录',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: _TC.text(context))),
                      const Spacer(),
                      _pill('${dur}min', Colors.redAccent),
                      IconButton(
                          icon: Icon(Icons.close,
                              size: 18, color: _TC.textHint(context)),
                          onPressed: () => Navigator.pop(context)),
                    ]),
                    if (tag != null) ...[
                      const SizedBox(height: 10),
                      _tagRow(tag.name, tc)
                    ],
                    const SizedBox(height: 16),
                    Row(children: [
                      Expanded(
                          child: _InfoCard(
                              label: '开始',
                              value: DateFormat('HH:mm').format(s),
                              sub: DateFormat('MM/dd').format(s))),
                      const SizedBox(width: 10),
                      Expanded(
                          child: _InfoCard(
                              label: '结束',
                              value: DateFormat('HH:mm').format(e),
                              sub: DateFormat('MM/dd').format(e))),
                      const SizedBox(width: 10),
                      Expanded(
                          child: _InfoCard(
                              label: '时长',
                              value: '${dur}min',
                              sub:
                                  (pom.isCompleted == true) ? '✓ 完成' : '手动停止')),
                    ]),
                  ]),
            ));
  }

  void _showTimeLogDetail(TimeLogItem log) {
    final tag = log.tagUuids.isNotEmpty
        ? _tags.cast<PomodoroTag?>().firstWhere(
            (t) => t?.uuid == log.tagUuids.first,
            orElse: () => null)
        : null;
    final c = tag != null ? hexColor(tag.color) : const Color(0xFF3B82F6);
    final dur = (log.endTime - log.startTime) ~/ 60000;
    final s = DateTime.fromMillisecondsSinceEpoch(log.startTime);
    final e = DateTime.fromMillisecondsSinceEpoch(log.endTime);
    showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) => _sheet(
              c.withOpacity(0.4),
              Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      _glow(c),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Text(
                              log.title.isNotEmpty
                                  ? log.title
                                  : (tag?.name ?? '补录记录'),
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: _TC.text(context)),
                              overflow: TextOverflow.ellipsis)),
                      _pill('${dur}min', c),
                      IconButton(
                          icon: Icon(Icons.close,
                              size: 18, color: _TC.textHint(context)),
                          onPressed: () => Navigator.pop(context)),
                    ]),
                    if (tag != null) ...[
                      const SizedBox(height: 10),
                      _tagRow(tag.name, c)
                    ],
                    const SizedBox(height: 16),
                    Row(children: [
                      Expanded(
                          child: _InfoCard(
                              label: '开始',
                              value: DateFormat('HH:mm').format(s),
                              sub: DateFormat('MM/dd').format(s))),
                      const SizedBox(width: 10),
                      Expanded(
                          child: _InfoCard(
                              label: '结束',
                              value: DateFormat('HH:mm').format(e),
                              sub: DateFormat('MM/dd').format(e))),
                      const SizedBox(width: 10),
                      Expanded(
                          child: _InfoCard(
                              label: '时长', value: '${dur}min', sub: '手动补录')),
                    ]),
                    const SizedBox(height: 20),
                    Row(children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _editTimeLog(log);
                          },
                          icon: const Icon(Icons.edit_note, size: 18),
                          label: const Text('编辑记录',
                              style: TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600)),
                          style: OutlinedButton.styleFrom(
                              foregroundColor: _TC.text(context),
                              side: BorderSide(color: _TC.divider(context)),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12))),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _deleteLog(log.id);
                          },
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: const Text('删除记录',
                              style: TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600)),
                          style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red,
                              side: BorderSide(
                                  color: Colors.red.withOpacity(0.4)),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12))),
                        ),
                      ),
                    ]),
                  ]),
            ));
  }

  Widget _glow(Color c) => Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
          color: c,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: c, blurRadius: 6)]));

  Widget _pill(String t, Color c) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
          color: c.withOpacity(0.1),
          border: Border.all(color: c.withOpacity(0.4)),
          borderRadius: BorderRadius.circular(20)),
      child: Text(t,
          style:
              TextStyle(fontSize: 12, color: c, fontWeight: FontWeight.w700)));

  Widget _tagRow(String name, Color c) => Row(children: [
        Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text(name,
            style:
                TextStyle(fontSize: 13, color: c, fontWeight: FontWeight.w600)),
      ]);

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
            }));
  }

  void _showTagManager() async {
    final updated = await showModalBottomSheet<List<PomodoroTag>>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _TagManagerSheet(tags: _tags));
    if (updated != null) {
      await PomodoroService.saveTags(updated);
      setState(() => _tags = updated);
    }
  }
}

// ══════════════════════════════════════════════════════════
// 视图切换 Tab
// ══════════════════════════════════════════════════════════
class _ViewTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ViewTab(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 5),
            decoration: BoxDecoration(
                color: selected ? accent.withOpacity(0.12) : Colors.transparent,
                border: Border.all(
                    color: selected
                        ? accent.withOpacity(0.4)
                        : Colors.transparent),
                borderRadius: BorderRadius.circular(18)),
            child: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                    color: selected ? accent : _TC.textSub(context)))));
  }
}

// ══════════════════════════════════════════════════════════
// 周视图
// ══════════════════════════════════════════════════════════
class _WeekView extends StatelessWidget {
  final DateTime weekStart;
  final List<TimeLogItem> logs;
  final List<PomodoroRecord> pomodoros;
  final List<PomodoroTag> tags;
  final void Function(DateTime) onDayTap;
  final void Function(PomodoroTag) onTagTap;
  final VoidCallback onManageTags, onAddLog;
  final void Function(PomodoroRecord) onPomodoroTap;
  final void Function(TimeLogItem) onTimeLogTap;
  final String username;

  const _WeekView(
      {required this.weekStart,
      required this.logs,
      required this.pomodoros,
      required this.tags,
      required this.onDayTap,
      required this.onTagTap,
      required this.onManageTags,
      required this.onAddLog,
      required this.onPomodoroTap,
      required this.onTimeLogTap,
      required this.username});

  int _rangeMin(int from, int to) {
    final lm = logs
        .where((l) => l.endTime > from && l.startTime < to)
        .fold(0, (s, l) => s + (l.endTime - l.startTime) ~/ 60000);
    final pm = pomodoros
        .where((p) =>
            p.startTime < to &&
            (p.endTime ?? p.startTime + p.effectiveDuration * 1000) > from)
        .fold(0, (s, p) => s + p.effectiveDuration ~/ 60);
    return lm + pm;
  }

  @override
  Widget build(BuildContext context) {
    final days = _weekDays(weekStart);
    final todayMs = _dayStart(DateTime.now()).millisecondsSinceEpoch;
    final todayMin = _rangeMin(todayMs, todayMs + 86400000);
    final wStart0 = days.first.millisecondsSinceEpoch;
    final wEnd0 = days.last.millisecondsSinceEpoch + 86400000;

    return LayoutBuilder(builder: (ctx, outer) {
      final isWide = outer.maxWidth >= 720;
      return Column(children: [
        _buildTopBar(ctx, todayMin),
        Expanded(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
              child:
                  _buildGrid(ctx, days, outer.maxWidth - (isWide ? 160.0 : 0))),
          if (isWide) _buildTagSidebar(ctx, wStart0, wEnd0),
        ])),
        if (!isWide) _buildTagChips(ctx, wStart0, wEnd0),
      ]);
    });
  }

  Widget _buildTopBar(BuildContext ctx, int todayMin) => Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
        color: _TC.topBar(ctx),
        child: Row(children: [
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                  color: const Color(0xFF22C55E).withOpacity(0.12),
                  border: Border.all(
                      color: const Color(0xFF22C55E).withOpacity(0.35)),
                  borderRadius: BorderRadius.circular(20)),
              child: Text('今日 ${todayMin}min',
                  style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF4ADE80),
                      fontWeight: FontWeight.w600))),
          const Spacer(),
          _TinyButton(label: '标签管理', onTap: onManageTags),
          const SizedBox(width: 8),
          _TinyButton(label: '+ 补录', onTap: onAddLog, primary: true),
          const SizedBox(width: 8),
          Builder(
              builder: (bCtx) => ElevatedButton(
                    style:
                        ElevatedButton.styleFrom(backgroundColor: Colors.green),
                    onPressed: () async {
                      await StorageService.resetSyncTime(username);
                      await StorageService.syncData(username,
                          forceFullSync: true,
                          syncTodos: true,
                          syncCountdowns: true,
                          syncTimeLogs: true);
                      if (bCtx.mounted)
                        ScaffoldMessenger.of(bCtx).showSnackBar(const SnackBar(
                            content: Text('🎉 数据强拉成功！请点击右上角的【刷新图标 ↻】查看界面'),
                            duration: Duration(seconds: 4)));
                    },
                    child: const Text('🚑 一键恢复',
                        style: TextStyle(color: Colors.white, fontSize: 12)),
                  )),
        ]),
      );

  Widget _buildGrid(BuildContext ctx, List<DateTime> days, double availW) {
    const totalW = kWeekTimeW + kWeekDayW * 7;
    final scale = availW / totalW;
    final tW = kWeekTimeW * scale;
    final dW = kWeekDayW * scale;
    final accent = Theme.of(ctx).colorScheme.primary;
    final isDark = Theme.of(ctx).brightness == Brightness.dark;

    int dayMin(DateTime d) {
      final ds = _dayStart(d).millisecondsSinceEpoch;
      return _rangeMin(ds, ds + 86400000);
    }

    return Column(children: [
      Container(
          height: 52,
          color: _TC.topBar(ctx),
          child: Row(children: [
            SizedBox(width: tW),
            ...List.generate(7, (i) {
              final d = days[i];
              final isToday = DateFormat('yyyyMMdd').format(d) ==
                  DateFormat('yyyyMMdd').format(DateTime.now());
              final dm = dayMin(d);
              return GestureDetector(
                  onTap: () => onDayTap(d),
                  child: Container(
                      width: dW,
                      height: 52,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                          color: isToday ? accent.withOpacity(0.07) : null,
                          border: Border(
                              right: BorderSide(
                                  color: _TC.divider(ctx).withOpacity(0.2)))),
                      child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                    '周${[
                                      '一',
                                      '二',
                                      '三',
                                      '四',
                                      '五',
                                      '六',
                                      '日'
                                    ][i]}',
                                    style: TextStyle(
                                        fontSize: 9,
                                        color: isToday
                                            ? accent
                                            : _TC.textHint(ctx),
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.5)),
                                Text('${d.day}',
                                    style: TextStyle(
                                        fontSize: 15,
                                        color: isToday
                                            ? _TC.text(ctx)
                                            : _TC.textSub(ctx),
                                        fontWeight: isToday
                                            ? FontWeight.w700
                                            : FontWeight.w400)),
                                if (dm > 0)
                                  Text('${dm}m',
                                      style: TextStyle(
                                          fontSize: 8,
                                          color: accent.withOpacity(0.5))),
                              ]))));
            }),
          ])),
      Expanded(child: LayoutBuilder(builder: (ctx2, gc) {
        final hourH = gc.maxHeight / 24;
        final totalH = hourH * 24;
        return SizedBox(
            height: totalH,
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                  width: tW,
                  height: totalH,
                  child: Stack(
                      clipBehavior: Clip.none,
                      children: List.generate(
                          24,
                          (h) => Positioned(
                              top: h * hourH - 8,
                              right: 4,
                              child: Text('${h.toString().padLeft(2, '0')}',
                                  style: TextStyle(
                                      fontSize: (tW * 0.16).clamp(7.0, 11.0),
                                      color: _TC.timeLabel(ctx2,
                                          major: h % 6 == 0),
                                      fontWeight: FontWeight.w700)))))),
              ...days.map((d) {
                final ds = _dayStart(d).millisecondsSinceEpoch;
                final de = ds + 86400000;
                final dLogs = logs
                    .where((l) => l.endTime > ds && l.startTime < de)
                    .toList();
                final dPoms = pomodoros.where((p) {
                  final pe =
                      p.endTime ?? (p.startTime + p.effectiveDuration * 1000);
                  return pe > ds && p.startTime < de;
                }).toList();
                return SizedBox(
                    width: dW,
                    height: totalH,
                    child: Stack(children: [
                      CustomPaint(
                          size: Size(dW, totalH),
                          painter: _WeekColPainter(
                              dayLogs: dLogs,
                              dayPoms: dPoms,
                              tags: tags,
                              dayStartMs: ds,
                              isDark: isDark,
                              hourH: hourH)),
                      ...dPoms.map((pom) {
                        final pe = pom.endTime ??
                            (pom.startTime + pom.effectiveDuration * 1000);
                        final rs = max(pom.startTime, ds);
                        final re = min(pe, de);
                        final top = (rs - ds) / 3600000 * hourH;
                        final h =
                            ((re - rs) / 3600000 * hourH).clamp(3.0, 9999.0);
                        return Positioned(
                            top: top,
                            left: 0,
                            right: 0,
                            height: h,
                            child: GestureDetector(
                                onTap: () => onPomodoroTap(pom),
                                behavior: HitTestBehavior.opaque,
                                child: const SizedBox.expand()));
                      }),
                      ...dLogs.map((log) {
                        final rs = max(log.startTime, ds);
                        final re = min(log.endTime, de);
                        final top = (rs - ds) / 3600000 * hourH;
                        final h =
                            ((re - rs) / 3600000 * hourH).clamp(3.0, 9999.0);
                        return Positioned(
                            top: top,
                            left: 0,
                            right: 0,
                            height: h,
                            child: GestureDetector(
                                onTap: () => onTimeLogTap(log),
                                behavior: HitTestBehavior.opaque,
                                child: const SizedBox.expand()));
                      }),
                    ]));
              }),
            ]));
      })),
    ]);
  }

  Widget _buildTagSidebar(BuildContext ctx, int ws, int we) => Container(
      width: 160,
      decoration: BoxDecoration(
          color: _TC.card(ctx),
          border: Border(left: BorderSide(color: _TC.divider(ctx)))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
            child: Text('本周标签',
                style: TextStyle(
                    fontSize: 10,
                    color: _TC.textHint(ctx),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5))),
        Expanded(
            child: ListView(
                padding: const EdgeInsets.only(bottom: 8),
                children: tags.map((t) {
                  int tw = logs
                      .where((l) =>
                          l.tagUuids.contains(t.uuid) &&
                          l.endTime > ws &&
                          l.startTime < we)
                      .fold(
                          0, (s, l) => s + (l.endTime - l.startTime) ~/ 60000);
                  tw += pomodoros
                      .where((p) =>
                          p.tagUuids.contains(t.uuid) &&
                          p.startTime < we &&
                          (p.endTime ??
                                  p.startTime + p.effectiveDuration * 1000) >
                              ws)
                      .fold(0, (s, p) => s + p.effectiveDuration ~/ 60);
                  final c = hexColor(t.color);
                  return GestureDetector(
                      onTap: () => onTagTap(t),
                      child: Container(
                          margin: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                              color: c.withOpacity(0.07),
                              border: Border.all(color: c.withOpacity(0.25)),
                              borderRadius: BorderRadius.circular(10)),
                          child: Row(children: [
                            Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                    color: c, shape: BoxShape.circle)),
                            const SizedBox(width: 8),
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                          color: _TC.text(ctx),
                                          fontWeight: FontWeight.w700)),
                                ])),
                          ])));
                }).toList())),
      ]));

  Widget _buildTagChips(BuildContext ctx, int ws, int we) => Container(
      height: 52,
      color: _TC.topBar(ctx),
      child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          children: tags.map((t) {
            int tw = logs
                .where((l) =>
                    l.tagUuids.contains(t.uuid) &&
                    l.endTime > ws &&
                    l.startTime < we)
                .fold(0, (s, l) => s + (l.endTime - l.startTime) ~/ 60000);
            tw += pomodoros
                .where((p) =>
                    p.tagUuids.contains(t.uuid) &&
                    p.startTime < we &&
                    (p.endTime ?? p.startTime + p.effectiveDuration * 1000) >
                        ws)
                .fold(0, (s, p) => s + p.effectiveDuration ~/ 60);
            final c = hexColor(t.color);
            return GestureDetector(
                onTap: () => onTagTap(t),
                child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                        color: c.withOpacity(0.08),
                        border: Border.all(color: c.withOpacity(0.3)),
                        borderRadius: BorderRadius.circular(8)),
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
                                  color: _TC.text(ctx),
                                  fontWeight: FontWeight.w700)),
                        ])));
          }).toList()));
}

// ══════════════════════════════════════════════════════════
// 周视图列 Painter
// ══════════════════════════════════════════════════════════
class _WeekColPainter extends CustomPainter {
  final List<TimeLogItem> dayLogs;
  final List<PomodoroRecord> dayPoms;
  final List<PomodoroTag> tags;
  final int dayStartMs;
  final bool isDark;
  final double hourH;

  const _WeekColPainter(
      {required this.dayLogs,
      this.dayPoms = const [],
      required this.tags,
      required this.dayStartMs,
      required this.isDark,
      required this.hourH});

  @override
  void paint(Canvas canvas, Size size) {
    final de = dayStartMs + 86400000;
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
          ..strokeWidth = 0.5);

    void block(int start, int end, Color c, bool isPom) {
      final rs = max(start, dayStartMs);
      final re = min(end, de);
      final top = (rs - dayStartMs) / 3600000 * hourH;
      final bot = (re - dayStartMs) / 3600000 * hourH;
      if (bot <= top + 1) return;
      canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTRB(0, top + 0.5, 3, bot - 0.5),
              const Radius.circular(2)),
          Paint()..color = c.withOpacity(0.9));
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTRB(3, top + 0.5, size.width - 1, bot - 0.5),
              const Radius.circular(3)),
          Paint()..color = c.withOpacity(isPom ? 0.22 : 0.35));
    }

    for (final p in dayPoms) {
      final pe = p.endTime ?? (p.startTime + p.effectiveDuration * 1000);
      Color c = Colors.redAccent.withOpacity(0.45);
      if (p.tagUuids.isNotEmpty) {
        final t = tags.cast<PomodoroTag?>().firstWhere(
            (t) => p.tagUuids.contains(t?.uuid),
            orElse: () => null);
        if (t != null) c = hexColor(t.color, opacity: 0.45);
      }
      block(p.startTime, pe, c, true);
    }
    for (final l in dayLogs) {
      Color c = const Color(0xFF3B82F6).withOpacity(0.45);
      if (l.tagUuids.isNotEmpty) {
        final t = tags.cast<PomodoroTag?>().firstWhere(
            (t) => l.tagUuids.contains(t?.uuid),
            orElse: () => null);
        if (t != null) c = hexColor(t.color, opacity: 0.45);
      }
      block(l.startTime, l.endTime, c, false);
    }
  }

  @override
  bool shouldRepaint(covariant _WeekColPainter o) =>
      o.isDark != isDark ||
      o.hourH != hourH ||
      o.dayLogs.length != dayLogs.length ||
      o.dayPoms.length != dayPoms.length;
}

// ══════════════════════════════════════════════════════════
// 日视图 — 网格（24行×5分钟格）
// ══════════════════════════════════════════════════════════
class _DayGridView extends StatefulWidget {
  final DateTime date;
  final List<TimeLogItem> logs;
  final List<PomodoroRecord> pomodoros;
  final List<PomodoroTag> tags;
  final void Function(PomodoroRecord) onPomodoroTap;
  final void Function(TimeLogItem) onTimeLogTap;
  final VoidCallback onSwitchEdit;

  const _DayGridView(
      {required this.date,
      required this.logs,
      required this.pomodoros,
      required this.tags,
      required this.onPomodoroTap,
      required this.onTimeLogTap,
      required this.onSwitchEdit});

  @override
  State<_DayGridView> createState() => _DayGridViewState();
}

class _DayGridViewState extends State<_DayGridView> {
  @override
  Widget build(BuildContext context) {
    final ds = _dayStart(widget.date).millisecondsSinceEpoch;
    final de = ds + 86400000;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final dLogs =
        widget.logs.where((l) => l.endTime > ds && l.startTime < de).toList();
    final dPoms = widget.pomodoros.where((p) {
      final pe = p.endTime ?? (p.startTime + p.effectiveDuration * 1000);
      return pe > ds && p.startTime < de;
    }).toList();

    final logMin =
        dLogs.fold(0, (s, l) => s + (l.endTime - l.startTime) ~/ 60000);
    final pomMin = dPoms.fold(0, (s, p) => s + p.effectiveDuration ~/ 60);
    final totalMin = logMin + pomMin;

    final Map<String, int> tagMinMap = {};
    for (final l in dLogs)
      for (final uid in l.tagUuids)
        tagMinMap[uid] =
            (tagMinMap[uid] ?? 0) + (l.endTime - l.startTime) ~/ 60000;
    for (final p in dPoms)
      for (final uid in p.tagUuids)
        tagMinMap[uid] = (tagMinMap[uid] ?? 0) + p.effectiveDuration ~/ 60;

    return Column(children: [
      _buildSummary(context, totalMin, logMin, pomMin, tagMinMap),
      Expanded(child: LayoutBuilder(builder: (ctx, constraints) {
        final gridAreaW = constraints.maxWidth - kTimeAxisW;
        final colW = gridAreaW / kColsPerH;
        final rowH = constraints.maxHeight / kTotalRows;

        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: kTimeAxisW,
            height: constraints.maxHeight,
            child: _TimeLabels(isDark: isDark, rowH: rowH),
          ),
          Expanded(
            child: SizedBox(
              width: gridAreaW,
              height: constraints.maxHeight,
              child: _GridCanvas(
                colW: colW,
                rowW: gridAreaW,
                rowH: rowH,
                dayStartMs: ds,
                dLogs: dLogs,
                dPoms: dPoms,
                tags: widget.tags,
                isDark: isDark,
                onPomodoroTap: widget.onPomodoroTap,
                onTimeLogTap: widget.onTimeLogTap,
                date: widget.date,
              ),
            ),
          ),
        ]);
      })),
    ]);
  }

  Widget _buildSummary(BuildContext ctx, int total, int logMin, int pomMin,
      Map<String, int> tagMinMap) {
    final accent = Theme.of(ctx).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      color: _TC.topBar(ctx),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                  color: accent.withOpacity(0.1),
                  border: Border.all(color: accent.withOpacity(0.3)),
                  borderRadius: BorderRadius.circular(20)),
              child: Text('${(total / 60).toStringAsFixed(1)}h  今日合计',
                  style: TextStyle(
                      fontSize: 11,
                      color: accent,
                      fontWeight: FontWeight.w700))),
          const SizedBox(width: 8),
          if (pomMin > 0) _miniPill(ctx, '专注 ${pomMin}m', Colors.redAccent),
          if (logMin > 0) ...[
            const SizedBox(width: 6),
            _miniPill(ctx, '补录 ${logMin}m', const Color(0xFF3B82F6)),
          ],
          const Spacer(),
          GestureDetector(
              onTap: widget.onSwitchEdit,
              child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                      color: accent.withOpacity(0.1),
                      border: Border.all(color: accent.withOpacity(0.3)),
                      borderRadius: BorderRadius.circular(8)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.edit_note, size: 14, color: accent),
                    const SizedBox(width: 4),
                    Text('补录',
                        style: TextStyle(
                            fontSize: 11,
                            color: accent,
                            fontWeight: FontWeight.w700)),
                  ]))),
        ]),
        if (tagMinMap.isNotEmpty && total > 0) ...[
          const SizedBox(height: 8),
          _TagProgressBar(
              tagMinMap: tagMinMap, totalMin: total, tags: widget.tags),
        ],
      ]),
    );
  }

  Widget _miniPill(BuildContext ctx, String text, Color c) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
          color: c.withOpacity(0.08),
          border: Border.all(color: c.withOpacity(0.3)),
          borderRadius: BorderRadius.circular(16)),
      child: Text(text,
          style:
              TextStyle(fontSize: 10, color: c, fontWeight: FontWeight.w600)));
}

// ══════════════════════════════════════════════════════════
// 左侧时间标签列
// ══════════════════════════════════════════════════════════
class _TimeLabels extends StatelessWidget {
  final bool isDark;
  final double rowH;

  const _TimeLabels({required this.isDark, required this.rowH});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: kTimeAxisW,
      height: rowH * kTotalRows,
      child: Stack(
        children: List.generate(kTotalRows, (h) {
          return Positioned(
            top: h * rowH,
            left: 0,
            right: 0,
            child: SizedBox(
              height: rowH,
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8, top: 3),
                  child: Text(
                    '${h.toString().padLeft(2, '0')}:00',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight:
                          h % 6 == 0 ? FontWeight.w700 : FontWeight.w400,
                      color: _TC.timeLabel(context, major: h % 6 == 0),
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════
// 网格 Canvas
// ══════════════════════════════════════════════════════════
class _GridCanvas extends StatelessWidget {
  final double colW, rowW, rowH;
  final int dayStartMs;
  final List<TimeLogItem> dLogs;
  final List<PomodoroRecord> dPoms;
  final List<PomodoroTag> tags;
  final bool isDark;
  final DateTime date;
  final void Function(PomodoroRecord) onPomodoroTap;
  final void Function(TimeLogItem) onTimeLogTap;

  const _GridCanvas(
      {required this.colW,
      required this.rowW,
      required this.rowH,
      required this.dayStartMs,
      required this.dLogs,
      required this.dPoms,
      required this.tags,
      required this.isDark,
      required this.date,
      required this.onPomodoroTap,
      required this.onTimeLogTap});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isToday = DateFormat('yyyyMMdd').format(now) ==
        DateFormat('yyyyMMdd').format(date);
    final nowTotalMin = isToday ? now.hour * 60 + now.minute : -1;

    return Stack(children: [
      CustomPaint(
        size: Size(rowW, rowH * kTotalRows),
        painter: _GridBgPainter(colW: colW, rowH: rowH, isDark: isDark),
      ),
      if (nowTotalMin >= 0) _buildNowLine(nowTotalMin),
      ...dPoms.expand((pom) {
        final pe =
            pom.endTime ?? (pom.startTime + pom.effectiveDuration * 1000);
        PomodoroTag? tag;
        if (pom.tagUuids.isNotEmpty)
          tag = tags.cast<PomodoroTag?>().firstWhere(
              (t) => pom.tagUuids.contains(t?.uuid),
              orElse: () => null);
        final base = tag != null ? hexColor(tag.color) : Colors.redAccent;
        final title = tag?.name ?? '专注';
        return _buildEventSegments(
          startMs: max(pom.startTime, dayStartMs),
          endMs: min(pe, dayStartMs + 86400000),
          dayStartMs: dayStartMs,
          colW: colW,
          isDark: isDark,
          fillColor: base.withOpacity(isDark ? 0.30 : 0.22),
          barColor: base,
          isPom: true,
          title: title,
          onTap: () => onPomodoroTap(pom),
        );
      }),
      ...dLogs.expand((log) {
        PomodoroTag? tag;
        if (log.tagUuids.isNotEmpty)
          tag = tags.cast<PomodoroTag?>().firstWhere(
              (t) => log.tagUuids.contains(t?.uuid),
              orElse: () => null);
        final base =
            tag != null ? hexColor(tag.color) : const Color(0xFF3B82F6);
        final title = log.title.isNotEmpty ? log.title : (tag?.name ?? '补录');
        return _buildEventSegments(
          startMs: max(log.startTime, dayStartMs),
          endMs: min(log.endTime, dayStartMs + 86400000),
          dayStartMs: dayStartMs,
          colW: colW,
          isDark: isDark,
          fillColor: base.withOpacity(isDark ? 0.26 : 0.18),
          barColor: base,
          isPom: false,
          title: title,
          onTap: () => onTimeLogTap(log),
        );
      }),
    ]);
  }

  Widget _buildNowLine(int nowTotalMin) {
    final nowHour = nowTotalMin ~/ 60;
    final minInHour = nowTotalMin % 60;
    final x = (minInHour / kMinsPerCol) * colW;
    final y = nowHour * rowH;

    return Stack(children: [
      Positioned(
        top: y,
        left: 0,
        right: 0,
        height: 1.0,
        child: Container(color: Colors.redAccent.withOpacity(0.20)),
      ),
      Positioned(
        top: y,
        left: x,
        width: 1.5,
        height: rowH,
        child: Container(color: Colors.redAccent.withOpacity(0.80)),
      ),
      Positioned(
        top: y + rowH / 2 - 3,
        left: x - 3,
        child: Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: Colors.redAccent,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: Colors.redAccent.withOpacity(0.5), blurRadius: 4)
            ],
          ),
        ),
      ),
    ]);
  }

  List<Widget> _buildEventSegments({
    required int startMs,
    required int endMs,
    required int dayStartMs,
    required double colW,
    required bool isDark,
    required Color fillColor,
    required Color barColor,
    required bool isPom,
    required String title,
    required VoidCallback onTap,
  }) {
    if (endMs <= startMs) return [];

    final startSec = (startMs - dayStartMs) / 1000.0;
    final endSec = (endMs - dayStartMs) / 1000.0;
    final startMinF = startSec / 60.0;
    final endMinF = endSec / 60.0;
    final totalDurMin = ((endMs - startMs) / 60000).round();
    final List<Widget> segments = [];

    int row = startMinF ~/ 60;

    while (row < kTotalRows) {
      final rowStartMin = row * 60.0;
      final rowEndMin = rowStartMin + 60.0;
      final segStartMin = startMinF.clamp(rowStartMin, rowEndMin);
      final segEndMin = endMinF.clamp(rowStartMin, rowEndMin);

      if (segEndMin <= segStartMin) {
        if (endMinF <= rowStartMin) break;
        row++;
        continue;
      }

      final colStart = (segStartMin - rowStartMin) / kMinsPerCol;
      final colEnd = (segEndMin - rowStartMin) / kMinsPerCol;

      final left = colStart * colW;
      final width = (colEnd - colStart) * colW;
      final renderW = width.clamp(1.0, double.infinity);

      final isFirst = row == (startMinF ~/ 60);
      final isLast = endMinF <= rowEndMin;
      final canText = isFirst && renderW >= 28;
      final showDur = isFirst && renderW >= 70;
      final showIcon = isFirst && renderW >= 22;

      segments.add(Positioned(
        top: row * rowH + 1,
        left: left + 1,
        width: renderW - 2,
        height: rowH - 2,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            clipBehavior: Clip.hardEdge,
            decoration: BoxDecoration(
              color: fillColor,
              border: Border(
                left: BorderSide(color: barColor, width: 2.5),
                top: isFirst
                    ? BorderSide(color: barColor.withOpacity(0.45), width: 1.0)
                    : BorderSide.none,
                bottom: isLast
                    ? BorderSide(color: barColor.withOpacity(0.45), width: 1.0)
                    : BorderSide.none,
                right: isLast && colEnd < kColsPerH
                    ? BorderSide(color: barColor.withOpacity(0.25), width: 1.0)
                    : BorderSide.none,
              ),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(isFirst ? 3 : 0),
                bottomLeft: Radius.circular(isLast ? 3 : 0),
                topRight: Radius.circular(isFirst && isLast ? 3 : 0),
                bottomRight: Radius.circular(isFirst && isLast ? 3 : 0),
              ),
            ),
            padding: const EdgeInsets.only(left: 4, right: 3, top: 1),
            child: canText
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (isPom && showIcon)
                        Padding(
                          padding: const EdgeInsets.only(right: 2),
                          child: Icon(Icons.timer_outlined,
                              size: 9, color: barColor),
                        ),
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: 10,
                            color: barColor,
                            fontWeight: FontWeight.w700,
                            height: 1.1,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      if (showDur)
                        Text(
                          '${totalDurMin}m',
                          style: TextStyle(
                            fontSize: 9,
                            color: barColor.withOpacity(0.65),
                          ),
                        ),
                    ],
                  )
                : null,
          ),
        ),
      ));

      if (isLast) break;
      row++;
    }

    return segments;
  }
}

// ══════════════════════════════════════════════════════════
// 网格背景 Painter
// ══════════════════════════════════════════════════════════
class _GridBgPainter extends CustomPainter {
  final double colW;
  final double rowH;
  final bool isDark;

  const _GridBgPainter(
      {required this.colW, required this.rowH, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final rowMajor = Paint()
      ..color = isDark ? const Color(0xFF2E2E2E) : const Color(0xFFCCCCCC)
      ..strokeWidth = 0.9;
    final rowNormal = Paint()
      ..color = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFE8E8E8)
      ..strokeWidth = 0.5;

    for (int r = 0; r <= kTotalRows; r++) {
      final y = r * rowH;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        r % 6 == 0 ? rowMajor : rowNormal,
      );
    }

    final colHour = Paint()
      ..color = isDark ? const Color(0xFF383838) : const Color(0xFFBBBBBB)
      ..strokeWidth = 0.9;
    final colHalf = Paint()
      ..color = isDark ? const Color(0xFF252525) : const Color(0xFFDCDCDC)
      ..strokeWidth = 0.5;
    final colCell = Paint()
      ..color = isDark ? const Color(0xFF181818) : const Color(0xFFF0F0F0)
      ..strokeWidth = 0.3;

    for (int c = 0; c <= kTotalCols; c++) {
      final x = c * colW;
      final Paint p;
      if (c % kColsPerH == 0)
        p = colHour;
      else if (c % 5 == 0)
        p = colHalf;
      else
        p = colCell;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }

    for (int h = 0; h < kTotalRows; h++) {
      final rowTop = h * rowH;

      _drawLabel(
        canvas,
        '${h.toString().padLeft(2, '0')}:00',
        Offset(h * kColsPerH * colW + 3, rowTop + 2),
        fontSize: 8.0,
        color: isDark ? const Color(0xFF3A3A3A) : const Color(0xFFBBBBBB),
        bold: true,
      );

      if (colW >= 14) {
        _drawLabel(
          canvas,
          '${h.toString().padLeft(2, '0')}:30',
          Offset((h * kColsPerH + 5) * colW + 3, rowTop + 2),
          fontSize: 7.0,
          color: isDark ? const Color(0xFF2C2C2C) : const Color(0xFFCCCCCC),
          bold: false,
        );
      }
    }
  }

  void _drawLabel(Canvas canvas, String text, Offset offset,
      {required double fontSize, required Color color, required bool bold}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          color: color,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _GridBgPainter o) =>
      o.isDark != isDark || o.colW != colW || o.rowH != rowH;
}

// ══════════════════════════════════════════════════════════
// 标签色条
// ══════════════════════════════════════════════════════════
class _TagProgressBar extends StatelessWidget {
  final Map<String, int> tagMinMap;
  final int totalMin;
  final List<PomodoroTag> tags;

  const _TagProgressBar(
      {required this.tagMinMap, required this.totalMin, required this.tags});

  @override
  Widget build(BuildContext context) {
    final sorted = tagMinMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
              height: 5,
              width: double.infinity,
              child: Row(
                  children: sorted.map((e) {
                final t = tags
                    .cast<PomodoroTag?>()
                    .firstWhere((t) => t?.uuid == e.key, orElse: () => null);
                final c =
                    t != null ? hexColor(t.color) : const Color(0xFF3B82F6);
                return Expanded(flex: e.value, child: Container(color: c));
              }).toList()))),
      const SizedBox(height: 5),
      Wrap(
          spacing: 10,
          runSpacing: 3,
          children: sorted.map((e) {
            final t = tags
                .cast<PomodoroTag?>()
                .firstWhere((t) => t?.uuid == e.key, orElse: () => null);
            if (t == null) return const SizedBox.shrink();
            final c = hexColor(t.color);
            return Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
              const SizedBox(width: 4),
              Text(t.name,
                  style: TextStyle(
                      fontSize: 10, color: c, fontWeight: FontWeight.w600)),
              const SizedBox(width: 3),
              Text('${e.value}m',
                  style: TextStyle(fontSize: 10, color: _TC.textSub(context))),
            ]);
          }).toList()),
    ]);
  }
}
