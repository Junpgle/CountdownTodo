import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../../../services/pomodoro_service.dart';
import '../../../utils/app_color_utils.dart';

class UnifiedTagManagerSheet extends StatefulWidget {
  final List<PomodoroTag> allTags;
  final List<String> selectedUuids;
  final void Function(List<PomodoroTag>, List<String>)? onChanged;
  final List<PomodoroRecord>? pomodoroRecords;
  final bool showSelection;
  final bool showBatchTag;
  final bool showArchive;

  const UnifiedTagManagerSheet({
    super.key,
    required this.allTags,
    this.selectedUuids = const [],
    this.onChanged,
    this.pomodoroRecords,
    this.showSelection = false,
    this.showBatchTag = false,
    this.showArchive = true,
  });

  @override
  State<UnifiedTagManagerSheet> createState() => _UnifiedTagManagerSheetState();
}

class _UnifiedTagManagerSheetState extends State<UnifiedTagManagerSheet>
    with SingleTickerProviderStateMixin {
  late List<PomodoroTag> _tags;
  late List<String> _selected;
  late List<PomodoroTag> _archivedTags;
  final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();
  final TextEditingController _nameController = TextEditingController();
  String _newColor = _presetColors[0];
  bool _showColorPicker = false;
  String? _editingColorTagUuid;

  static const List<String> _presetColors = [
    '#F44336',
    '#E91E63',
    '#9C27B0',
    '#3F51B5',
    '#2196F3',
    '#009688',
    '#4CAF50',
    '#FF9800',
    '#607D8B',
    '#795548',
  ];

  static const List<String> _extendedColors = [
    '#EF5350',
    '#EC407A',
    '#AB47BC',
    '#5C6BC0',
    '#42A5F5',
    '#26A69A',
    '#66BB6A',
    '#FFA726',
    '#78909C',
    '#8D6E63',
    '#F48FB1',
    '#CE93D8',
    '#9FA8DA',
    '#81D4FA',
    '#80CBC4',
    '#A5D6A7',
    '#FFCC80',
    '#BCAAA4',
    '#B0BEC5',
    '#D7CCC8',
  ];

  @override
  void initState() {
    super.initState();
    _tags = List.from(widget.allTags);
    _selected = List.from(widget.selectedUuids);
    _archivedTags = [];
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _addTag() {
    if (_nameController.text.trim().isEmpty) return;
    final tag = PomodoroTag(
      uuid: 'tag_${DateTime.now().millisecondsSinceEpoch}',
      name: _nameController.text.trim(),
      color: _newColor,
    );
    setState(() {
      _tags.add(tag);
      _nameController.clear();
    });
    _listKey.currentState?.insertItem(
      _tags.length - 1,
      duration: const Duration(milliseconds: 300),
    );
    widget.onChanged?.call(_tags, _selected);
  }

  void _deleteTag(int index) {
    final tag = _tags[index];
    _listKey.currentState?.removeItem(
      index,
      (_, animation) => _buildRemovedItem(tag, animation),
      duration: const Duration(milliseconds: 250),
    );
    setState(() {
      _selected.remove(tag.uuid);
      _tags.removeAt(index);
      if (widget.showArchive) {
        _archivedTags.add(tag);
      }
    });
    widget.onChanged?.call(_tags, _selected);
  }

  void _restoreTag(PomodoroTag tag) {
    setState(() {
      _archivedTags.remove(tag);
      _tags.add(tag);
    });
    _listKey.currentState?.insertItem(
      _tags.length - 1,
      duration: const Duration(milliseconds: 300),
    );
    widget.onChanged?.call(_tags, _selected);
  }

  void _batchAddTagToUntagged() {
    if (widget.pomodoroRecords == null || _tags.isEmpty) return;
    
    final untaggedRecords = widget.pomodoroRecords!
        .where((r) => r.tagUuids.isEmpty)
        .toList();
    
    if (untaggedRecords.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有未标签的番茄钟记录')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => _BatchTagDialog(
        tags: _tags,
        untaggedCount: untaggedRecords.length,
        onConfirm: (tagUuid) {
          // TODO: 实际保存到数据库
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已为 ${untaggedRecords.length} 条记录添加标签')),
          );
          Navigator.pop(ctx);
        },
      ),
    );
  }

  void _openCustomColorPicker({String? forTagUuid}) {
    setState(() {
      _editingColorTagUuid = forTagUuid;
      _showColorPicker = true;
    });
  }

  void _onCustomColorSelected(String hex) {
    if (_editingColorTagUuid != null) {
      final index = _tags.indexWhere((t) => t.uuid == _editingColorTagUuid);
      if (index >= 0) {
        setState(() {
          _tags[index] = PomodoroTag(
            uuid: _tags[index].uuid,
            name: _tags[index].name,
            color: hex,
          );
        });
        widget.onChanged?.call(_tags, _selected);
      }
    } else {
      setState(() => _newColor = hex);
    }
    setState(() => _showColorPicker = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_showColorPicker) {
      return _buildColorPicker();
    }

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Padding(
        padding: MediaQuery.of(context).viewInsets,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            const Divider(),
            if (_tags.isEmpty)
              _buildEmptyState()
            else
              _buildTagList(),
            _buildAddSection(),
            if (widget.showArchive && _archivedTags.isNotEmpty) _buildArchivedSection(),
            if (widget.showBatchTag) _buildBatchTagSection(),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            '标签管理',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          Row(
            children: [
              if (widget.showBatchTag)
                IconButton(
                  icon: const Icon(Icons.playlist_add),
                  color: Theme.of(context).colorScheme.secondary,
                  tooltip: '批量添加标签',
                  onPressed: _batchAddTagToUntagged,
                ),
              IconButton(
                icon: const Icon(Icons.check),
                color: Theme.of(context).colorScheme.primary,
                onPressed: () {
                  widget.onChanged?.call(_tags, _selected);
                  Navigator.pop(context, _tags);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Padding(
      padding: EdgeInsets.all(32),
      child: Text(
        '还没有标签，下方添加新标签',
        style: TextStyle(color: Colors.grey),
      ),
    );
  }

  Widget _buildTagList() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 260),
      child: AnimatedList(
        key: _listKey,
        shrinkWrap: true,
        initialItemCount: _tags.length,
        itemBuilder: (_, index, animation) {
          final tag = _tags[index];
          final color = AppColorUtils.hexToColor(tag.color, fallback: Colors.grey);
          return SizeTransition(
            sizeFactor: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            ),
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(1.0, 0.0),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              )),
              child: FadeTransition(
                opacity: animation,
                child: _buildTagItem(tag, index, color),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTagItem(PomodoroTag tag, int index, Color color) {
    return ListTile(
      key: ValueKey(tag.uuid),
      leading: GestureDetector(
        onTap: () => _openCustomColorPicker(forTagUuid: tag.uuid),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 4),
            ],
          ),
          child: const Icon(Icons.palette, color: Colors.white, size: 16),
        ),
      ),
      title: Text(tag.name),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.showSelection)
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
                widget.onChanged?.call(_tags, _selected);
              },
            ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20, color: Colors.grey),
            onPressed: () => _deleteTag(index),
          ),
        ],
      ),
    );
  }

  Widget _buildRemovedItem(PomodoroTag tag, Animation<double> animation) {
    return SizeTransition(
      sizeFactor: CurvedAnimation(
        parent: animation,
        curve: Curves.easeInCubic,
      ),
      child: FadeTransition(
        opacity: animation,
        child: ListTile(
          leading: CircleAvatar(
            radius: 16,
            backgroundColor: AppColorUtils.hexToColor(tag.color, fallback: Colors.grey),
          ),
          title: Text(tag.name),
          trailing: const Icon(Icons.delete, color: Colors.grey),
        ),
      ),
    );
  }

  Widget _buildAddSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'NEW TAG',
            style: TextStyle(
              fontSize: 9,
              color: Colors.grey,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _nameController,
                  onSubmitted: (_) => _addTag(),
                  decoration: InputDecoration(
                    hintText: '标签名称',
                    isDense: true,
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _openCustomColorPicker(),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColorUtils.hexToColor(_newColor, fallback: Colors.grey),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: AppColorUtils.hexToColor(_newColor, fallback: Colors.grey).withValues(alpha: 0.4),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _addTag,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                  foregroundColor: Theme.of(context).colorScheme.primary,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('+ 添加'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _presetColors.map((c) {
              final col = AppColorUtils.hexToColor(c, fallback: Colors.grey);
              return GestureDetector(
                onTap: () => setState(() => _newColor = c),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: col,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _newColor == c
                          ? Colors.white
                          : Colors.transparent,
                      width: 2,
                    ),
                    boxShadow: _newColor == c
                        ? [BoxShadow(color: col, blurRadius: 6)]
                        : null,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildArchivedSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.archive_outlined, size: 16, color: Colors.grey),
              const SizedBox(width: 8),
              Text(
                '已归档 (${_archivedTags.length})',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 120),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _archivedTags.length,
            itemBuilder: (ctx, i) {
              final tag = _archivedTags[i];
              final color = AppColorUtils.hexToColor(tag.color, fallback: Colors.grey);
              return ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 12,
                  backgroundColor: color,
                ),
                title: Text(
                  tag.name,
                  style: const TextStyle(fontSize: 13),
                ),
                trailing: TextButton(
                  onPressed: () => _restoreTag(tag),
                  child: const Text('恢复', style: TextStyle(fontSize: 12)),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildBatchTagSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: OutlinedButton.icon(
        onPressed: _batchAddTagToUntagged,
        icon: const Icon(Icons.playlist_add, size: 18),
        label: const Text('为未标签的番茄钟批量添加标签'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, 40),
        ),
      ),
    );
  }

  void _openColorPickerDialog() {
    Color pickerColor = _editingColorTagUuid != null
        ? AppColorUtils.hexToColor(
            _tags.firstWhere((t) => t.uuid == _editingColorTagUuid).color,
            fallback: Colors.grey)
        : AppColorUtils.hexToColor(_newColor, fallback: Colors.grey);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择颜色'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: pickerColor,
            onColorChanged: (Color color) {
              pickerColor = color;
            },
            enableAlpha: false,
          ),
        ),
        actions: [
          TextButton(
            child: const Text('取消'),
            onPressed: () {
              setState(() => _showColorPicker = false);
              Navigator.of(context).pop();
            },
          ),
          ElevatedButton(
            child: const Text('确定'),
            onPressed: () {
              final hex =
                  '#${(pickerColor.r * 255).round().toRadixString(16).padLeft(2, '0')}${(pickerColor.g * 255).round().toRadixString(16).padLeft(2, '0')}${(pickerColor.b * 255).round().toRadixString(16).padLeft(2, '0')}'
                      .toUpperCase();
              _onCustomColorSelected(hex);
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildColorPicker() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Padding(
        padding: MediaQuery.of(context).viewInsets,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '选择颜色',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _showColorPicker = false),
                  ),
                ],
              ),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '预设颜色',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: _presetColors.map((c) {
                      final col =
                          AppColorUtils.hexToColor(c, fallback: Colors.grey);
                      return GestureDetector(
                        onTap: () => _onCustomColorSelected(c),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: col,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    '更多颜色',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: _extendedColors.map((c) {
                      final col =
                          AppColorUtils.hexToColor(c, fallback: Colors.grey);
                      return GestureDetector(
                        onTap: () => _onCustomColorSelected(c),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: col,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1.5),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _openColorPickerDialog,
                      icon: const Icon(Icons.palette_outlined),
                      label: const Text('自定义颜色'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
          ],
        ),
      ),
    );
  }
}

class _BatchTagDialog extends StatefulWidget {
  final List<PomodoroTag> tags;
  final int untaggedCount;
  final ValueChanged<String> onConfirm;

  const _BatchTagDialog({
    required this.tags,
    required this.untaggedCount,
    required this.onConfirm,
  });

  @override
  State<_BatchTagDialog> createState() => _BatchTagDialogState();
}

class _BatchTagDialogState extends State<_BatchTagDialog> {
  String? _selectedTagUuid;

  @override
  void initState() {
    super.initState();
    if (widget.tags.isNotEmpty) {
      _selectedTagUuid = widget.tags.first.uuid;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('批量添加标签'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('共 ${widget.untaggedCount} 条未标签的番茄钟记录'),
          const SizedBox(height: 16),
          const Text('选择标签:'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: widget.tags.map((tag) {
              final color = AppColorUtils.hexToColor(tag.color, fallback: Colors.grey);
              final isSelected = _selectedTagUuid == tag.uuid;
              return GestureDetector(
                onTap: () => setState(() => _selectedTagUuid = tag.uuid),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? color.withValues(alpha: 0.2)
                        : color.withValues(alpha: 0.05),
                    border: Border.all(
                      color: isSelected ? color : color.withValues(alpha: 0.3),
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    tag.name,
                    style: TextStyle(
                      color: color,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _selectedTagUuid != null
              ? () => widget.onConfirm(_selectedTagUuid!)
              : null,
          child: const Text('确定'),
        ),
      ],
    );
  }
}
