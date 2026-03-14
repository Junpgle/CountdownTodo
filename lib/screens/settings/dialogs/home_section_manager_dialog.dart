import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomeSectionManagerDialog extends StatefulWidget {
  const HomeSectionManagerDialog({Key? key}) : super(key: key);

  @override
  State<HomeSectionManagerDialog> createState() => _HomeSectionManagerDialogState();
}

class _HomeSectionManagerDialogState extends State<HomeSectionManagerDialog> {
  List<String>? leftOrder;
  List<String>? rightOrder;
  List<String> mobileCombinedOrder = [];
  Map<String, bool> visibility = {};
  bool isLoading = true;

  final List<String> defaultOrder = [
    'courses',
    'countdowns',
    'todos',
    'screenTime',
    'math',
    'pomodoro'
  ];

  final Map<String, String> names = {
    'courses': '课程提醒',
    'countdowns': '重要日与倒计时',
    'todos': '待办事项清单',
    'screenTime': '屏幕时间面板',
    'math': '数学测验入口',
    'pomodoro': '今日专注统计',
  };

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    
    leftOrder = prefs.getStringList('home_section_order_left');
    rightOrder = prefs.getStringList('home_section_order_right');

    if (leftOrder == null || rightOrder == null) {
      List<String> oldOrder = prefs.getStringList('home_section_order') ?? defaultOrder;
      leftOrder = [];
      rightOrder = [];
      for (int i = 0; i < oldOrder.length; i++) {
        if (i % 2 == 0) {
          leftOrder!.add(oldOrder[i]);
        } else {
          rightOrder!.add(oldOrder[i]);
        }
      }
    }

    List<String> combined = [...leftOrder!, ...rightOrder!];
    for (var key in defaultOrder) {
      if (!combined.contains(key)) leftOrder!.add(key);
    }
    leftOrder!.removeWhere((key) => !defaultOrder.contains(key));
    rightOrder!.removeWhere((key) => !defaultOrder.contains(key));

    mobileCombinedOrder = [...leftOrder!, ...rightOrder!];

    visibility = {
      'courses': true,
      'countdowns': true,
      'todos': true,
      'screenTime': true,
      'math': true,
      'pomodoro': true
    };
    String? visStr = prefs.getString('home_section_visibility');
    if (visStr != null) visibility = Map<String, bool>.from(jsonDecode(visStr));
    for (var key in defaultOrder) visibility.putIfAbsent(key, () => true);

    setState(() => isLoading = false);
  }

  void moveItem(String item, {String? targetKey, bool? toLeftList}) {
    setState(() {
      leftOrder!.remove(item);
      rightOrder!.remove(item);
      if (targetKey != null) {
        if (leftOrder!.contains(targetKey)) {
          leftOrder!.insert(leftOrder!.indexOf(targetKey), item);
        } else if (rightOrder!.contains(targetKey)) {
          rightOrder!.insert(rightOrder!.indexOf(targetKey), item);
        }
      } else if (toLeftList != null) {
        if (toLeftList)
          leftOrder!.add(item);
        else
          rightOrder!.add(item);
      }
    });
  }

  Widget buildDraggableItem(String key) {
    return LongPressDraggable<String>(
      data: key,
      delay: const Duration(milliseconds: 200),
      feedback: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(8),
        color: Colors.transparent,
        child: Container(
          width: 250,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.9),
              borderRadius: BorderRadius.circular(8)),
          child: Text(names[key] ?? key,
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onPrimaryContainer)),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: CheckboxListTile(
            title: Text(names[key] ?? key),
            value: visibility[key],
            onChanged: null),
      ),
      child: DragTarget<String>(
          onWillAccept: (data) => data != key,
          onAccept: (data) => moveItem(data, targetKey: key),
          builder: (context, candidateData, rejectedData) {
            return Container(
              decoration: BoxDecoration(
                border: candidateData.isNotEmpty
                    ? Border(
                    top: BorderSide(
                        color: Theme.of(context).colorScheme.primary,
                        width: 3))
                    : null,
              ),
              child: CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(names[key] ?? key,
                    style: const TextStyle(fontSize: 14)),
                value: visibility[key],
                secondary: const Icon(Icons.drag_indicator,
                    color: Colors.grey, size: 20),
                onChanged: (val) => setState(() => visibility[key] = val ?? true),
              ),
            );
          }),
    );
  }

  Widget buildDragColumn(List<String> items, bool isLeft) {
    return Expanded(
      child: DragTarget<String>(
          onWillAccept: (data) => true,
          onAccept: (data) => moveItem(data, toLeftList: isLeft),
          builder: (context, candidateData, rejectedData) {
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.only(bottom: 60),
              decoration: BoxDecoration(
                color: candidateData.isNotEmpty
                    ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.1)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(isLeft ? "屏幕左栏" : "屏幕右栏",
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.grey)),
                  ),
                  ...items.map((key) => buildDraggableItem(key)),
                ],
              ),
            );
          }),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const AlertDialog(
        content: SizedBox(
          height: 100,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final bool isTablet = MediaQuery.of(context).size.width >= 768;

    return AlertDialog(
      title: const Text("首页模块管理"),
      content: SizedBox(
        width: isTablet ? 600 : double.maxFinite,
        height: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: Text(
                  isTablet
                      ? "长按模块，可跨越左右栏进行拖拽。\n勾选控制该模块是否在首页展示。"
                      : "长按右侧把手拖拽改变顺序，勾选控制是否展示。",
                  style: const TextStyle(color: Colors.grey, fontSize: 13)),
            ),
            Expanded(
              child: isTablet
                  ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  buildDragColumn(leftOrder!, true),
                  buildDragColumn(rightOrder!, false),
                ],
              )
                  : ReorderableListView(
                shrinkWrap: true,
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    if (newIndex > oldIndex) newIndex -= 1;
                    final item = mobileCombinedOrder.removeAt(oldIndex);
                    mobileCombinedOrder.insert(newIndex, item);
                  });
                },
                children: mobileCombinedOrder.map((key) {
                  return CheckboxListTile(
                    key: Key(key),
                    contentPadding: EdgeInsets.zero,
                    title: Text(names[key] ?? key),
                    value: visibility[key] ?? true,
                    secondary: const Icon(Icons.drag_handle, color: Colors.grey),
                    onChanged: (val) {
                      setState(() => visibility[key] = val ?? true);
                    },
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("取消")),
        FilledButton(
          onPressed: () async {
            final prefs = await SharedPreferences.getInstance();
            if (!isTablet) {
              leftOrder!.clear();
              rightOrder!.clear();
              int mid = (mobileCombinedOrder.length / 2).ceil();
              for (int i = 0; i < mobileCombinedOrder.length; i++) {
                if (i < mid)
                  leftOrder!.add(mobileCombinedOrder[i]);
                else
                  rightOrder!.add(mobileCombinedOrder[i]);
              }
            }

            await prefs.setStringList('home_section_order_left', leftOrder!);
            await prefs.setStringList('home_section_order_right', rightOrder!);
            await prefs.setString('home_section_visibility', jsonEncode(visibility));
            
            if (context.mounted) {
              Navigator.pop(context, true);
            }
          },
          child: const Text("保存并应用"),
        )
      ],
    );
  }
}
