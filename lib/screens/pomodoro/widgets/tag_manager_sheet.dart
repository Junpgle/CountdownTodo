import 'package:flutter/material.dart';
import '../../../services/pomodoro_service.dart';
import '../pomodoro_utils.dart';

class TagManagerSheet extends StatefulWidget {
  final List<PomodoroTag> allTags;
  final List<String> selectedUuids;
  final void Function(List<PomodoroTag>, List<String>) onChanged;

  const TagManagerSheet({
    super.key,
    required this.allTags,
    required this.selectedUuids,
    required this.onChanged,
  });

  @override
  State<TagManagerSheet> createState() => _TagManagerSheetState();
}

class _TagManagerSheetState extends State<TagManagerSheet> {
  late List<PomodoroTag> _tags;
  late List<String> _selected;

  static const List<String> _presetColors = [
    '#F44336', '#E91E63', '#9C27B0', '#3F51B5',
    '#2196F3', '#009688', '#4CAF50', '#FF9800',
    '#607D8B', '#795548',
  ];

  @override
  void initState() {
    super.initState();
    _tags = List.from(widget.allTags);
    _selected = List.from(widget.selectedUuids);
  }

  void _addTag() {
    final ctrl = TextEditingController();
    String pickedColor = _presetColors[0];
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, sd) => AlertDialog(
          title: const Text('新增标签'),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                decoration: InputDecoration(
                  labelText: '标签名称',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: _presetColors.map((c) {
                  final col = hexToColor(c);
                  return GestureDetector(
                    onTap: () => sd(() => pickedColor = c),
                    child: CircleAvatar(
                      radius: 18,
                      backgroundColor: col,
                      child: pickedColor == c
                          ? const Icon(Icons.check, color: Colors.white, size: 20)
                          : null,
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () {
                if (ctrl.text.trim().isNotEmpty) {
                  final tag = PomodoroTag(name: ctrl.text.trim(), color: pickedColor);
                  setState(() => _tags.add(tag));
                  widget.onChanged(_tags, _selected);
                  Navigator.pop(ctx);
                }
              },
              child: const Text('添加'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: MediaQuery.of(context).viewInsets,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('管理标签', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.add_circle),
                  color: Theme.of(context).colorScheme.primary,
                  iconSize: 28,
                  onPressed: _addTag,
                ),
              ],
            ),
          ),
          const Divider(),
          if (_tags.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Text('还没有标签，点击右上角添加', style: TextStyle(color: Colors.grey)),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ReorderableListView.builder(
                shrinkWrap: true,
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    if (newIndex > oldIndex) newIndex--;
                    final tag = _tags.removeAt(oldIndex);
                    _tags.insert(newIndex, tag);
                  });
                  widget.onChanged(_tags, _selected);
                },
                itemCount: _tags.length,
                itemBuilder: (_, i) {
                  final tag = _tags[i];
                  final color = hexToColor(tag.color);
                  return ListTile(
                    key: ValueKey(tag.uuid),
                    leading: CircleAvatar(radius: 8, backgroundColor: color),
                    title: Text(tag.name),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Checkbox(
                          value: _selected.contains(tag.uuid),
                          activeColor: color,
                          onChanged: (val) {
                            setState(() {
                              if (val == true) {
                                _selected.add(tag.uuid);
                              } else {
                                _selected.remove(tag.uuid);
                              }
                            });
                            widget.onChanged(_tags, _selected);
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20, color: Colors.grey),
                          onPressed: () {
                            setState(() {
                              _selected.remove(tag.uuid);
                              _tags.removeAt(i);
                            });
                            widget.onChanged(_tags, _selected);
                          },
                        ),
                        const Icon(Icons.drag_handle, size: 20, color: Colors.grey),
                        const SizedBox(width: 4),
                      ],
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
