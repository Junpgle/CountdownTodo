import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../storage_service.dart';
import '../settings/batch_tag_page.dart';
import '../settings/rebind_tag_page.dart';
import '../../services/pomodoro_service.dart';
import '../../utils/app_color_utils.dart';

class UnifiedTagManagerScreen extends StatefulWidget {
  final List<PomodoroTag> allTags;
  final List<String> selectedUuids;
  final void Function(List<PomodoroTag>, List<String>)? onChanged;
  final bool showSelection;
  final bool showArchive;

  const UnifiedTagManagerScreen({
    super.key,
    required this.allTags,
    this.selectedUuids = const [],
    this.onChanged,
    this.showSelection = false,
    this.showArchive = true,
  });

  @override
  State<UnifiedTagManagerScreen> createState() => _UnifiedTagManagerScreenState();
}

class _UnifiedTagManagerScreenState extends State<UnifiedTagManagerScreen> {
  late List<PomodoroTag> _tags;
  late List<String> _selected;
  late List<PomodoroTag> _archivedTags;
  bool _showArchived = false;

  PomodoroTag? _editingTag;
  bool _isAddingNewTag = false;

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

  List<PomodoroTag> get _allTags => [..._tags, ..._archivedTags];

  void _notifyChanges() {
    widget.onChanged?.call(_allTags, _selected);
  }

  void _archiveTag(int index) {
    final tag = _tags[index];
    setState(() {
      _selected.remove(tag.uuid);
      _tags.removeAt(index);
      tag.isArchived = true;
      _archivedTags.add(tag);
      if (_editingTag?.uuid == tag.uuid) {
        _editingTag = null;
      }
    });
    _notifyChanges();
  }

  void _restoreTag(PomodoroTag tag) {
    setState(() {
      _archivedTags.remove(tag);
      tag.isArchived = false;
      _tags.add(tag);
    });
    _notifyChanges();
  }

  void _showAddTagDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 600),
      builder: (ctx) => _TagFormSheet(
        title: '添加新标签',
        onSubmit: (name, colorHex) {
          final tag = PomodoroTag(
            name: name.trim(),
            color: colorHex,
          );
          setState(() {
            _tags.add(tag);
          });
          _notifyChanges();
          Navigator.pop(ctx);
        },
      ),
    );
  }

  void _showEditTagDialog(PomodoroTag tag, int index) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 600),
      builder: (ctx) => _TagFormSheet(
        title: '编辑标签',
        initialName: tag.name,
        initialColorHex: tag.color,
        onSubmit: (name, colorHex) {
          setState(() {
            tag.name = name.trim();
            tag.color = colorHex;
            tag.updatedAt = DateTime.now().millisecondsSinceEpoch;
            tag.version += 1;
          });
          _notifyChanges();
          Navigator.pop(ctx);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('管理标签'),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () async {
                    final prefs = await SharedPreferences.getInstance();
                    final username = prefs.getString(StorageService.KEY_CURRENT_USER) ?? '';
                    if (!context.mounted) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => BatchTagPage(
                          username: username,
                          isEmbedded: false,
                        ),
                        settings: const RouteSettings(name: '批量添加标签'),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2.0),
                    child: Text(
                      '想要批量给事件添加标签？',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.primary,
                        decoration: TextDecoration.underline,
                        decorationColor: colorScheme.primary,
                      ),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () async {
                    final prefs = await SharedPreferences.getInstance();
                    final username = prefs.getString(StorageService.KEY_CURRENT_USER) ?? '';
                    if (!context.mounted) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => RebindTagPage(
                          username: username,
                        ),
                        settings: const RouteSettings(name: '重新绑定标签'),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Text(
                      '需要重新绑定已删除的标签？',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.error,
                        decoration: TextDecoration.underline,
                        decorationColor: colorScheme.error,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        scrolledUnderElevation: 0,
        backgroundColor: colorScheme.surface,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '添加标签',
            onPressed: () {
              if (MediaQuery.of(context).size.width >= 800) {
                setState(() {
                  _isAddingNewTag = true;
                  _editingTag = null;
                });
              } else {
                _showAddTagDialog();
              }
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 800;

          if (isWide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Column(
                      children: [
                        if (_tags.isEmpty)
                          _buildEmptyState(colorScheme)
                        else
                          _buildTagList(colorScheme, isWide: true),
                      ],
                    ),
                  ),
                ),
                VerticalDivider(width: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                Expanded(
                  flex: 4,
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildRightPanel(colorScheme),
                        const SizedBox(height: 32),
                        if (widget.showArchive && _archivedTags.isNotEmpty)
                          _buildArchivedSection(colorScheme, isWide: true),
                      ],
                    ),
                  ),
                ),
              ],
            );
          } else {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Column(
                    children: [
                      if (_tags.isEmpty)
                        _buildEmptyState(colorScheme)
                      else
                        _buildTagList(colorScheme, isWide: false),
                      const SizedBox(height: 16),
                      if (widget.showArchive && _archivedTags.isNotEmpty)
                        _buildArchivedSection(colorScheme, isWide: false),
                      const SizedBox(height: 48),
                    ],
                  ),
                ),
              ),
            );
          }
        },
      ),
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
            '点击右上角 + 创建你的第一个标签吧',
            style: TextStyle(
              fontSize: 13,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTagList(ColorScheme colorScheme, {required bool isWide}) {
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
        _notifyChanges();
      },
      itemBuilder: (ctx, index) {
        final tag = _tags[index];
        final color = AppColorUtils.hexToColor(tag.color, fallback: colorScheme.primary);
        return _buildTagItem(tag, index, color, colorScheme, isWide);
      },
    );
  }

  Widget _buildTagItem(PomodoroTag tag, int index, Color color, ColorScheme colorScheme, bool isWide) {
    final isEditing = isWide && _editingTag?.uuid == tag.uuid && !_isAddingNewTag;

    return Container(
      key: ValueKey(tag.uuid),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isEditing ? colorScheme.primaryContainer.withValues(alpha: 0.3) : colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isEditing ? colorScheme.primary : colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: ListTile(
        onTap: isWide
            ? () {
                setState(() {
                  _editingTag = tag;
                  _isAddingNewTag = false;
                });
              }
            : null,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        leading: GestureDetector(
          onTap: () {
            if (isWide) {
              setState(() {
                _editingTag = tag;
                _isAddingNewTag = false;
              });
            } else {
              _showEditTagDialog(tag, index);
            }
          },
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
                  _notifyChanges();
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

  Widget _buildRightPanel(ColorScheme colorScheme) {
    if (_isAddingNewTag) {
      return _buildRightPanelContainer(
        colorScheme,
        child: _TagForm(
          title: '添加新标签',
          onSubmit: (name, colorHex) {
            final tag = PomodoroTag(
              name: name.trim(),
              color: colorHex,
            );
            setState(() {
              _tags.add(tag);
              _isAddingNewTag = false;
            });
            _notifyChanges();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('添加成功'), duration: Duration(seconds: 1)),
            );
          },
        ),
      );
    } else if (_editingTag != null) {
      return _buildRightPanelContainer(
        colorScheme,
        child: _TagForm(
          title: '编辑标签',
          initialName: _editingTag!.name,
          initialColorHex: _editingTag!.color,
          onSubmit: (name, colorHex) {
            setState(() {
              _editingTag!.name = name.trim();
              _editingTag!.color = colorHex;
              _editingTag!.updatedAt = DateTime.now().millisecondsSinceEpoch;
              _editingTag!.version += 1;
              _editingTag = null;
            });
            _notifyChanges();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('保存成功'), duration: Duration(seconds: 1)),
            );
          },
        ),
      );
    } else {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Column(
          children: [
            Icon(Icons.edit_outlined, size: 48, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text(
              '请在左侧选择标签进行编辑',
              style: TextStyle(fontSize: 16, color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildRightPanelContainer(ColorScheme colorScheme, {required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      padding: const EdgeInsets.all(24),
      child: child,
    );
  }

  Widget _buildArchivedSection(ColorScheme colorScheme, {required bool isWide}) {
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
            onTap: () {
              setState(() {
                _showArchived = !_showArchived;
              });
            },
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.archive, size: 20, color: colorScheme.onSurfaceVariant),
                  const SizedBox(width: 12),
                  Text(
                    '已归档 (${_archivedTags.length})',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _showArchived ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
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
}

class _TagFormSheet extends StatelessWidget {
  final String title;
  final String? initialName;
  final String? initialColorHex;
  final void Function(String name, String colorHex) onSubmit;

  const _TagFormSheet({
    required this.title,
    this.initialName,
    this.initialColorHex,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 18, 
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _TagForm(
            title: title,
            initialName: initialName,
            initialColorHex: initialColorHex,
            onSubmit: onSubmit,
            isSheet: true,
          ),
        ],
      ),
    );
  }
}

class _TagForm extends StatefulWidget {
  final String title;
  final String? initialName;
  final String? initialColorHex;
  final void Function(String name, String colorHex) onSubmit;
  final bool isSheet;

  const _TagForm({
    required this.title,
    this.initialName,
    this.initialColorHex,
    required this.onSubmit,
    this.isSheet = false,
  });

  @override
  State<_TagForm> createState() => _TagFormState();
}

class _TagFormState extends State<_TagForm> {
  late TextEditingController _nameController;
  late String _selectedColor;

  @override
  void initState() {
    super.initState();
    _initValues();
  }

  void _initValues() {
    _nameController = TextEditingController(text: widget.initialName ?? '');
    _selectedColor = widget.initialColorHex ?? _UnifiedTagManagerScreenState._presetColors[0];
  }

  @override
  void didUpdateWidget(_TagForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialName != oldWidget.initialName || widget.initialColorHex != oldWidget.initialColorHex) {
      _nameController.text = widget.initialName ?? '';
      _selectedColor = widget.initialColorHex ?? _UnifiedTagManagerScreenState._presetColors[0];
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_nameController.text.trim().isNotEmpty) {
      widget.onSubmit(_nameController.text.trim(), _selectedColor);
    }
  }

  void _openColorPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 600),
      builder: (ctx) => _ColorPickerSheet(
        initialColorHex: _selectedColor,
        onColorSelected: (hex) {
          setState(() => _selectedColor = hex);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!widget.isSheet) ...[
          Text(
            widget.title,
            style: TextStyle(
              fontSize: 18, 
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 16),
        ],
        Row(
          children: [
            GestureDetector(
              onTap: _openColorPicker,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColorUtils.hexToColor(_selectedColor, fallback: Colors.grey),
                  shape: BoxShape.circle,
                  border: Border.all(color: colorScheme.surface, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: AppColorUtils.hexToColor(_selectedColor, fallback: Colors.grey).withValues(alpha: 0.4),
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
                autofocus: widget.isSheet || widget.initialName == null,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  hintText: '输入标签名称...',
                  hintStyle: TextStyle(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
                  isDense: true,
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _submit,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: const Text('保存', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }
}

class _ColorPickerSheet extends StatefulWidget {
  final String initialColorHex;
  final void Function(String) onColorSelected;

  const _ColorPickerSheet({
    required this.initialColorHex,
    required this.onColorSelected,
  });

  @override
  State<_ColorPickerSheet> createState() => _ColorPickerSheetState();
}

class _ColorPickerSheetState extends State<_ColorPickerSheet> {
  late String _selectedHex;

  @override
  void initState() {
    super.initState();
    _selectedHex = widget.initialColorHex;
  }

  void _openCustomColorPickerDialog() {
    Color pickerColor = AppColorUtils.hexToColor(_selectedHex, fallback: Colors.grey);

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
          ),
        ),
        actions: [
          TextButton(
            child: const Text('取消'),
            onPressed: () => Navigator.of(context).pop(),
          ),
          FilledButton(
            child: const Text('确定'),
            onPressed: () {
              final hex =
                  '#${(pickerColor.r * 255).round().toRadixString(16).padLeft(2, '0')}${(pickerColor.g * 255).round().toRadixString(16).padLeft(2, '0')}${(pickerColor.b * 255).round().toRadixString(16).padLeft(2, '0')}'
                      .toUpperCase();
              widget.onColorSelected(hex);
              Navigator.of(context).pop();
              Navigator.of(context).pop(); // Also pop the color picker sheet
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

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
                    onPressed: () => Navigator.pop(context),
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
                      children: _UnifiedTagManagerScreenState._presetColors.map((c) {
                        final col = AppColorUtils.hexToColor(c, fallback: Colors.grey);
                        return GestureDetector(
                          onTap: () {
                            widget.onColorSelected(c);
                            Navigator.pop(context);
                          },
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
                      children: _UnifiedTagManagerScreenState._extendedColors.map((c) {
                        final col = AppColorUtils.hexToColor(c, fallback: Colors.grey);
                        return GestureDetector(
                          onTap: () {
                            widget.onColorSelected(c);
                            Navigator.pop(context);
                          },
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
                        onPressed: _openCustomColorPickerDialog,
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
