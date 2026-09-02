import '../../widgets/floating_glass_control.dart';
import '../../widgets/management_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../storage_service.dart';
import '../../widgets/optional_liquid_glass_surface.dart';
import '../settings/batch_tag_page.dart';
import '../settings/rebind_tag_page.dart';
import '../../services/pomodoro_service.dart';
import '../../utils/app_color_utils.dart';
import '../../utils/app_dialogs.dart';

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
  State<UnifiedTagManagerScreen> createState() =>
      _UnifiedTagManagerScreenState();
}

class _UnifiedTagManagerScreenState extends State<UnifiedTagManagerScreen> {
  late List<PomodoroTag> _tags;
  late List<String> _selected;
  late List<PomodoroTag> _archivedTags;
  bool _showArchived = false;
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matches(PomodoroTag tag) => tag.name
      .toLowerCase()
      .contains(_searchController.text.trim().toLowerCase());

  PomodoroTag? _editingTag;
  bool _isAddingNewTag = false;

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
      _searchController.clear();
      _showArchived = false;
    });
    _notifyChanges();
  }

  void _showAddTagDialog() {
    showAppModalBottomSheet(
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
            _searchController.clear();
            _showArchived = false;
          });
          _notifyChanges();
          Navigator.pop(ctx);
        },
      ),
    );
  }

  void _showEditTagDialog(PomodoroTag tag, int index) {
    showAppModalBottomSheet(
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

  void _addTag(bool isWide) {
    if (isWide) {
      setState(() {
        _isAddingNewTag = true;
        _editingTag = null;
      });
    } else {
      _showAddTagDialog();
    }
  }

  void _editTag(PomodoroTag tag, bool isWide) {
    if (isWide) {
      setState(() {
        _editingTag = tag;
        _isAddingNewTag = false;
      });
    } else {
      _showEditTagDialog(tag, _tags.indexOf(tag));
    }
  }

  Future<void> _openTagTool(bool batch) async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString(StorageService.keyCurrentUser) ?? '';
    if (!mounted) return;
    Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => batch
              ? BatchTagPage(username: username, isEmbedded: false)
              : RebindTagPage(username: username),
          settings: RouteSettings(name: batch ? '批量添加标签' : '重新绑定标签'),
        ));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isWide = MediaQuery.sizeOf(context).width >= 1000 &&
        MediaQuery.textScalerOf(context).scale(14) < 21;
    final visible =
        (_showArchived ? _archivedTags : _tags).where(_matches).toList();
    final canReorder = !_showArchived && _searchController.text.trim().isEmpty;
    final list =
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ManagementSearchField(
        controller: _searchController,
        hintText: '搜索标签名称',
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 14),
      ManagementFilterBar<bool>(
          value: _showArchived,
          onChanged: (value) => setState(() => _showArchived = value),
          options: [
            ManagementFilterOption(value: false, label: '使用中 ${_tags.length}'),
            if (widget.showArchive)
              ManagementFilterOption(
                  value: true, label: '已归档 ${_archivedTags.length}')
          ]),
      const SizedBox(height: 12),
      Text(
          _showArchived
              ? '归档标签仍保留在历史记录中，可随时恢复。'
              : canReorder
                  ? '拖动右侧手柄排序，点击标签编辑。'
                  : '搜索时暂停排序，清空搜索后可拖动调整。',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant)),
      const SizedBox(height: 16),
      if (visible.isEmpty)
        ManagementEmptyState(
          icon:
              _showArchived ? Icons.inventory_2_outlined : Icons.label_outline,
          title: _searchController.text.trim().isNotEmpty
              ? '没有找到匹配的标签'
              : _showArchived
                  ? '暂无归档标签'
                  : '还没有标签',
          description: _searchController.text.trim().isNotEmpty
              ? '试试其他关键词，或清空搜索。'
              : _showArchived
                  ? '不常用的标签可以归档，不会删除历史记录。'
                  : '点击“添加标签”，为专注和时间日志分类。',
        )
      else if (canReorder)
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: visible.length,
          onReorderItem: (oldIndex, newIndex) {
            setState(() {
              final tag = _tags.removeAt(oldIndex);
              _tags.insert(newIndex, tag);
            });
            _notifyChanges();
          },
          itemBuilder: (_, index) =>
              _buildTagCard(visible[index], isWide, index),
        )
      else
        ...visible.map((tag) => _buildTagCard(tag, isWide, null)),
    ]);

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: FloatingGlassAppBar(
        flexibleSpace: const FloatingGlassTopBarBackground(),
        title: const Text('管理标签'),
      ),
      body: ManagementPage(maxWidth: 1160, children: [
        const ManagementIntro(
            icon: Icons.label_outline_rounded,
            title: '让专注更有条理',
            description: '整理专注与时间日志的标签，保留每一次投入的线索。'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(
              onPressed: () => _addTag(isWide),
              icon: const Icon(Icons.add_rounded),
              label: const Text('添加标签')),
          TextButton.icon(
              onPressed: () => _openTagTool(true),
              icon: const Icon(Icons.playlist_add_rounded),
              label: const Text('批量添加标签')),
          TextButton.icon(
              onPressed: () => _openTagTool(false),
              icon: const Icon(Icons.link_rounded),
              label: const Text('重新绑定标签')),
        ]),
        const SizedBox(height: 24),
        if (isWide)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: list),
            const SizedBox(width: 24),
            Expanded(child: _buildRightPanel(scheme)),
          ])
        else
          list,
      ]),
    );
  }

  Widget _buildTagCard(PomodoroTag tag, bool isWide, int? dragIndex) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = AppColorUtils.hexToColor(tag.color, fallback: scheme.primary);
    final editing = isWide && _editingTag?.uuid == tag.uuid && !_isAddingNewTag;
    return ManagementCard(
      key: ValueKey(tag.uuid),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      backgroundColor: editing ? scheme.primaryContainer : null,
      borderColor: editing ? scheme.primary : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12)),
              child: Center(
                  child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                          color: color, shape: BoxShape.circle)))),
          const SizedBox(width: 12),
          Expanded(
              child: tag.isArchived
                  ? Text(tag.name, style: theme.textTheme.titleMedium)
                  : InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => _editTag(tag, isWide),
                      child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(tag.name,
                              style: theme.textTheme.titleMedium)),
                    )),
          if (dragIndex != null)
            ReorderableDragStartListener(
                index: dragIndex,
                child: Tooltip(
                    message: '拖动排序',
                    child: SizedBox(
                        width: 40,
                        height: 48,
                        child: Icon(Icons.drag_indicator_rounded,
                            color: scheme.onSurfaceVariant)))),
        ]),
        const SizedBox(height: 4),
        ManagementActionBar(spacing: 4, runSpacing: 4, children: [
          if (widget.showSelection && !tag.isArchived)
            FilterChip(
                label: Text(_selected.contains(tag.uuid) ? '已选中' : '选择'),
                selected: _selected.contains(tag.uuid),
                onSelected: (value) {
                  setState(() {
                    if (value) {
                      _selected.add(tag.uuid);
                    } else {
                      _selected.remove(tag.uuid);
                    }
                  });
                  _notifyChanges();
                }),
          if (!tag.isArchived) ...[
            TextButton.icon(
                onPressed: () => _editTag(tag, isWide),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('编辑')),
            if (widget.showArchive)
              TextButton.icon(
                  onPressed: () => _archiveTag(_tags.indexOf(tag)),
                  icon: const Icon(Icons.archive_outlined, size: 18),
                  label: const Text('归档')),
          ] else
            FilledButton.tonalIcon(
                onPressed: () => _restoreTag(tag),
                icon: const Icon(Icons.unarchive_outlined, size: 18),
                label: const Text('恢复')),
        ]),
      ]),
    );
  }

  Widget _buildRightPanel(ColorScheme colorScheme) {
    if (_isAddingNewTag) {
      return _buildRightPanelContainer(
        colorScheme,
        child: _TagForm(
          key: const ValueKey('new-tag'),
          title: '添加新标签',
          onSubmit: (name, colorHex) {
            final tag = PomodoroTag(
              name: name.trim(),
              color: colorHex,
            );
            setState(() {
              _tags.add(tag);
              _searchController.clear();
              _showArchived = false;
              _isAddingNewTag = false;
            });
            _notifyChanges();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('添加成功'), duration: Duration(seconds: 1)),
            );
          },
        ),
      );
    } else if (_editingTag != null) {
      return _buildRightPanelContainer(
        colorScheme,
        child: _TagForm(
          key: ValueKey(_editingTag!.uuid),
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
              const SnackBar(
                  content: Text('保存成功'), duration: Duration(seconds: 1)),
            );
          },
        ),
      );
    } else {
      return OptionalLiquidGlassCard(
        width: double.infinity,
        padding: const EdgeInsets.all(32),
        borderRadius: 16,
        fallbackDecoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Column(
          children: [
            Icon(Icons.edit_outlined,
                size: 48,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text(
              '请在左侧选择标签进行编辑',
              style:
                  TextStyle(fontSize: 16, color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildRightPanelContainer(ColorScheme colorScheme,
      {required Widget child}) {
    return OptionalLiquidGlassCard(
      borderRadius: 16,
      highContrast: true,
      fallbackDecoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      padding: const EdgeInsets.all(24),
      child: child,
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

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: OptionalLiquidGlassSheet(
            topRadius: 24,
            padding: const EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: 20,
            ),
            fallbackDecoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                        child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    )),
                    IconButton(
                      tooltip: '关闭',
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
          ),
        ),
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
    super.key,
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
  bool _nameMissing = false;

  @override
  void initState() {
    super.initState();
    _initValues();
  }

  void _initValues() {
    _nameController = TextEditingController(text: widget.initialName ?? '');
    _selectedColor = widget.initialColorHex ??
        _UnifiedTagManagerScreenState._presetColors[0];
  }

  @override
  void didUpdateWidget(_TagForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialName != oldWidget.initialName ||
        widget.initialColorHex != oldWidget.initialColorHex) {
      _nameController.text = widget.initialName ?? '';
      _selectedColor = widget.initialColorHex ??
          _UnifiedTagManagerScreenState._presetColors[0];
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    setState(() => _nameMissing = _nameController.text.trim().isEmpty);
    if (_nameMissing) return;
    widget.onSubmit(_nameController.text.trim(), _selectedColor);
  }

  void _openColorPicker() {
    showAppModalBottomSheet(
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
                  color: AppColorUtils.hexToColor(_selectedColor,
                      fallback: Colors.grey),
                  shape: BoxShape.circle,
                  border: Border.all(color: colorScheme.surface, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: AppColorUtils.hexToColor(_selectedColor,
                              fallback: Colors.grey)
                          .withValues(alpha: 0.4),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child:
                    const Icon(Icons.color_lens, color: Colors.white, size: 20),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _nameController,
                onChanged: (_) => setState(() => _nameMissing = false),
                autofocus: widget.isSheet || widget.initialName == null,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: '标签名称',
                  errorText: _nameMissing ? '请输入标签名称' : null,
                  hintText: '输入标签名称...',
                  hintStyle: TextStyle(
                      color:
                          colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
                  isDense: true,
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text('点击左侧色块设置颜色。',
            style: TextStyle(color: colorScheme.onSurfaceVariant)),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _submit,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
            child: const Text('保存',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
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
    Color pickerColor =
        AppColorUtils.hexToColor(_selectedHex, fallback: Colors.grey);

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

    return OptionalLiquidGlassSheet(
      topRadius: 24,
      fallbackDecoration: BoxDecoration(
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
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
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
                      children:
                          _UnifiedTagManagerScreenState._presetColors.map((c) {
                        final col =
                            AppColorUtils.hexToColor(c, fallback: Colors.grey);
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
                                BoxShadow(
                                    color: col.withValues(alpha: 0.4),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2)),
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
                      children: _UnifiedTagManagerScreenState._extendedColors
                          .map((c) {
                        final col =
                            AppColorUtils.hexToColor(c, fallback: Colors.grey);
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
                                BoxShadow(
                                    color: col.withValues(alpha: 0.3),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2)),
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
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
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
