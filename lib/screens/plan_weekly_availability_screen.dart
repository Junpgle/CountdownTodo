import 'package:flutter/material.dart';

import '../models/plan_availability.dart';
import '../models/plan_weekly_availability.dart';
import '../services/plan_weekly_availability_preferences.dart';
import '../services/plan_todo_guard.dart';
import '../utils/app_dialogs.dart';

Future<bool> _discardWeeklyChanges(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('放弃未保存的修改？'),
        content: const Text('每周规则尚未保存。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('继续编辑'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('放弃修改'),
          ),
        ],
      ),
    ) ??
    false;

class PlanWeeklyAvailabilityScreen extends StatefulWidget {
  const PlanWeeklyAvailabilityScreen({super.key, required this.username});
  final String username;
  @override
  State<PlanWeeklyAvailabilityScreen> createState() =>
      _PlanWeeklyAvailabilityScreenState();
}

class _PlanWeeklyAvailabilityScreenState
    extends State<PlanWeeklyAvailabilityScreen> {
  final _scroll = ScrollController();
  PlanTodoIdentity? _identity;
  PlanWeeklyRules? _rules;
  String? _baseline, _expectedKey, _error;
  bool _loading = true, _saving = false, _leaving = false;
  int _sequence = 0;
  bool get _dirty => _rules != null && _rules!.fingerprint != _baseline;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant PlanWeeklyAvailabilityScreen old) {
    super.didUpdateWidget(old);
    if (old.username != widget.username) {
      _rules = null;
      _baseline = null;
      _load();
    }
  }

  Future<void> _load() async {
    final sequence = ++_sequence;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final identity = await PlanTodoIdentity.capture(widget.username);
      final saved = await PlanWeeklyAvailabilityPreferences.load(
        widget.username,
      );
      await identity.check();
      if (!mounted || sequence != _sequence) return;
      setState(() {
        _identity = identity;
        _rules = saved.rules;
        _expectedKey = saved.key;
        _baseline = saved.rules?.fingerprint;
        _error = saved.error;
      });
    } catch (e) {
      if (mounted && sequence == _sequence) setState(() => _error = '$e');
    } finally {
      if (mounted && sequence == _sequence) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving ||
        _rules == null ||
        _identity == null ||
        _expectedKey == null) {
      return;
    }
    final sequence = _sequence, username = widget.username;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await PlanWeeklyAvailabilityPreferences.save(
        _identity!,
        _rules!,
        expectedKey: _expectedKey!,
      );
      if (!mounted || sequence != _sequence || username != widget.username) {
        return;
      }
      setState(() {
        _baseline = _rules!.fingerprint;
        _leaving = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context, true);
      });
    } catch (e) {
      if (mounted && sequence == _sequence && username == widget.username) {
        setState(
          () => _error = e is PlanAvailabilityException
              ? e.message
              : '保存失败，修改仍保留，请重试',
        );
        if (_scroll.hasClients) _scroll.jumpTo(0);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _edit(int index) async {
    final result = await Navigator.push<List<PlanWeeklyWindow>>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            _WeeklyDayEditor(weekday: index, initial: _rules!.days[index]),
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      final days = _rules!.days.toList();
      days[index] = result;
      _rules = _rules!.copy(days: days);
    });
  }

  Future<void> _copy() async {
    var source = 0;
    final targets = <int>{};
    final apply = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => AlertDialog(
          title: const Text('复制到其他星期'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<int>(
                    initialValue: source,
                    decoration: const InputDecoration(labelText: '复制来源'),
                    items: [
                      for (var i = 0; i < 7; i++)
                        DropdownMenuItem(
                          value: i,
                          child: Text(PlanWeeklyRules.weekdays[i]),
                        ),
                    ],
                    onChanged: (v) => update(() {
                      source = v!;
                      targets.remove(source);
                    }),
                  ),
                  const SizedBox(height: 12),
                  const Text('选择目标星期'),
                  for (var i = 0; i < 7; i++)
                    if (i != source)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(PlanWeeklyRules.weekdays[i]),
                        value: targets.contains(i),
                        onChanged: (v) => update(() {
                          if (v!) {
                            targets.add(i);
                          } else {
                            targets.remove(i);
                          }
                        }),
                      ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: targets.isEmpty ? null : () => Navigator.pop(c, true),
              child: const Text('填入草稿'),
            ),
          ],
        ),
      ),
    );
    if (apply != true || !mounted) return;
    setState(() {
      final days = _rules!.days.toList();
      for (final i in targets) {
        days[i] = days[source];
      }
      _rules = _rules!.copy(days: days);
    });
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: (!_dirty && !_saving) || _leaving,
    onPopInvokedWithResult: (didPop, result) async {
      if (didPop || _saving) return;
      if (await _discardWeeklyChanges(context) && mounted) {
        setState(() => _leaving = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.pop(context);
        });
      }
    },
    child: Scaffold(
      appBar: AppBar(
        title: const Text('每周可安排时间'),
        actions: [
          TextButton(
            key: const ValueKey('weekly-save'),
            onPressed: _loading || _saving || _rules == null ? null : _save,
            child: Text(_saving ? '保存中' : '保存'),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.all(16),
            children: [
              if (_loading) const LinearProgressIndicator(),
              if (_error != null) ...[
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: _loading || _saving
                          ? null
                          : () async {
                              if (!_dirty ||
                                  await _discardWeeklyChanges(context)) {
                                if (mounted) _load();
                              }
                            },
                      child: const Text('重新读取'),
                    ),
                    if (_rules == null && _expectedKey != null)
                      TextButton(
                        key: const ValueKey('weekly-repair'),
                        onPressed: () => setState(() {
                          _rules = PlanWeeklyRules.initial();
                          _error = null;
                        }),
                        child: const Text('重置此规则并编辑'),
                      ),
                  ],
                ),
              ],
              if (_rules != null) ...[
                SwitchListTile(
                  key: const ValueKey('weekly-enabled'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('用于推荐时段'),
                  subtitle: const Text('仅当前账号、本机生效；手工安排仍可自由选择时间'),
                  value: _rules!.enabled,
                  onChanged: _saving
                      ? null
                      : (v) =>
                            setState(() => _rules = _rules!.copy(enabled: v)),
                ),
                const SizedBox(height: 8),
                for (var i = 0; i < 7; i++)
                  Card(
                    child: ListTile(
                      key: ValueKey('weekly-day-$i'),
                      title: Text(PlanWeeklyRules.weekdays[i]),
                      subtitle: Text(_rules!.summary(i + 1)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _saving ? null : () => _edit(i),
                    ),
                  ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      key: const ValueKey('weekly-copy'),
                      onPressed: _saving ? null : _copy,
                      icon: const Icon(Icons.copy_all_outlined),
                      label: const Text('复制到其他星期'),
                    ),
                    OutlinedButton(
                      key: const ValueKey('weekly-template'),
                      onPressed: _saving
                          ? null
                          : () => setState(() {
                              final days = _rules!.days.toList();
                              for (var i = 0; i < 5; i++) {
                                days[i] = [
                                  const PlanWeeklyWindow(540, 720),
                                  const PlanWeeklyWindow(840, 1080),
                                ];
                              }
                              _rules = _rules!.copy(days: days);
                            }),
                      child: const Text('填入工作日 09–12 / 14–18'),
                    ),
                    TextButton(
                      key: const ValueKey('weekly-reset'),
                      onPressed: _saving
                          ? null
                          : () => setState(() {
                              _rules = PlanWeeklyRules.initial().copy(
                                enabled: _rules!.enabled,
                              );
                            }),
                      child: const Text('恢复每天全天'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  '设置只影响推荐，不会修改已有规划。模板与复制仅填入当前草稿，点击保存后生效。午休、用餐避让、缓冲和已有日程继续参与检查。',
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class _WeeklyDayEditor extends StatefulWidget {
  const _WeeklyDayEditor({required this.weekday, required this.initial});
  final int weekday;
  final List<PlanWeeklyWindow> initial;
  @override
  State<_WeeklyDayEditor> createState() => _WeeklyDayEditorState();
}

class _WeeklyDayEditorState extends State<_WeeklyDayEditor> {
  late List<PlanWeeklyWindow> _windows;
  late String _mode;
  late String _baseline;
  String? _error;
  bool _leaving = false;
  String get _key =>
      '$_mode:${_windows.map((w) => '${w.start}:${w.end}').join(',')}';
  @override
  void initState() {
    super.initState();
    _windows = widget.initial.toList();
    _mode = _windows.isEmpty
        ? 'none'
        : _windows.length == 1 &&
              _windows.first.start == 0 &&
              _windows.first.end == 1440
        ? 'all'
        : 'custom';
    _baseline = _key;
  }

  Future<void> _time(int index, bool start) async {
    final w = _windows[index],
        minute = start ? _windows[index].start : _windows[index].end;
    final selected = await showAppTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minute ~/ 60 % 24, minute: minute % 60),
    );
    if (!mounted || selected == null) return;
    final m = selected.hour * 60 + selected.minute;
    setState(() {
      _error = null;
      _windows[index] = start
          ? PlanWeeklyWindow(m, w.end)
          : PlanWeeklyWindow(w.start, m == 0 ? 1440 : m);
    });
  }

  void _apply() {
    try {
      final windows = _mode == 'all'
          ? [const PlanWeeklyWindow(0, 1440)]
          : _mode == 'none'
          ? <PlanWeeklyWindow>[]
          : _windows;
      if (_mode == 'custom' && windows.isEmpty) {
        throw const FormatException('请添加时段，或明确选择不推荐');
      }
      final normalized = PlanWeeklyRules(
        enabled: false,
        days: List.generate(7, (_) => windows),
      ).days.first;
      setState(() => _leaving = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context, normalized);
      });
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _key == _baseline || _leaving,
    onPopInvokedWithResult: (didPop, result) async {
      if (!didPop && await _discardWeeklyChanges(context) && mounted) {
        setState(() => _leaving = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.pop(context);
        });
      }
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text('${PlanWeeklyRules.weekdays[widget.weekday]}可安排时间'),
        actions: [
          TextButton(
            key: const ValueKey('weekly-day-apply'),
            onPressed: _apply,
            child: const Text('应用'),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final m in ['all', 'custom', 'none'])
                    ChoiceChip(
                      key: ValueKey('weekly-mode-$m'),
                      label: Text(
                        {'all': '全天', 'custom': '指定时段', 'none': '不推荐'}[m]!,
                      ),
                      selected: _mode == m,
                      onSelected: (_) => setState(() {
                        _mode = m;
                        _error = null;
                        if (m == 'custom' &&
                            (_windows.isEmpty ||
                                _windows.first.end == 1440 &&
                                    _windows.first.start == 0)) {
                          _windows = [const PlanWeeklyWindow(540, 720)];
                        }
                      }),
                    ),
                ],
              ),
              if (_mode == 'custom') ...[
                const SizedBox(height: 16),
                for (var i = 0; i < _windows.length; i++)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text('时段${i + 1}'),
                          OutlinedButton(
                            key: ValueKey('weekly-start-$i'),
                            onPressed: () => _time(i, true),
                            child: Text(
                              '开始 ${PlanWeeklyWindow.time(_windows[i].start)}',
                            ),
                          ),
                          OutlinedButton(
                            key: ValueKey('weekly-end-$i'),
                            onPressed: () => _time(i, false),
                            child: Text(
                              '结束 ${PlanWeeklyWindow.time(_windows[i].end)}',
                            ),
                          ),
                          IconButton(
                            tooltip: '移除时段${i + 1}',
                            onPressed: () =>
                                setState(() => _windows.removeAt(i)),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),
                  ),
                TextButton.icon(
                  key: const ValueKey('weekly-add-window'),
                  onPressed: _windows.length >= 4
                      ? null
                      : () => setState(() {
                          _windows.add(const PlanWeeklyWindow(840, 1080));
                        }),
                  icon: const Icon(Icons.add),
                  label: const Text('添加时段（最多四段）'),
                ),
                const Text('结束选00:00表示当天24:00。重叠或相邻时段会自动合并。'),
              ],
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
