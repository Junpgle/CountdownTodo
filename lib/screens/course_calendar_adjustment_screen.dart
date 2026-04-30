import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/course_calendar_adjustment_service.dart';

class CourseCalendarAdjustmentScreen extends StatefulWidget {
  final String? initialOfficialHolidayKey;

  const CourseCalendarAdjustmentScreen({
    super.key,
    this.initialOfficialHolidayKey,
  });

  @override
  State<CourseCalendarAdjustmentScreen> createState() =>
      _CourseCalendarAdjustmentScreenState();
}

class _CourseCalendarAdjustmentScreenState
    extends State<CourseCalendarAdjustmentScreen> {
  final DateFormat _df = DateFormat('yyyy-MM-dd');
  CourseCalendarAdjustment _adjustment = CourseCalendarAdjustment.empty();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final adjustment = await CourseCalendarAdjustmentService.load();
    if (!mounted) return;
    setState(() {
      _adjustment = adjustment;
      _loading = false;
    });
  }

  Future<void> _save(CourseCalendarAdjustment adjustment) async {
    final officialHolidayKey = widget.initialOfficialHolidayKey;
    final nextAdjustment =
        officialHolidayKey == null || officialHolidayKey.isEmpty
            ? adjustment
            : adjustment.copyWith(
                handledOfficialHolidayKeys: {
                  ...adjustment.handledOfficialHolidayKeys,
                  officialHolidayKey,
                },
              );
    await CourseCalendarAdjustmentService.save(nextAdjustment);
    if (!mounted) return;
    setState(() => _adjustment = nextAdjustment);
  }

  Future<DateTime?> _pickDate({DateTime? initial}) {
    final now = DateTime.now();
    return showDatePicker(
      context: context,
      initialDate: initial ?? now,
      firstDate: DateTime(now.year - 2, 1, 1),
      lastDate: DateTime(now.year + 3, 12, 31),
    );
  }

  Future<void> _addHoliday() async {
    final action = await _showAddHolidaySheet();
    if (action == _AddAction.cancel) return;
    if (action != _AddAction.manual) return;

    final picked = await _pickDate();
    if (picked == null) return;
    final date = _df.format(picked);
    await _save(_adjustment.copyWith(
      holidayDates: {..._adjustment.holidayDates, date},
      holidayLabels: Map<String, String>.from(_adjustment.holidayLabels)
        ..remove(date),
    ));
  }

  Future<void> _addTransfer() async {
    final action = await _showAddTransferSheet();
    if (action == _AddAction.cancel) return;
    if (action != _AddAction.manual) return;

    final from = await _pickDate();
    if (from == null || !mounted) return;
    final to = await _pickDate(initial: from);
    if (to == null) return;
    await _save(_adjustment.copyWith(transfers: [
      ..._adjustment.transfers,
      CourseDayTransfer(fromDate: _df.format(from), toDate: _df.format(to)),
    ]));
  }

  Future<_AddAction> _showAddHolidaySheet() async {
    return await _showAddPanel(
          title: '添加放假日期',
          manualLabel: '手动选择日期',
          children: CourseCalendarAdjustmentService.officialWindows
              .map((window) => _HolidaySuggestionGroup(
                    window: window,
                    adjustment: _adjustment,
                    formatDateShort: _formatDateShort,
                    onAdd: (date) {
                      final labels =
                          Map<String, String>.from(_adjustment.holidayLabels);
                      labels[date] = window.name;
                      _save(_adjustment.copyWith(
                        holidayDates: {..._adjustment.holidayDates, date},
                        holidayLabels: labels,
                      ));
                    },
                  ))
              .toList(),
        ) ??
        _AddAction.cancel;
  }

  Future<_AddAction> _showAddTransferSheet() async {
    return await _showAddPanel(
          title: '添加调休补课',
          manualLabel: '手动选择调休',
          children: CourseCalendarAdjustmentService.officialWindows
              .where((window) => window.transfers.isNotEmpty)
              .map((window) => _TransferSuggestionGroup(
                    window: window,
                    adjustment: _adjustment,
                    onAdd: (transfer) {
                      _save(_adjustment.copyWith(
                        transfers: [..._adjustment.transfers, transfer],
                      ));
                    },
                  ))
              .toList(),
        ) ??
        _AddAction.cancel;
  }

  Future<_AddAction?> _showAddPanel({
    required String title,
    required String manualLabel,
    required List<Widget> children,
  }) {
    final width = MediaQuery.sizeOf(context).width;
    final sheet = _AddSheet(
      title: title,
      manualLabel: manualLabel,
      children: children,
    );

    if (width >= 700) {
      return showDialog<_AddAction>(
        context: context,
        builder: (ctx) => Dialog(
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 760,
              maxHeight: 640,
            ),
            child: sheet,
          ),
        ),
      );
    }

    return showModalBottomSheet<_AddAction>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => sheet,
    );
  }

  Future<void> _editTransfer(int index) async {
    final current = _adjustment.transfers[index];
    final from = await _pickDate(initial: _tryParseDate(current.fromDate));
    if (from == null || !mounted) return;
    final to = await _pickDate(initial: _tryParseDate(current.toDate) ?? from);
    if (to == null) return;

    final next = [..._adjustment.transfers];
    next[index] = CourseDayTransfer(
      fromDate: _df.format(from),
      toDate: _df.format(to),
      label: current.label,
    );
    await _save(_adjustment.copyWith(transfers: next));
  }

  DateTime? _tryParseDate(String value) {
    try {
      return _df.parseStrict(value);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('放假与调休')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1000),
                    child: Column(
                      children: [
                        _buildTopBar(),
                        const SizedBox(height: 12),
                        _buildCurrentPanel(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildTopBar() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.event_repeat_outlined),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${_adjustment.holidayDates.length} 天放假 · ${_adjustment.transfers.length} 条调休',
                style: const TextStyle(fontWeight: FontWeight.w700),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Row(
              children: [
                const Icon(Icons.campaign_outlined, size: 18),
                Switch(
                  value: _adjustment.officialHolidayPromptEnabled,
                  onChanged: (value) => _save(_adjustment.copyWith(
                    officialHolidayPromptEnabled: value,
                  )),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentPanel() {
    final holidays = _adjustment.holidayDates.toList()..sort();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 720;
            final holidayPanel = _buildHolidayPanel(holidays);
            final transferPanel = _buildTransferPanel();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _PanelHeader(
                  icon: Icons.tune_rounded,
                  title: '当前设置',
                ),
                const SizedBox(height: 12),
                if (wide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: holidayPanel),
                      const SizedBox(width: 20),
                      Expanded(child: transferPanel),
                    ],
                  )
                else ...[
                  holidayPanel,
                  const Divider(height: 28),
                  transferPanel,
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHolidayPanel(List<String> holidays) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PanelHeader(
          icon: Icons.free_cancellation_outlined,
          title: '放假日期',
        ),
        const SizedBox(height: 8),
        if (holidays.isEmpty)
          _EmptyLine(
            '未设置放假日期',
            action: TextButton.icon(
              onPressed: _addHoliday,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('添加'),
            ),
          )
        else ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: holidays.map((date) {
              final label = _adjustment.holidayLabels[date];
              return InputChip(
                label: Text(label == null || label.isEmpty
                    ? _formatDateShort(date)
                    : '$label ${_formatDateShort(date)}'),
                onDeleted: () {
                  final next = {..._adjustment.holidayDates}..remove(date);
                  final labels =
                      Map<String, String>.from(_adjustment.holidayLabels)
                        ..remove(date);
                  _save(_adjustment.copyWith(
                    holidayDates: next,
                    holidayLabels: labels,
                  ));
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _addHoliday,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('添加更多'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTransferPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PanelHeader(
          title: '调休补课',
          icon: Icons.swap_horiz_rounded,
        ),
        const SizedBox(height: 4),
        if (_adjustment.transfers.isEmpty)
          _EmptyLine(
            '未设置调休',
            action: TextButton.icon(
              onPressed: _addTransfer,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('添加'),
            ),
          )
        else ...[
          ..._adjustment.transfers.asMap().entries.map((entry) {
            final index = entry.key;
            final transfer = entry.value;
            return _TransferRowCompact(
              transfer: transfer,
              onEdit: () => _editTransfer(index),
              onDelete: () {
                final next = [..._adjustment.transfers]..removeAt(index);
                _save(_adjustment.copyWith(transfers: next));
              },
            );
          }),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _addTransfer,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('添加更多'),
            ),
          ),
        ],
      ],
    );
  }

  String _formatDateShort(String date) {
    final parsed = _tryParseDate(date);
    if (parsed == null) return date;
    return '${parsed.month}月${parsed.day}日';
  }
}

enum _AddAction { manual, cancel }

class _AddSheet extends StatelessWidget {
  final String title;
  final String manualLabel;
  final List<Widget> children;

  const _AddSheet({
    required this.title,
    required this.manualLabel,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: () =>
                          Navigator.pop(context, _AddAction.manual),
                      icon: const Icon(Icons.edit_calendar_outlined),
                      label: Text(manualLabel),
                    ),
                  ],
                ),
                if (children.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  if (constraints.maxWidth >= 620)
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: children
                          .map((child) => SizedBox(
                                width: (constraints.maxWidth - 44) / 2,
                                child: child,
                              ))
                          .toList(),
                    )
                  else
                    ...children,
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _HolidaySuggestionGroup extends StatelessWidget {
  final OfficialHolidayWindow window;
  final CourseCalendarAdjustment adjustment;
  final String Function(String date) formatDateShort;
  final ValueChanged<String> onAdd;

  const _HolidaySuggestionGroup({
    required this.window,
    required this.adjustment,
    required this.formatDateShort,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return _SuggestionGroup(
      title: window.name,
      subtitle: '${window.year} · ${window.holidayDates.length} 天',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: window.holidayDates.map((date) {
          final added = adjustment.holidayDates.contains(date);
          return ActionChip(
            avatar: Icon(added ? Icons.check : Icons.add, size: 18),
            label: Text(formatDateShort(date)),
            onPressed: added ? null : () => onAdd(date),
          );
        }).toList(),
      ),
    );
  }
}

class _TransferSuggestionGroup extends StatelessWidget {
  final OfficialHolidayWindow window;
  final CourseCalendarAdjustment adjustment;
  final ValueChanged<CourseDayTransfer> onAdd;

  const _TransferSuggestionGroup({
    required this.window,
    required this.adjustment,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return _SuggestionGroup(
      title: window.name,
      subtitle: '${window.year} · ${window.transfers.length} 条调休',
      child: Column(
        children: window.transfers.map((transfer) {
          final added = adjustment.transfers.any((item) =>
              item.fromDate == transfer.fromDate &&
              item.toDate == transfer.toDate);
          return _TransferRow(
            transfer: transfer,
            dense: true,
            added: added,
            onTap: added ? null : () => onAdd(transfer),
          );
        }).toList(),
      ),
    );
  }
}

class _SuggestionGroup extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _SuggestionGroup({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            Text(
              subtitle,
              style: TextStyle(
                color: Theme.of(context).colorScheme.outline,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  final IconData icon;
  final String title;

  const _PanelHeader({
    required this.icon,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      ],
    );
  }
}

class _TransferRow extends StatelessWidget {
  final CourseDayTransfer transfer;
  final VoidCallback? onTap;
  final bool dense;
  final bool added;

  const _TransferRow({
    required this.transfer,
    this.onTap,
    this.dense = false,
    this.added = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: dense,
      contentPadding: EdgeInsets.zero,
      leading: Icon(added ? Icons.check_circle_outline : Icons.swap_horiz),
      title: Text(transfer.label.isEmpty
          ? '${_short(transfer.fromDate)} 的课'
          : '${transfer.label}：${_short(transfer.fromDate)} 的课'),
      subtitle: Text('调到 ${_short(transfer.toDate)}'),
      onTap: onTap,
    );
  }

  String _short(String date) {
    try {
      final parsed = DateFormat('yyyy-MM-dd').parseStrict(date);
      return '${parsed.month}月${parsed.day}日';
    } catch (_) {
      return date;
    }
  }
}

class _EmptyLine extends StatelessWidget {
  final String text;
  final Widget? action;

  const _EmptyLine(this.text, {this.action});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}

class _TransferRowCompact extends StatelessWidget {
  final CourseDayTransfer transfer;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _TransferRowCompact({
    required this.transfer,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: const Icon(Icons.swap_horiz, size: 20),
        title: Text(
          transfer.label.isEmpty
              ? '${_short(transfer.fromDate)} 的课'
              : '${transfer.label}：${_short(transfer.fromDate)} 的课',
          style: const TextStyle(fontSize: 14),
        ),
        subtitle: Text(
          '调到 ${_short(transfer.toDate)}',
          style: const TextStyle(fontSize: 12),
        ),
        onTap: onEdit,
        trailing: IconButton(
          icon: const Icon(Icons.close, size: 18),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          onPressed: onDelete,
        ),
      ),
    );
  }

  String _short(String date) {
    try {
      final parsed = DateFormat('yyyy-MM-dd').parseStrict(date);
      return '${parsed.month}月${parsed.day}日';
    } catch (_) {
      return date;
    }
  }
}
