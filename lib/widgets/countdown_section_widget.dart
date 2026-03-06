import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models.dart';
import '../../storage_service.dart';
import '../screens/historical_countdowns_screen.dart';
import '../widgets/home_sections.dart';

class CountdownSectionWidget extends StatefulWidget {
  final List<CountdownItem> countdowns;
  final String username;
  final bool isLight;
  final VoidCallback onDataChanged;

  const CountdownSectionWidget({
    super.key,
    required this.countdowns,
    required this.username,
    required this.isLight,
    required this.onDataChanged,
  });

  @override
  State<CountdownSectionWidget> createState() => _CountdownSectionWidgetState();
}

class _CountdownSectionWidgetState extends State<CountdownSectionWidget> {

  void _addCountdown() {
    TextEditingController titleCtrl = TextEditingController();
    DateTime selectedDate = DateTime.now().add(const Duration(days: 1));
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("添加倒计时"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: "事项名称")),
              ListTile(
                title: Text("目标日期: ${DateFormat('yyyy-MM-dd').format(selectedDate)}"), trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final picked = await showDatePicker(context: context, firstDate: DateTime.now(), lastDate: DateTime(2100), initialDate: selectedDate);
                  if (picked != null) setDialogState(() => selectedDate = picked);
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("取消")),
            FilledButton(
              onPressed: () async {
                if (titleCtrl.text.isNotEmpty) {
                  List<CountdownItem> updatedList = List.from(widget.countdowns);
                  // 🚀 修复：去除旧版的 lastUpdated 属性，采用模型的默认版本号初始化
                  updatedList.add(CountdownItem(title: titleCtrl.text, targetDate: selectedDate));
                  await StorageService.saveCountdowns(widget.username, updatedList);
                  widget.onDataChanged(); // 通知父组件更新
                  if (mounted) Navigator.pop(ctx);
                }
              },
              child: const Text("添加"),
            ),
          ],
        ),
      ),
    );
  }

  void _deleteCountdown(CountdownItem itemToDelete) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("删除倒计时"),
        content: const Text("确定要删除这条倒计时吗？"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("取消")),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              // 🚀 修复：使用 ID 而非 title 来删除倒计时
              await StorageService.deleteCountdownGlobally(widget.username, itemToDelete.id);
              widget.onDataChanged();
              if (mounted) Navigator.pop(ctx);
            },
            child: const Text("删除"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: SectionHeader(title: "重要日", icon: Icons.timer, onAdd: _addCountdown, isLight: widget.isLight)),
            IconButton(
              icon: Icon(Icons.history, color: widget.isLight ? Colors.white70 : Colors.grey),
              onPressed: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => HistoricalCountdownsScreen(username: widget.username)));
                widget.onDataChanged();
              },
            ),
          ],
        ),
        _buildList(),
      ],
    );
  }

  Widget _buildList() {
    final List<CountdownItem> activeCountdowns = widget.countdowns.where((item) {
      return item.targetDate.difference(DateTime.now()).inDays + 1 >= 0;
    }).toList()
      ..sort((a, b) => a.targetDate.compareTo(b.targetDate));

    if (activeCountdowns.isEmpty) return EmptyState(text: "暂无有效倒计时", isLight: widget.isLight);

    return SizedBox(
      height: 110,
      child: ListView.builder(
        scrollDirection: Axis.horizontal, itemCount: activeCountdowns.length,
        itemBuilder: (context, index) {
          final item = activeCountdowns[index];
          final diff = item.targetDate.difference(DateTime.now()).inDays + 1;

          return Stack(
            children: [
              Card(
                color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.9), margin: const EdgeInsets.only(right: 12),
                child: Container(
                  width: 140, padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 16.0),
                        child: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Theme.of(context).colorScheme.onPrimaryContainer)),
                      ),
                      const Spacer(),
                      Text("$diff天", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onPrimaryContainer)),
                      Text("目标日: ${DateFormat('MM-dd').format(item.targetDate)}", style: const TextStyle(fontSize: 10)),
                    ],
                  ),
                ),
              ),
              Positioned(
                right: 16,
                top: 4,
                child: InkWell(
                  onTap: () => _deleteCountdown(item),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.close, size: 16, color: Theme.of(context).colorScheme.onPrimaryContainer.withOpacity(0.5)),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}