part of '../conflict_inbox_screen.dart';

/// Bottom sheet for comparing local vs server versions and choosing resolution.
class _ConflictResolutionSheet extends StatefulWidget {
  final Map<String, dynamic> localItem;
  final Map<String, dynamic>? serverItem;
  final String table;
  final String username;
  final VoidCallback onResolved;

  final bool isEmbedded;

  const _ConflictResolutionSheet({
    required this.localItem,
    required this.serverItem,
    required this.table,
    required this.username,
    required this.onResolved,
    this.isEmbedded = false,
  });

  @override
  State<_ConflictResolutionSheet> createState() =>
      _ConflictResolutionSheetState();
}

class _ConflictResolutionSheetState extends State<_ConflictResolutionSheet> {
  bool _isResolving = false;

  bool get _hasServerData =>
      widget.serverItem != null && widget.serverItem!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    if (widget.isEmbedded) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _buildContent(context),
        ),
      );
    }

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.8,
      ),
      child: OptionalLiquidGlassSheet(
        topRadius: 20,
        padding: const EdgeInsets.all(20),
        fallbackDecoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              const Center(child: AppSheetDragHandle(margin: EdgeInsets.zero)),
              const SizedBox(height: 16),
              ..._buildContent(context),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildContent(BuildContext context) {
    final diffs = _buildDiffFields(widget.localItem, widget.serverItem);

    return [
      const Text(
        "版本对齐建议",
        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 8),
      Text(
        "检测到两端内容存在差异，请选择权威版本进行保留。",
        style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
      ),
      if (diffs.isNotEmpty) ...[
        const SizedBox(height: 16),
        _buildDiffSummary(diffs),
      ] else ...[
        const SizedBox(height: 16),
        _buildDiffFallbackHint(),
      ],
      const SizedBox(height: 32),

      // Local version card
      _buildVersionCard(
        label: "本地版本",
        icon: Icons.phone_android_rounded,
        color: Theme.of(context).colorScheme.primary,
        data: widget.localItem,
      ),
      const SizedBox(height: 12),

      // Server version card
      if (_hasServerData)
        _buildVersionCard(
          label: "服务器版本",
          icon: Icons.cloud_rounded,
          color: Colors.green,
          data: widget.serverItem!,
        )
      else
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Icon(Icons.cloud_off_rounded, color: Colors.grey),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  "服务器版本数据暂不可用\n请同步后重试",
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
              ),
            ],
          ),
        ),
      const SizedBox(height: 24),

      // Action buttons
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _isResolving ? null : _keepLocal,
              icon: const Icon(Icons.phone_android_rounded, size: 18),
              label: const Text("保留本地"),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              onPressed: _isResolving ? null : _acceptServer,
              icon: const Icon(Icons.cloud_done_rounded, size: 18),
              label: const Text("采用服务器"),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
      if (_isResolving) ...[
        const SizedBox(height: 12),
        const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ],
      const SizedBox(height: 12),
    ];
  }

  Widget _buildDiffSummary(List<_ConflictFieldDiff> diffs) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.tune_rounded, size: 18, color: Colors.amber),
              const SizedBox(width: 8),
              Text(
                '差异字段',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade900,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${diffs.length} 项',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: diffs
                .map(
                  (diff) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.grey.withValues(alpha: 0.15),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          diff.label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '本地: ${diff.localValue}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.blueGrey.shade700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '服务器: ${diff.serverValue}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.green.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildDiffFallbackHint() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.16)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: Colors.grey.shade600,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '当前没有匹配到可见字段差异。可能是其它隐藏字段、归一化值，或者服务端只保留了冲突标记。',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade700,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVersionCard({
    required String label,
    required IconData icon,
    required Color color,
    required Map<String, dynamic> data,
  }) {
    final title = data['content'] ?? data['title'] ?? data['name'] ?? '未命名';
    final isDeleted = data['is_deleted'] == 1 || data['is_deleted'] == true;
    final version = data['version'] ?? '?';
    final isCompleted =
        data['is_completed'] == 1 || data['is_completed'] == true;
    final targetValue = data['target_value'] ?? data['targetValue'];
    final unit = data['unit']?.toString() ?? '';

    String? timeStr;
    final start =
        data['start_time'] ??
        data['startTime'] ??
        data['created_date'] ??
        data['createdDate'];
    final end =
        data['end_time'] ??
        data['endTime'] ??
        data['due_date'] ??
        data['dueDate'];
    final targetTime = data['target_time'] ?? data['targetTime'];
    if (start != null && end != null) {
      final startMs = start is int
          ? start
          : int.tryParse(start.toString()) ?? 0;
      final endMs = end is int ? end : int.tryParse(end.toString()) ?? 0;
      if (startMs > 0 && endMs > 0) {
        final sf = AppTimeFormats.dateFormatter('MM-dd HH:mm');
        timeStr =
            '${sf.format(DateTime.fromMillisecondsSinceEpoch(startMs))} ~ ${sf.format(DateTime.fromMillisecondsSinceEpoch(endMs))}';
      }
    } else if (targetTime != null) {
      final tMs = targetTime is int
          ? targetTime
          : int.tryParse(targetTime.toString()) ?? 0;
      if (tMs > 0) {
        timeStr = AppTimeFormats.dateFormatter('MM-dd HH:mm')
            .format(DateTime.fromMillisecondsSinceEpoch(tMs));
      }
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  "v$version",
                  style: TextStyle(
                    fontSize: 10,
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildFieldRow("标题", title),
          if (isDeleted) _buildFieldRow("状态", "已删除", valueColor: Colors.red),
          if (isCompleted) _buildFieldRow("完成", "是"),
          if (targetValue != null)
            _buildFieldRow(
              "目标值",
              unit.isNotEmpty ? '$targetValue $unit' : '$targetValue',
            ),
          if (timeStr != null) _buildFieldRow("时间", timeStr),
          if (data['remark'] != null && data['remark'].toString().isNotEmpty)
            _buildFieldRow("备注", data['remark'].toString()),
        ],
      ),
    );
  }

  List<_ConflictFieldDiff> _buildDiffFields(
    Map<String, dynamic> local,
    Map<String, dynamic>? server,
  ) {
    if (server == null || server.isEmpty) return const [];

    final collabType =
        local['collab_type'] ??
        local['collabType'] ??
        server['collab_type'] ??
        server['collabType'] ??
        0;
    final isIndependentCollab = collabType == 1 || collabType == '1';

    final fields = <_ConflictFieldSpec>[
      _ConflictFieldSpec(
        label: '标题',
        keys: const ['content', 'title', 'name', 'courseName', 'course_name'],
      ),
      _ConflictFieldSpec(label: '备注', keys: const ['remark']),
      if (!isIndependentCollab)
        _ConflictFieldSpec(
          label: '完成状态',
          keys: const ['is_completed', 'isCompleted'],
        ),
      _ConflictFieldSpec(
        label: '删除状态',
        keys: const ['is_deleted', 'isDeleted'],
      ),
      _ConflictFieldSpec(label: '版本号', keys: const ['version']),
      _ConflictFieldSpec(
        label: '更新时间',
        keys: const ['updated_at', 'updatedAt'],
        formatter: _formatTimestamp,
      ),
      _ConflictFieldSpec(
        label: '创建时间',
        keys: const ['created_at', 'createdAt'],
        formatter: _formatTimestamp,
      ),
      _ConflictFieldSpec(label: '分组', keys: const ['group_id', 'groupId']),
      _ConflictFieldSpec(label: '团队', keys: const ['team_uuid', 'teamUuid']),
      _ConflictFieldSpec(
        label: '分类',
        keys: const ['category_id', 'categoryId'],
      ),
      _ConflictFieldSpec(
        label: '开始时间',
        keys: const ['start_time', 'startTime', 'created_date', 'createdDate'],
        formatter: _formatDateTimeMs,
      ),
      _ConflictFieldSpec(
        label: '结束/截止',
        keys: const [
          'end_time',
          'endTime',
          'due_date',
          'dueDate',
          'target_time',
          'targetTime',
        ],
        formatter: _formatDateTimeMs,
      ),
      _ConflictFieldSpec(label: '循环', keys: const ['recurrence']),
      _ConflictFieldSpec(label: '全天', keys: const ['is_all_day', 'isAllDay']),
      _ConflictFieldSpec(
        label: '协作类型',
        keys: const ['collab_type', 'collabType'],
      ),
      _ConflictFieldSpec(
        label: '提醒',
        keys: const ['reminder_minutes', 'reminderMinutes'],
      ),
      _ConflictFieldSpec(label: '星期', keys: const ['weekday']),
      _ConflictFieldSpec(label: '周次', keys: const ['week_index', 'weekIndex']),
      _ConflictFieldSpec(label: '地点', keys: const ['room_name', 'roomName']),
      _ConflictFieldSpec(
        label: '教师',
        keys: const ['teacher_name', 'teacherName'],
      ),
      _ConflictFieldSpec(
        label: '课名',
        keys: const ['course_name', 'courseName'],
      ),
      _ConflictFieldSpec(label: '图标', keys: const ['icon']),
      _ConflictFieldSpec(
        label: '来源类型',
        keys: const ['source_type', 'sourceType'],
      ),
      _ConflictFieldSpec(
        label: '来源列表',
        keys: const ['source_ids', 'sourceIds'],
      ),
      _ConflictFieldSpec(
        label: '显示模式',
        keys: const ['display_mode', 'displayMode'],
      ),
      _ConflictFieldSpec(
        label: '默认专注',
        keys: const ['default_focus_minutes', 'defaultFocusMinutes'],
      ),
      _ConflictFieldSpec(label: '排序', keys: const ['sort_order', 'sortOrder']),
      _ConflictFieldSpec(
        label: '归档',
        keys: const ['is_archived', 'isArchived'],
      ),
      _ConflictFieldSpec(
        label: '所属目标',
        keys: const ['habit_uuid', 'habitUuid'],
      ),
      _ConflictFieldSpec(
        label: '生效日期',
        keys: const ['effective_from_date', 'effectiveFromDate'],
      ),
      _ConflictFieldSpec(
        label: '结束日期',
        keys: const ['effective_to_date', 'effectiveToDate'],
      ),
      _ConflictFieldSpec(
        label: '周期类型',
        keys: const ['period_type', 'periodType'],
      ),
      _ConflictFieldSpec(
        label: '星期掩码',
        keys: const ['weekdays_mask', 'weekdaysMask'],
      ),
      _ConflictFieldSpec(
        label: '间隔天数',
        keys: const ['custom_interval_days', 'customIntervalDays'],
      ),
      _ConflictFieldSpec(
        label: '目标值',
        keys: const ['target_value', 'targetValue'],
      ),
      _ConflictFieldSpec(label: '单位', keys: const ['unit']),
      _ConflictFieldSpec(
        label: '目标时刻',
        keys: const ['target_time_minute', 'targetTimeMinute'],
      ),
      _ConflictFieldSpec(
        label: '比较方式',
        keys: const ['time_comparison', 'timeComparison'],
      ),
      _ConflictFieldSpec(
        label: '容差分钟',
        keys: const ['time_tolerance_minutes', 'timeToleranceMinutes'],
      ),
      _ConflictFieldSpec(
        label: '日界分钟',
        keys: const ['day_boundary_minute', 'dayBoundaryMinute'],
      ),
      _ConflictFieldSpec(
        label: '快捷值',
        keys: const ['quick_values_json', 'quickValuesJson'],
      ),
      _ConflictFieldSpec(
        label: '提醒策略',
        keys: const ['reminder_policy_json', 'reminderPolicyJson'],
      ),
    ];

    final diffs = <_ConflictFieldDiff>[];
    for (final field in fields) {
      final localValue = _extractFieldValue(local, field.keys);
      final serverValue = _extractFieldValue(server, field.keys);
      if (!_valuesEqual(localValue, serverValue)) {
        diffs.add(
          _ConflictFieldDiff(
            label: field.label,
            localValue: _formatFieldValue(localValue, field.formatter),
            serverValue: _formatFieldValue(serverValue, field.formatter),
          ),
        );
      }
    }

    return diffs;
  }

  dynamic _extractFieldValue(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      if (data.containsKey(key)) return data[key];
    }
    return null;
  }

  bool _valuesEqual(dynamic a, dynamic b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    return _normalizeComparableValue(a) == _normalizeComparableValue(b);
  }

  String _normalizeComparableValue(dynamic value) {
    if (value == null) return '';
    if (value is bool) return value ? '1' : '0';
    if (value is num) return value.toString();
    if (value is Map || value is List) return jsonEncode(value);
    return value.toString().trim();
  }

  String _formatFieldValue(
    dynamic value,
    String Function(dynamic value)? formatter,
  ) {
    if (formatter != null) {
      return formatter(value);
    }
    final normalized = _normalizeComparableValue(value);
    return normalized.isEmpty ? '空' : normalized;
  }

  String _formatTimestamp(dynamic value) {
    final ms = _toMillis(value);
    if (ms == null || ms <= 0) return '空';
    return AppTimeFormats.dateFormatter('yyyy-MM-dd HH:mm:ss')
        .format(DateTime.fromMillisecondsSinceEpoch(ms));
  }

  String _formatDateTimeMs(dynamic value) {
    final ms = _toMillis(value);
    if (ms == null || ms <= 0) return '空';
    return AppTimeFormats.dateFormatter('MM-dd HH:mm')
        .format(DateTime.fromMillisecondsSinceEpoch(ms));
  }

  int? _toMillis(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  Widget _buildFieldRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 40,
            child: Text(
              label,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 13, color: valueColor),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _keepLocal() async {
    setState(() => _isResolving = true);
    try {
      final uuid = widget.localItem['uuid'] ?? widget.localItem['id'] ?? '';

      // Bump version above server version and clear conflict flag locally,
      // then re-upload via op_logs so the server picks it up.
      final serverVersion = widget.serverItem?['version'] as int? ?? 0;
      final currentVersion = widget.localItem['version'] as int? ?? 1;
      final newVersion = serverVersion > currentVersion
          ? serverVersion + 1
          : currentVersion + 1;
      final now = DateTime.now().millisecondsSinceEpoch;

      widget.localItem['version'] = newVersion;
      widget.localItem['updated_at'] = now;
      widget.localItem['has_conflict'] = 0;
      widget.localItem.remove('conflict_data');
      widget.localItem.remove('serverVersionData');

      // Persist locally and create oplog to push bumped version to server
      await StorageService.resolveConflictLocally(
        uuid: uuid,
        table: widget.table,
        resolvedData: widget.localItem,
        createOplog: true,
      );

      // Also tell the server to clear the conflict flag
      try {
        await ApiService.resolveConflict(
          uuid: uuid,
          table: widget.table,
          resolution: 'keep_local',
          bumpedVersion: newVersion,
          data: widget.localItem,
        );
      } catch (e) {
        // debugPrint(
        //     'resolve_conflict keep_local API failed (will retry via oplog): $e');
      }

      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        widget.onResolved();
        Future.microtask(() => StorageService.syncData(widget.username));
        if (!widget.isEmbedded) {
          Navigator.pop(context);
        }
        AppSnackBars.showSnackBarFromMessenger(
          messenger,
          const SnackBar(
            content: Text('已保留本地版本，冲突已解决'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        AppSnackBars.showSnackBar(
          context,
          SnackBar(content: Text('操作失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isResolving = false);
    }
  }

  Future<void> _acceptServer() async {
    if (!_hasServerData) {
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(
          content: Text('服务器版本数据不可用，请先同步'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isResolving = true);
    try {
      final uuid = widget.localItem['uuid'] ?? widget.localItem['id'] ?? '';

      // Overwrite local with server version, clear conflict flag
      widget.serverItem!['has_conflict'] = 0;

      // Overwrite local with server version, no oplog needed
      await StorageService.resolveConflictLocally(
        uuid: uuid,
        table: widget.table,
        resolvedData: widget.serverItem!,
        createOplog: false,
        touchUpdatedAt: false,
      );

      // Notify server
      final apiResult = await ApiService.resolveConflict(
        uuid: uuid,
        table: widget.table,
        resolution: 'accept_server',
      );
      if (apiResult['success'] != true) {
        // API failed — create fallback oplog so resolution survives next sync
        // debugPrint(
        //     'accept_server API failed, creating fallback oplog: ${apiResult['error']}');
        await StorageService.resolveConflictLocally(
          uuid: uuid,
          table: widget.table,
          resolvedData: widget.serverItem!,
          createOplog: true,
          touchUpdatedAt: true,
        );
      }

      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        widget.onResolved();
        Future.microtask(() => StorageService.syncData(widget.username));
        if (!widget.isEmbedded) {
          Navigator.pop(context);
        }
        AppSnackBars.showSnackBarFromMessenger(
          messenger,
          const SnackBar(
            content: Text('已采用服务器版本，冲突已解决'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        AppSnackBars.showSnackBar(
          context,
          SnackBar(content: Text('操作失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isResolving = false);
    }
  }
}

class _ConflictFieldSpec {
  final String label;
  final List<String> keys;
  final String Function(dynamic value)? formatter;

  const _ConflictFieldSpec({
    required this.label,
    required this.keys,
    this.formatter,
  });
}

class _ConflictFieldDiff {
  final String label;
  final String localValue;
  final String serverValue;

  const _ConflictFieldDiff({
    required this.label,
    required this.localValue,
    required this.serverValue,
  });
}
