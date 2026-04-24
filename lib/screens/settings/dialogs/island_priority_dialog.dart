import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class IslandPriorityDialog extends StatefulWidget {
  const IslandPriorityDialog({super.key});

  @override
  State<IslandPriorityDialog> createState() => _IslandPriorityDialogState();
}

class _IslandPriorityDialogState extends State<IslandPriorityDialog> {
  List<String> _items = [
    'course',
    'countdown',
    'todo',
    'focus',
    'date',
    'weekday'
  ];

  final Map<String, String> _labels = {
    'course': '课程表',
    'countdown': '倒计时',
    'todo': '待办事项',
    'focus': '专注时间',
    'date': '公历日期',
    'weekday': '星期',
  };

  final Map<String, IconData> _icons = {
    'course': Icons.book_outlined,
    'countdown': Icons.timer_outlined,
    'todo': Icons.check_box_outlined,
    'focus': Icons.psychology_outlined,
    'date': Icons.calendar_today_outlined,
    'weekday': Icons.calendar_view_week_outlined,
  };

  @override
  void initState() {
    super.initState();
    _loadPriority();
  }

  Future<void> _loadPriority() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('island_slot_priority');
    if (saved != null && saved.isNotEmpty) {
      // Ensure all valid items exist
      final valid = saved.where((e) => _labels.containsKey(e)).toList();
      for (var k in _labels.keys) {
        if (!valid.contains(k)) valid.add(k);
      }
      setState(() {
        _items = valid;
      });
    }
  }

  Future<void> _savePriority() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('island_slot_priority', _items);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('✨ 灵动岛信息流优先级'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '拖拽下方卡片进行排序。灵动岛会在闲置和展开状态时，从上往下依次尝试获取数据。获取到的第一个显示在左侧，第二个显示在右侧。',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: ReorderableListView(
                shrinkWrap: true,
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    if (oldIndex < newIndex) {
                      newIndex -= 1;
                    }
                    final item = _items.removeAt(oldIndex);
                    _items.insert(newIndex, item);
                  });
                },
                children: [
                  for (int i = 0; i < _items.length; i++)
                    Card(
                      key: ValueKey(_items[i]),
                      elevation: 1,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        leading: Icon(_icons[_items[i]] ?? Icons.info_outline),
                        title: Text(_labels[_items[i]] ?? _items[i]),
                        leadingAndTrailingTextStyle:
                            const TextStyle(fontSize: 14),
                        trailing:
                            const Icon(Icons.drag_handle, color: Colors.grey),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () async {
            await _savePriority();
            Navigator.of(context).pop(true);
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}
