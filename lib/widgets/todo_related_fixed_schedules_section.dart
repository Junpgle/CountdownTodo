import 'dart:async';

import 'package:flutter/material.dart';

import '../models.dart';
import '../services/fixed_schedule_todo_relation_service.dart';
import '../storage_service.dart';
import '../utils/time_utils.dart';
import 'app_detail_widgets.dart';

typedef RelatedFixedScheduleLoader = Future<List<FixedScheduleItem>> Function(
  String username,
  String todoId,
);
typedef CurrentUsernameLoader = Future<String?> Function();
typedef RelatedFixedScheduleOpener = Future<void> Function(
  String username,
  FixedScheduleItem item,
);

Future<List<FixedScheduleItem>> _loadRelatedFixedSchedules(
  String username,
  String todoId,
) => StorageService.getFixedSchedulesByRelatedTodo(username, todoId);

Future<String?> _getCurrentUsername() => StorageService.getCurrentUsername();

/// Read-only reverse relation from a todo to the fixed schedules that link it.
class TodoRelatedFixedSchedulesSection extends StatefulWidget {
  const TodoRelatedFixedSchedulesSection({
    super.key,
    required this.todo,
    required this.onOpenSchedule,
    this.loadSchedules = _loadRelatedFixedSchedules,
    this.getCurrentUsername = _getCurrentUsername,
  });

  final TodoItem todo;
  final RelatedFixedScheduleOpener onOpenSchedule;
  final RelatedFixedScheduleLoader loadSchedules;
  final CurrentUsernameLoader getCurrentUsername;

  @override
  State<TodoRelatedFixedSchedulesSection> createState() =>
      _TodoRelatedFixedSchedulesSectionState();
}

class _TodoRelatedFixedSchedulesSectionState
    extends State<TodoRelatedFixedSchedulesSection>
    with WidgetsBindingObserver {
  List<FixedScheduleTodoRelationGroup> _groups = const [];
  String? _username;
  String? _loadError;
  bool _loading = true;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    StorageService.scopedDataRefreshNotifier.addListener(_onDataRefresh);
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant TodoRelatedFixedSchedulesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.todo.id != widget.todo.id ||
        oldWidget.todo.teamUuid != widget.todo.teamUuid) {
      _groups = const [];
      _username = null;
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    StorageService.scopedDataRefreshNotifier.removeListener(_onDataRefresh);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_load());
  }

  void _onDataRefresh() {
    final signal = StorageService.scopedDataRefreshNotifier.value;
    if (signal.affects(DataRefreshDomain.fixedSchedules)) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    if (!mounted) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final username = (await widget.getCurrentUsername())?.trim();
      if (!mounted || generation != _generation) return;
      if (username == null || username.isEmpty) {
        setState(() {
          _groups = const [];
          _username = null;
          _loading = false;
          _loadError = '当前账号不可用，无法读取关联固定日程。';
        });
        return;
      }

      if (_username != null && _username != username) {
        setState(() => _groups = const []);
      }

      final schedules = await widget.loadSchedules(username, widget.todo.id);
      final latestUsername = (await widget.getCurrentUsername())?.trim();
      if (!mounted || generation != _generation) return;
      if (latestUsername != username) {
        setState(() {
          _groups = const [];
          _username = latestUsername;
          _loading = false;
        });
        if (latestUsername?.isNotEmpty == true) unawaited(_load());
        return;
      }

      final groups = FixedScheduleTodoRelationService.groupForTodo(
        todo: widget.todo,
        schedules: schedules,
      );
      setState(() {
        _groups = groups;
        _username = username;
        _loading = false;
        _loadError = null;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _groups = const [];
        _loading = false;
        _loadError = '关联固定日程读取失败，无法确认当前列表是否为空。';
      });
    }
  }

  Future<void> _openSchedule(
    FixedScheduleItem item, {
    GlobalKey? sourceKey,
  }) async {
    final username = _username;
    if (username == null || username.isEmpty) return;
    try {
      await (widget.onOpenSchedule as dynamic)(
        username,
        item,
        sourceKey: sourceKey,
      );
    } catch (_) {
      await widget.onOpenSchedule(username, item);
    }
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final linkedCount = _groups.fold<int>(
      0,
      (count, group) => count + group.items.length,
    );
    final title = linkedCount == 0 ? '关联固定日程' : '关联固定日程 · $linkedCount';
    return AppDetailSection(
      title: title,
      children: [
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: LinearProgressIndicator(),
          )
        else if (_loadError != null)
          _buildError(context)
        else if (_groups.isEmpty)
          Text(
            '暂无关联固定日程。可在固定日程编辑中关联准备待办。',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          )
        else
          ..._groups.map((group) => _buildGroup(context, group)),
      ],
    );
  }

  Widget _buildError(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_loadError!, style: TextStyle(color: colors.onSurfaceVariant)),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('related-fixed-schedules-retry'),
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('重试'),
          ),
        ),
      ],
    );
  }

  Widget _buildGroup(
    BuildContext context,
    FixedScheduleTodoRelationGroup group,
  ) {
    if (!group.isSeries) {
      return _buildOccurrenceTile(context, group.items.single);
    }
    final summary = group.summaryItem;
    return Card(
      key: ValueKey('related-fixed-schedule-series-${group.key}'),
      margin: const EdgeInsets.only(bottom: 8),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: Icon(
          Icons.event_repeat_rounded,
          color: Theme.of(context).colorScheme.primary,
        ),
        title: Text(group.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${group.items.length} 场关联 · ${_occurrenceSummary(summary)}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        children: [
          for (final item in group.items)
            _buildOccurrenceTile(context, item, compact: true),
        ],
      ),
    );
  }

  Widget _buildOccurrenceTile(
    BuildContext context,
    FixedScheduleItem item, {
    bool compact = false,
  }) {
    final colors = Theme.of(context).colorScheme;
    final phase = item.phaseAt(DateTime.now());
    final statusColor = switch (phase) {
      FixedSchedulePhase.cancelled => colors.error,
      FixedSchedulePhase.ongoing => colors.primary,
      FixedSchedulePhase.ended => colors.onSurfaceVariant,
      FixedSchedulePhase.upcoming => colors.secondary,
      FixedSchedulePhase.timeTbd => colors.tertiary,
    };
    final cardKey = GlobalKey();
    return KeyedSubtree(
      key: ValueKey('related-fixed-schedule-${item.id}'),
      child: Card(
        key: cardKey,
        margin: compact
            ? const EdgeInsets.fromLTRB(12, 0, 12, 8)
            : const EdgeInsets.only(bottom: 8),
        color: colors.surfaceContainerLow,
        child: ListTile(
          onTap: () => _openSchedule(item, sourceKey: cardKey),
          leading: Icon(Icons.event_available_rounded, color: statusColor),
          title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            _occurrenceDetails(item),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Icon(
            Icons.chevron_right_rounded,
            color: colors.onSurfaceVariant,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 2,
          ),
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }

  String _occurrenceSummary(FixedScheduleItem item) =>
      '${_dateTimeLabel(item)} · ${_phaseLabel(item)}';

  String _occurrenceDetails(FixedScheduleItem item) {
    final location = item.location?.trim();
    final details = <String>[_dateTimeLabel(item), _phaseLabel(item)];
    if (location != null && location.isNotEmpty) details.add(location);
    return details.join(' · ');
  }

  String _dateTimeLabel(FixedScheduleItem item) {
    final date = DateTime.tryParse(item.date)?.toLocal();
    final day = date == null
        ? item.date
        : AppTimeFormats.format(date, 'yyyy年M月d日');
    if (item.startTime == null) return '$day · 时间待定';
    final start = DateTime.fromMillisecondsSinceEpoch(item.startTime!)
        .toLocal();
    final startText = AppTimeFormats.format(start, 'HH:mm');
    final endTime = item.endTime;
    if (endTime == null) return '$day $startText · 结束待定';
    final end = DateTime.fromMillisecondsSinceEpoch(endTime).toLocal();
    return '$day $startText–${AppTimeFormats.format(end, 'HH:mm')}';
  }

  String _phaseLabel(FixedScheduleItem item) =>
      switch (item.phaseAt(DateTime.now())) {
        FixedSchedulePhase.timeTbd => '时间待定',
        FixedSchedulePhase.upcoming => '未开始',
        FixedSchedulePhase.ongoing => '进行中',
        FixedSchedulePhase.ended => '已结束',
        FixedSchedulePhase.cancelled => '已取消',
      };
}
