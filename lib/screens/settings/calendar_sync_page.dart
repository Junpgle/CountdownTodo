import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/browser_file_service.dart';
import '../../services/calendar_sync_service.dart';
import '../../services/permission_request_coordinator.dart';
import '../../storage_service.dart';
import '../../utils/app_platform.dart';

class CalendarSyncPage extends StatefulWidget {
  final bool isEmbedded;
  const CalendarSyncPage({super.key, this.isEmbedded = false});

  @override
  State<CalendarSyncPage> createState() => _CalendarSyncPageState();
}

class _CalendarSyncPageState extends State<CalendarSyncPage> {
  final Set<String> _selectedIds = {};
  List<CalendarSyncEntry> _entries = [];
  List<Map<String, dynamic>> _calendars = [];
  int? _calendarId;
  String? _username;
  bool _clearBeforeWrite = true;
  bool _loading = true;
  bool _working = false;
  String? _error;
  late final PermissionRequestCoordinator _permissionCoordinator;

  @override
  void initState() {
    super.initState();
    _permissionCoordinator = PermissionRequestCoordinator(context: context);
    _load();
  }

  @override
  void dispose() {
    _permissionCoordinator.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (AppPlatform.isWeb) {
      setState(() {
        _loading = true;
        _error = null;
      });

      try {
        final username = await StorageService.getCurrentUsername();
        if (username == null || username.isEmpty) {
          setState(() {
            _loading = false;
            _error = '请先登录后再导出日历';
          });
          return;
        }

        final entries = await CalendarSyncService.loadEntries(username);
        setState(() {
          _username = username;
          _entries = entries;
          _calendars = const [];
          _calendarId = null;
          _selectedIds
            ..clear()
            ..addAll(entries.map((entry) => entry.id));
          _loading = false;
        });
      } catch (e) {
        setState(() {
          _loading = false;
          _error = '加载失败：$e';
        });
      }
      return;
    }

    if (!AppPlatform.isAndroid) {
      setState(() {
        _loading = false;
        _error = '当前仅支持写入 Android 系统日历';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      var granted = await CalendarSyncService.checkPermission();
      if (!granted) {
        final result =
            await _permissionCoordinator.request(AppPermissionKind.calendar);
        granted = result.granted;
      }
      if (!granted) {
        setState(() {
          _loading = false;
          _error = '需要日历读写权限后才能同步';
        });
        return;
      }

      final username = await StorageService.getCurrentUsername();
      if (username == null || username.isEmpty) {
        setState(() {
          _loading = false;
          _error = '请先登录后再同步日历';
        });
        return;
      }

      final results = await Future.wait([
        CalendarSyncService.loadEntries(username),
        CalendarSyncService.getWritableCalendars(),
      ]);
      final entries = results[0] as List<CalendarSyncEntry>;
      final calendars = results[1] as List<Map<String, dynamic>>;

      setState(() {
        _username = username;
        _entries = entries;
        _calendars = calendars;
        _calendarId = calendars.isNotEmpty
            ? (calendars.first['id'] as num?)?.toInt()
            : null;
        _selectedIds
          ..clear()
          ..addAll(entries.map((entry) => entry.id));
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = '加载失败：$e';
      });
    }
  }

  Future<void> _writeSelected() async {
    final selected =
        _entries.where((entry) => _selectedIds.contains(entry.id)).toList();
    if (selected.isEmpty) {
      _showMessage('请至少选择一项');
      return;
    }

    setState(() => _working = true);
    try {
      final result = await CalendarSyncService.writeEntries(
        entries: selected,
        calendarId: _calendarId,
        clearFirst: _clearBeforeWrite,
      );
      final username = _username;
      if (username != null && username.isNotEmpty) {
        await CalendarSyncService.applyWrittenPlanBlockEventIds(
          username: username,
          eventIdsBySource: result.eventIdsBySource,
          clearExisting: _clearBeforeWrite,
        );
      }
      _showMessage(
        '已写入 ${result.inserted} 项'
        '${result.cleared > 0 ? '，已清除旧内容 ${result.cleared} 项' : ''}'
        '${result.failed > 0 ? '，失败 ${result.failed} 项' : ''}',
      );
    } catch (e) {
      _showMessage('写入失败：$e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _exportSelectedIcs() async {
    final selected =
        _entries.where((entry) => _selectedIds.contains(entry.id)).toList();
    if (selected.isEmpty) {
      _showMessage('请至少选择一项');
      return;
    }

    setState(() => _working = true);
    try {
      final fileName =
          'countdowntodo-calendar-${DateFormat('yyyyMMdd-HHmmss').format(DateTime.now())}.ics';
      await BrowserFileService.saveTextFile(
        _buildIcs(selected),
        fileName,
        mimeType: 'text/calendar;charset=utf-8',
      );
      _showMessage('已导出 ${selected.length} 项到 $fileName');
    } catch (e) {
      _showMessage('导出失败：$e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _previewSelected() async {
    final selected =
        _entries.where((entry) => _selectedIds.contains(entry.id)).toList();
    if (selected.isEmpty) {
      _showMessage('请至少选择一项');
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '预览写入内容 · ${selected.length} 项',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: selected.length,
                    separatorBuilder: (_, __) => const Divider(height: 16),
                    itemBuilder: (context, index) {
                      final entry = selected[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          _iconFor(entry.type),
                          color: _colorFor(entry.type),
                        ),
                        title: Text(
                          entry.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          [
                            '${entry.typeLabel} · ${_formatEntryTime(entry)}',
                            if (entry.location?.isNotEmpty == true)
                              '地点：${entry.location}',
                            if (entry.description?.isNotEmpty == true)
                              entry.description!,
                          ].join('\n'),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      if (AppPlatform.isWeb) {
                        _exportSelectedIcs();
                      } else {
                        _writeSelected();
                      }
                    },
                    icon: Icon(AppPlatform.isWeb
                        ? Icons.download_outlined
                        : Icons.event_available_outlined),
                    label: Text(AppPlatform.isWeb ? '确认导出' : '确认写入'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除已写入日历'),
        content: const Text('将删除本软件此前写入系统日历的内容，不会删除其他日历事件。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _working = true);
    try {
      final count = await CalendarSyncService.clearAppEvents(
        calendarId: _calendarId,
      );
      _showMessage('已清除 $count 项');
    } catch (e) {
      _showMessage('清除失败：$e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _toggleType(CalendarSyncEntryType type, bool selected) {
    setState(() {
      for (final entry in _entries.where((entry) => entry.type == type)) {
        if (selected) {
          _selectedIds.add(entry.id);
        } else {
          _selectedIds.remove(entry.id);
        }
      }
    });
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.isEmbedded
          ? null
          : AppBar(
              title: Text(AppPlatform.isWeb ? '导出日历文件' : '写入系统日历'),
              actions: [
                IconButton(
                  tooltip: '刷新',
                  onPressed: _working ? null : _load,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
      body: _buildBody(),
      bottomNavigationBar: _loading || _error != null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Row(
                  children: [
                    if (!AppPlatform.isWeb) ...[
                      OutlinedButton.icon(
                        onPressed: _working ? null : _clearAll,
                        icon: const Icon(Icons.delete_sweep_outlined),
                        label: const Text('一键清除'),
                      ),
                      const SizedBox(width: 12),
                    ],
                    OutlinedButton.icon(
                      onPressed: _working ? null : _previewSelected,
                      icon: const Icon(Icons.visibility_outlined),
                      label: const Text('预览'),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _working
                            ? null
                            : (AppPlatform.isWeb
                                ? _exportSelectedIcs
                                : _writeSelected),
                        icon: _working
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(AppPlatform.isWeb
                                ? Icons.download_outlined
                                : Icons.event_available_outlined),
                        label: Text(AppPlatform.isWeb
                            ? '导出所选 ${_selectedIds.length} 项'
                            : '写入所选 ${_selectedIds.length} 项'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(AppPlatform.isWeb
              ? Icons.download_outlined
              : Icons.event_available_outlined),
          title: Text(AppPlatform.isWeb ? '选择导出内容' : '选择写入目标'),
          subtitle: Text(AppPlatform.isWeb
              ? '导出为 .ics 文件后，可导入 Apple 日历、Google Calendar、Outlook 等日历应用。'
              : '下面列表会显示系统识别到的日历，当前只保留这一处选择入口'),
        ),
        if (!AppPlatform.isWeb)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _clearBeforeWrite,
            title: const Text('写入前清除本软件已写入内容'),
            subtitle: const Text('避免重复事件；只清除带有 CountDownTodo 标记的事件'),
            onChanged: _working
                ? null
                : (value) => setState(() => _clearBeforeWrite = value),
          ),
        const SizedBox(height: 8),
        _buildQuickSelect(),
        const SizedBox(height: 8),
        if (_calendars.isNotEmpty) ...[
          const Text('可用日历', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          ..._calendars.map(
            (calendar) {
              final id = (calendar['id'] as num).toInt();
              final selected = _calendarId == id;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(
                  calendar['writable'] == true
                      ? Icons.edit_calendar_outlined
                      : Icons.visibility_outlined,
                ),
                title: Text(calendar['name']?.toString() ?? '日历'),
                subtitle: Text([
                  if ((calendar['account']?.toString() ?? '').isNotEmpty)
                    calendar['account'].toString(),
                  if (calendar['writable'] == true) '可写' else '只读',
                ].join(' · ')),
                trailing: selected
                    ? Icon(
                        Icons.check_circle,
                        color: Theme.of(context).colorScheme.primary,
                      )
                    : null,
                onTap: _working ? null : () => setState(() => _calendarId = id),
              );
            },
          ),
          const SizedBox(height: 8),
        ],
        if (_entries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Center(
              child: Text(AppPlatform.isWeb
                  ? '暂无可导出为日历的待办、课程、倒数日或规划块'
                  : '暂无可写入日历的待办、课程、倒数日或规划块'),
            ),
          )
        else
          ..._entries.map(_buildEntryTile),
      ],
    );
  }

  Widget _buildQuickSelect() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ActionChip(
          avatar: const Icon(Icons.done_all, size: 18),
          label: const Text('全选'),
          onPressed: _working
              ? null
              : () => setState(() {
                    _selectedIds
                      ..clear()
                      ..addAll(_entries.map((entry) => entry.id));
                  }),
        ),
        ActionChip(
          avatar: const Icon(Icons.remove_done, size: 18),
          label: const Text('全不选'),
          onPressed: _working ? null : () => setState(_selectedIds.clear),
        ),
        FilterChip(
          label: const Text('待办'),
          selected: _isTypeFullySelected(CalendarSyncEntryType.todo),
          onSelected: _working
              ? null
              : (selected) => _toggleType(CalendarSyncEntryType.todo, selected),
        ),
        FilterChip(
          label: const Text('课程'),
          selected: _isTypeFullySelected(CalendarSyncEntryType.course),
          onSelected: _working
              ? null
              : (selected) =>
                  _toggleType(CalendarSyncEntryType.course, selected),
        ),
        FilterChip(
          label: const Text('倒数日'),
          selected: _isTypeFullySelected(CalendarSyncEntryType.countdown),
          onSelected: _working
              ? null
              : (selected) =>
                  _toggleType(CalendarSyncEntryType.countdown, selected),
        ),
        FilterChip(
          label: const Text('规划'),
          selected: _isTypeFullySelected(CalendarSyncEntryType.planBlock),
          onSelected: _working
              ? null
              : (selected) =>
                  _toggleType(CalendarSyncEntryType.planBlock, selected),
        ),
      ],
    );
  }

  bool _isTypeFullySelected(CalendarSyncEntryType type) {
    final typed = _entries.where((entry) => entry.type == type).toList();
    return typed.isNotEmpty &&
        typed.every((entry) => _selectedIds.contains(entry.id));
  }

  Widget _buildEntryTile(CalendarSyncEntry entry) {
    final selected = _selectedIds.contains(entry.id);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: CheckboxListTile(
        value: selected,
        onChanged: _working
            ? null
            : (value) {
                setState(() {
                  if (value == true) {
                    _selectedIds.add(entry.id);
                  } else {
                    _selectedIds.remove(entry.id);
                  }
                });
              },
        title: Text(entry.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text('${entry.typeLabel} · ${_formatEntryTime(entry)}'),
        secondary: Icon(_iconFor(entry.type), color: _colorFor(entry.type)),
        controlAffinity: ListTileControlAffinity.trailing,
      ),
    );
  }

  IconData _iconFor(CalendarSyncEntryType type) {
    switch (type) {
      case CalendarSyncEntryType.todo:
        return Icons.check_circle_outline;
      case CalendarSyncEntryType.course:
        return Icons.school_outlined;
      case CalendarSyncEntryType.countdown:
        return Icons.event_outlined;
      case CalendarSyncEntryType.planBlock:
        return Icons.event_note_outlined;
    }
  }

  Color _colorFor(CalendarSyncEntryType type) {
    switch (type) {
      case CalendarSyncEntryType.todo:
        return Theme.of(context).colorScheme.primary;
      case CalendarSyncEntryType.course:
        return Colors.indigo;
      case CalendarSyncEntryType.countdown:
        return Colors.orange;
      case CalendarSyncEntryType.planBlock:
        return Colors.teal;
    }
  }

  String _formatEntryTime(CalendarSyncEntry entry) {
    final dateFormat = DateFormat('yyyy-MM-dd');
    final timeFormat = DateFormat('HH:mm');
    final dateTimeFormat = DateFormat('yyyy-MM-dd HH:mm');

    if (entry.allDay) {
      final inclusiveEnd = entry.end.subtract(const Duration(days: 1));
      final startDate = dateFormat.format(entry.start);
      if (_isSameDate(entry.start, inclusiveEnd)) return '$startDate 全天';
      return '$startDate 至 ${dateFormat.format(inclusiveEnd)} 全天';
    }

    if (_isSameDate(entry.start, entry.end)) {
      return '${dateFormat.format(entry.start)} '
          '${timeFormat.format(entry.start)}-${timeFormat.format(entry.end)}';
    }
    return '${dateTimeFormat.format(entry.start)} 至 '
        '${dateTimeFormat.format(entry.end)}';
  }

  bool _isSameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _buildIcs(List<CalendarSyncEntry> entries) {
    final lines = <String>[
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//CountDownTodo//Calendar Export//CN',
      'CALSCALE:GREGORIAN',
      'METHOD:PUBLISH',
      'X-WR-CALNAME:${_escapeIcsText('CountDownTodo')}',
      'X-WR-TIMEZONE:${_escapeIcsText(DateTime.now().timeZoneName)}',
    ];
    final stamp = _formatIcsDateTime(DateTime.now().toUtc());

    for (final entry in entries) {
      lines
        ..add('BEGIN:VEVENT')
        ..add(
          'UID:${_escapeIcsText('${entry.type.name}-${entry.id}@countdowntodo')}',
        )
        ..add('DTSTAMP:$stamp')
        ..add('SUMMARY:${_escapeIcsText(entry.title)}')
        ..add('CATEGORIES:${_escapeIcsText(entry.typeLabel)}');

      if (entry.allDay) {
        lines
          ..add('DTSTART;VALUE=DATE:${_formatIcsDate(entry.start)}')
          ..add('DTEND;VALUE=DATE:${_formatIcsDate(entry.end)}');
      } else {
        lines
          ..add('DTSTART:${_formatIcsDateTime(entry.start.toUtc())}')
          ..add('DTEND:${_formatIcsDateTime(entry.end.toUtc())}');
      }

      if (entry.location?.trim().isNotEmpty == true) {
        lines.add('LOCATION:${_escapeIcsText(entry.location!.trim())}');
      }
      if (entry.description?.trim().isNotEmpty == true) {
        lines.add('DESCRIPTION:${_escapeIcsText(entry.description!.trim())}');
      }
      lines.add('END:VEVENT');
    }

    lines.add('END:VCALENDAR');
    return '${lines.expand(_foldIcsLine).join('\r\n')}\r\n';
  }

  String _formatIcsDate(DateTime date) => DateFormat('yyyyMMdd').format(date);

  String _formatIcsDateTime(DateTime dateTime) =>
      DateFormat("yyyyMMdd'T'HHmmss'Z'").format(dateTime.toUtc());

  String _escapeIcsText(String value) {
    return value
        .replaceAll('\\', '\\\\')
        .replaceAll('\r\n', r'\n')
        .replaceAll('\n', r'\n')
        .replaceAll(';', r'\;')
        .replaceAll(',', r'\,');
  }

  List<String> _foldIcsLine(String line) {
    const maxLength = 72;
    if (line.length <= maxLength) return [line];
    final folded = <String>[];
    var rest = line;
    while (rest.length > maxLength) {
      folded.add(rest.substring(0, maxLength));
      rest = ' ${rest.substring(maxLength)}';
    }
    folded.add(rest);
    return folded;
  }
}
