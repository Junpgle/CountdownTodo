import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../../../services/pomodoro_service.dart';
import '../../../utils/app_color_utils.dart';

class UnifiedTagManagerSheet extends StatefulWidget {
  final List<PomodoroTag> allTags;
  final List<String> selectedUuids;
  final void Function(List<PomodoroTag>, List<String>)? onChanged;
  final bool showSelection;
  final bool showArchive;

  const UnifiedTagManagerSheet({
    super.key,
    required this.allTags,
    this.selectedUuids = const [],
    this.onChanged,
    this.showSelection = false,
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
  final TextEditingController _nameController = TextEditingController();
  String _newColor = _presetColors[0];
  bool _showColorPicker = false;
  String? _editingColorTagUuid;
  bool _showArchived = false;

  static const List<String> _presetColors = [
    '#F44336', '#E91E63', '#9C27B0', '#3F51B5', '#2196F3', '#009688',
    '#4CAF50', '#FF9800', '#607D8B', '#795548',
  ];

  static const List<String> _extendedColors = [
    '#EF5350', '#EC407A', '#AB47BC', '#5C6BC0', '#42A5F5', '#26A69A',
    '#66BB6A', '#FFA726', '#78909C', '#8D6E63', '#F48FB1', '#CE93D8',
    '#9FA8DA', '#81D4FA', '#80CBC4', '#A5D6A7', '#FFCC80', '#BCAAA4',
    '#B0BEC5', '#D7CCC8',
  ];

  @override
  void initState() {
    super.initState();
    _tags = widget.allTags.where((t) => !t.isArchived).toList();
    _archivedTags = widget.allTags.where((t) => t.isArchived).toList();
    _selected = List.from(widget.selectedUuids);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  List<PomodoroTag> get _allTags => [..._tags, ..._archivedTags];

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
    widget.onChanged?.call(_allTags, _selected);
  }

  void _archiveTag(int index) {
    final tag = _tags[index];
    setState(() {
      _selected.remove(tag.uuid);
      _tags.removeAt(index);
      tag.isArchived = true;
      _archivedTags.add(tag);
    });
    widget.onChanged?.call(_allTags, _selected);
  }

  void _restoreTag(PomodoroTag tag) {
    setState(() {
      _archivedTags.remove(tag);
      tag.isArchived = false;
      _tags.add(tag);
    });
    widget.onChanged?.call(_allTags, _selected);
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
        widget.onChanged?.call(_allTags, _selected);
      }
    } else {
      setState(() => _newColor = hex);
    }
    setState(() => _showColorPicker = false);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    if (_showColorPicker) {
      return _buildColorPicker(colorScheme);
    }

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(colorScheme),
              Flexible(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_tags.isEmpty)
                        _buildEmptyState(colorScheme)
                      else
                        _buildTagList(colorScheme),
                      const SizedBox(height: 16),
                      _buildAddSection(colorScheme),
                      const SizedBox(height: 16),
                      if (widget.showArchive && _archivedTags.isNotEmpty) 
                        _buildArchivedSection(colorScheme),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme colorScheme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '标签管理',
                style: TextStyle(
                  fontSize: 20, 
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.check, size: 18),
                label: const Text('完成'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () {
                  widget.onChanged?.call(_allTags, _selected);
                  Navigator.pop(context, _allTags);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(ColorScheme colorScheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Icon(Icons.label_outline, size: 48, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          Text(
            '还没有标签',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '在下方创建你的第一个标签吧',
            style: TextStyle(
              fontSize: 13,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTagList(ColorScheme colorScheme) {
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: _tags.length,
      onReorder: (oldIndex, newIndex) {
        setState(() {
          if (oldIndex < newIndex) newIndex -= 1;
          final tag = _tags.removeAt(oldIndex);
          _tags.insert(newIndex, tag);
        });
        widget.onChanged?.call(_allTags, _selected);
      },
      itemBuilder: (ctx, index) {
        final tag = _tags[index];
        final color = AppColorUtils.hexToColor(tag.color, fallback: colorScheme.primary);
        return _buildTagItem(tag, index, color, colorScheme);
      },
    );
  }

  Widget _buildTagItem(PomodoroTag tag, int index, Color color, ColorScheme colorScheme) {
    return Container(
      key: ValueKey(tag.uuid),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        leading: GestureDetector(
          onTap: () => _openCustomColorPicker(forTagUuid: tag.uuid),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 6, offset: const Offset(0, 2)),
              ],
            ),
            child: const Icon(Icons.palette_outlined, color: Colors.white, size: 18),
          ),
        ),
        title: Text(
          tag.name,
          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 16),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.showSelection)
              Checkbox(
                value: _selected.contains(tag.uuid),
                activeColor: color,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                onChanged: (val) {
                  setState(() {
                    if (val == true) {
                      _selected.add(tag.uuid);
                    } else {
                      _selected.remove(tag.uuid);
                    }
                  });
                  widget.onChanged?.call(_allTags, _selected);
                },
              ),
            IconButton(
              icon: Icon(Icons.archive_outlined, size: 20, color: colorScheme.onSurfaceVariant),
              tooltip: '归档',
              onPressed: () => _archiveTag(index),
            ),
            ReorderableDragStartListener(
              index: index,
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(Icons.drag_indicator, size: 20, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddSection(ColorScheme colorScheme) {
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.add_circle_outline, size: 18, color: colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                '添加新标签',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              GestureDetector(
                onTap: () => _openCustomColorPicker(),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColorUtils.hexToColor(_newColor, fallback: Colors.grey),
                    shape: BoxShape.circle,
                    border: Border.all(color: colorScheme.surface, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: AppColorUtils.hexToColor(_newColor, fallback: Colors.grey).withValues(alpha: 0.4),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.color_lens, color: Colors.white, size: 20),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _nameController,
                  onSubmitted: (_) => _addTag(),
                  decoration: InputDecoration(
                    hintText: '输入标签名称...',
                    hintStyle: TextStyle(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
                    isDense: true,
                    filled: true,
                    fillColor: colorScheme.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _addTag,
                icon: const Icon(Icons.add),
                style: IconButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  minimumSize: const Size(44, 44),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: _presetColors.map((c) {
                final col = AppColorUtils.hexToColor(c, fallback: Colors.grey);
                final isSelected = _newColor == c;
                return GestureDetector(
                  onTap: () => setState(() => _newColor = c),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(right: 12),
                    width: isSelected ? 32 : 28,
                    height: isSelected ? 32 : 28,
                    decoration: BoxDecoration(
                      color: col,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: colorScheme.surface,
                        width: isSelected ? 2 : 0,
                      ),
                      boxShadow: isSelected
                          ? [BoxShadow(color: col.withValues(alpha: 0.5), blurRadius: 8, offset: const Offset(0, 2))]
                          : null,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildArchivedSection(ColorScheme colorScheme) {
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _showArchived = !_showArchived),
            borderRadius: _showArchived 
                ? const BorderRadius.vertical(top: Radius.circular(16))
                : BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(Icons.archive_outlined, size: 20, color: colorScheme.onSurfaceVariant),
                  const SizedBox(width: 12),
                  Text(
                    '已归档',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${_archivedTags.length}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _showArchived ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (_showArchived) ...[
            const Divider(height: 1),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _archivedTags.length,
              separatorBuilder: (_, __) => const Divider(height: 1, indent: 48),
              itemBuilder: (ctx, i) {
                final tag = _archivedTags[i];
                final color = AppColorUtils.hexToColor(tag.color, fallback: Colors.grey);
                return ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                  ),
                  title: Text(
                    tag.name,
                    style: TextStyle(
                      fontSize: 14,
                      color: colorScheme.onSurfaceVariant,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                  trailing: FilledButton.tonal(
                    onPressed: () => _restoreTag(tag),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      minimumSize: const Size(0, 32),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('恢复', style: TextStyle(fontSize: 12)),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ],
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
        title: const Text('自定义颜色'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: pickerColor,
            onColorChanged: (Color color) {
              pickerColor = color;
            },
            enableAlpha: false,
            labelTypes: const [],
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
          FilledButton(
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

  Widget _buildColorPicker(ColorScheme colorScheme) {
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '选择颜色',
                    style: TextStyle(
                      fontSize: 20, 
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  IconButton.filledTonal(
                    icon: const Icon(Icons.close),
                    style: IconButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => setState(() => _showColorPicker = false),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '预设颜色',
                      style: TextStyle(
                        fontSize: 14, 
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: _presetColors.map((c) {
                        final col = AppColorUtils.hexToColor(c, fallback: Colors.grey);
                        return GestureDetector(
                          onTap: () => _onCustomColorSelected(c),
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: col,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(color: col.withValues(alpha: 0.4), blurRadius: 6, offset: const Offset(0, 2)),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 32),
                    Text(
                      '更多颜色',
                      style: TextStyle(
                        fontSize: 14, 
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: _extendedColors.map((c) {
                        final col = AppColorUtils.hexToColor(c, fallback: Colors.grey);
                        return GestureDetector(
                          onTap: () => _onCustomColorSelected(c),
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: col,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(color: col.withValues(alpha: 0.3), blurRadius: 4, offset: const Offset(0, 2)),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonalIcon(
                        onPressed: _openColorPickerDialog,
                        icon: const Icon(Icons.palette_outlined),
                        label: const Text('自定义颜色'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
