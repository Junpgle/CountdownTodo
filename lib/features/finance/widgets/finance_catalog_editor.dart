import 'dart:async';

import 'package:flutter/material.dart';

import '../../../utils/emoji_utils.dart';
import '../../../widgets/emoji_picker_dialog.dart';
import '../models/finance_models.dart';

class FinanceCatalogDraft {
  final String name;
  final String icon;
  final FinanceCategoryType? type;
  final String? parentUuid;

  const FinanceCatalogDraft({
    required this.name,
    required this.icon,
    required this.type,
    this.parentUuid,
  });
}

/// Owns its form state until the dialog route has finished closing.
class FinanceCatalogEditor extends StatefulWidget {
  final String initialName;
  final String initialIcon;
  final FinanceCategoryType? categoryType;
  final bool isEditing;
  final List<FinanceCategory> availableParents;
  final String? initialParentUuid;
  final String? editingCategoryUuid;
  final bool lockParent;
  final bool isSubcategory;

  /// System category type and hierarchy are fixed, while its name and icon
  /// can be customized.
  final bool systemCategory;
  final Future<void> Function(FinanceCatalogDraft draft) onSave;

  const FinanceCatalogEditor({
    super.key,
    this.initialName = '',
    required this.initialIcon,
    this.categoryType,
    this.isEditing = false,
    this.availableParents = const [],
    this.initialParentUuid,
    this.editingCategoryUuid,
    this.lockParent = false,
    this.isSubcategory = false,
    this.systemCategory = false,
    required this.onSave,
  });

  @override
  State<FinanceCatalogEditor> createState() => _FinanceCatalogEditorState();
}

class _FinanceCatalogEditorState extends State<FinanceCatalogEditor> {
  static const _noParentValue = '__finance_no_parent__';
  static const _recentPrefsKey = 'finance_recent_custom_emojis';

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _iconController;
  late String _selectedIcon;
  late FinanceCategoryType? _type;
  String? _parentUuid;
  bool _isSaving = false;
  String? _saveError;
  String? _iconError;

  bool get _isPayment => widget.categoryType == null;
  String get _defaultFallbackIcon => _isPayment ? '💼' : '📦';
  String get _label => _isPayment
      ? '付款方式'
      : widget.isSubcategory
      ? '细分类'
      : '分类';
  String get _icon => _selectedIcon.trim().isEmpty
      ? _defaultFallbackIcon
      : _selectedIcon.trim();

  bool get _hasChildren =>
      widget.editingCategoryUuid != null &&
      widget.availableParents.any(
        (category) =>
            category.parentUuid == widget.editingCategoryUuid &&
            !category.isDeleted,
      );

  List<FinanceCategory> get _parentCandidates {
    if (_isPayment || _type == null) return const [];
    return widget.availableParents.where((category) {
      final parentUuid = category.parentUuid?.trim();
      return category.type == _type &&
          category.uuid != widget.editingCategoryUuid &&
          !category.isDeleted &&
          (parentUuid == null || parentUuid.isEmpty) &&
          (!category.isArchived || category.uuid == _parentUuid);
    }).toList();
  }

  FinanceCategory? get _selectedParent {
    final parentUuid = _parentUuid?.trim();
    if (parentUuid == null || parentUuid.isEmpty) return null;
    for (final category in widget.availableParents) {
      if (category.uuid == parentUuid) return category;
    }
    return null;
  }

  String get _parentFieldValue {
    final parentUuid = _parentUuid?.trim();
    if (parentUuid != null &&
        _parentCandidates.any((category) => category.uuid == parentUuid)) {
      return parentUuid;
    }
    return _noParentValue;
  }

  List<String> get _suggestedIcons => _isPayment
      ? const [
          '💬',
          '💳',
          '💵',
          '🏦',
          '👛',
          '💼',
          '🪙',
          '📱',
          '🧧',
          '💰',
          '🌐',
          '🧾',
        ]
      : _type == FinanceCategoryType.income
      ? const [
          '💼',
          '💰',
          '🏆',
          '🧧',
          '🎁',
          '🪙',
          '🏦',
          '📈',
          '✨',
          '🌱',
          '🏠',
          '➕',
        ]
      : const [
          '🍜',
          '☕',
          '🛒',
          '🛍️',
          '🚇',
          '🚕',
          '🏠',
          '💡',
          '📚',
          '🎮',
          '🎬',
          '🎧',
          '💊',
          '🏃',
          '🐾',
          '🌷',
          '🎁',
          '✈️',
          '🔔',
          '✨',
          '👕',
          '📱',
          '🧾',
          '📦',
        ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    final initial = widget.initialIcon.trim().isEmpty
        ? _defaultFallbackIcon
        : widget.initialIcon.trim();
    _selectedIcon = initial;
    _iconController = TextEditingController(text: initial);
    _type = widget.categoryType;
    final parentUuid = widget.initialParentUuid?.trim();
    _parentUuid = parentUuid == null || parentUuid.isEmpty ? null : parentUuid;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _iconController.dispose();
    super.dispose();
  }

  String _helperHintForPlatform(TargetPlatform platform) {
    switch (platform) {
      case TargetPlatform.macOS:
        return '可用 ⌃⌘Space 调出系统表情键盘，或直接粘贴任意 Emoji';
      case TargetPlatform.windows:
        return '可用 Win + . 调出系统表情键盘，或直接粘贴任意 Emoji';
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return '可用系统表情键盘输入或粘贴任意 Emoji';
    }
  }

  void _handleCustomIconChanged(String value) {
    final composing = _iconController.value.composing;
    if (composing.isValid && !composing.isCollapsed) {
      return;
    }

    if (value.trim().isEmpty) {
      setState(() {
        _selectedIcon = _defaultFallbackIcon;
        _iconError = null;
      });
      return;
    }

    final extracted = EmojiUtils.extractSingleEmoji(value);
    setState(() {
      if (extracted != null) {
        _selectedIcon = extracted;
        _iconError = null;
      } else {
        _iconError = '请输入或粘贴 1 个 Emoji';
      }
    });
  }

  Future<void> _openFullEmojiPicker() async {
    if (_isSaving) return;
    FocusScope.of(context).unfocus();
    final picked = await AppEmojiPickerDialog.show(
      context,
      initialIcon: _icon,
      initialCategory: EmojiPickerCategory.finance,
      title: '选择$_label图标',
      recentPrefsKey: _recentPrefsKey,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _selectedIcon = picked;
      _iconController.text = picked;
      _iconError = null;
    });
  }

  Future<void> _save() async {
    if (_isSaving || !_formKey.currentState!.validate()) return;
    final rawIcon = _iconController.text.trim();
    String resolvedIcon;
    if (rawIcon.isEmpty) {
      resolvedIcon = _defaultFallbackIcon;
    } else {
      final extracted = EmojiUtils.extractSingleEmoji(rawIcon);
      if (extracted == null) {
        setState(() => _iconError = '请输入或粘贴 1 个 Emoji');
        return;
      }
      resolvedIcon = extracted;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _isSaving = true;
      _saveError = null;
      _iconError = null;
    });
    try {
      await widget.onSave(
        FinanceCatalogDraft(
          name: _nameController.text.trim(),
          icon: resolvedIcon,
          type: _type,
          parentUuid: _parentUuid,
        ),
      );
      unawaited(
        AppEmojiPickerDialog.recordRecentEmoji(
          resolvedIcon,
          prefsKey: _recentPrefsKey,
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      debugPrint('记账$_label保存失败：$error');
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _saveError = '保存失败，填写的内容已保留，请重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final selectedParent = _selectedParent;
    final selectedParentPath = selectedParent == null
        ? null
        : financeCategoryDisplayName(selectedParent, widget.availableParents);
    final selectedParentName = selectedParent == null
        ? null
        : financeCategorySiblingDisplayName(
            selectedParent,
            widget.availableParents,
          );
    return PopScope(
      canPop: !_isSaving,
      child: AlertDialog(
        scrollable: true,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        title: Text('${widget.isEditing ? '编辑' : '新增'}$_label'),
        content: SizedBox(
          width: 408,
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colors.primaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      InkWell(
                        onTap: _isSaving ? null : _openFullEmojiPicker,
                        borderRadius: BorderRadius.circular(14),
                        child: Tooltip(
                          message: '选择全部 Emoji',
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: colors.surface.withValues(alpha: 0.72),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: Text(
                                      _icon,
                                      textScaler: TextScaler.noScaling,
                                      style: const TextStyle(fontSize: 30),
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                right: -4,
                                bottom: -4,
                                child: Container(
                                  width: 18,
                                  height: 18,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: colors.primaryContainer,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: colors.surface,
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.edit_rounded,
                                    size: 11,
                                    color: colors.onPrimaryContainer,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _nameController.text.trim().isEmpty
                                  ? '你的$_label'
                                  : selectedParentPath == null
                                  ? _nameController.text.trim()
                                  : '$selectedParentPath - ${_nameController.text.trim()}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _isPayment
                                  ? '付款方式 · 自定义'
                                  : widget.systemCategory
                                  ? '系统${_type!.label}分类 · 自定义名称和图标'
                                  : '${_type!.label}分类 · 自定义',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  key: const ValueKey('finance-catalog-name'),
                  controller: _nameController,
                  enabled: !_isSaving,
                  maxLength: 30,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: '$_label名称',
                    hintText: _isPayment
                        ? '例如：日常银行卡'
                        : _type == FinanceCategoryType.income
                        ? '例如：兼职、理财收益'
                        : '例如：咖啡、宠物',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                  onFieldSubmitted: (_) => _save(),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? '请填写$_label名称'
                      : null,
                ),
                if (!_isPayment && !widget.systemCategory) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final type in FinanceCategoryType.values)
                        ChoiceChip(
                          label: Text('${type.label}分类'),
                          selected: type == _type,
                          onSelected: _isSaving || widget.isEditing
                              ? null
                              : (_) => setState(() {
                                  _type = type;
                                  if (!_parentCandidates.any(
                                    (category) => category.uuid == _parentUuid,
                                  )) {
                                    _parentUuid = null;
                                  }
                                }),
                        ),
                    ],
                  ),
                  if (widget.isEditing)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '分类类型创建后不可修改',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                ],
                if (!_isPayment &&
                    !widget.systemCategory &&
                    (_parentCandidates.isNotEmpty || _parentUuid != null)) ...[
                  DropdownButtonFormField<String>(
                    key: const ValueKey('finance-catalog-parent'),
                    initialValue: _parentFieldValue,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: '上级大类（可选）',
                      helperText: _hasChildren
                          ? '已有二级分类，请先移动二级分类后再调整上级'
                          : widget.lockParent && _selectedParent != null
                          ? '已选择“$selectedParentName”，这是该大类下的细分类'
                          : '不选择上级时，会创建为一级分类',
                      helperMaxLines: 2,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: _noParentValue,
                        child: Text('一级分类'),
                      ),
                      for (final parent in _parentCandidates)
                        DropdownMenuItem<String>(
                          value: parent.uuid,
                          child: Text(
                            '${parent.icon} ${financeCategorySiblingDisplayName(parent, widget.availableParents)}',
                          ),
                        ),
                    ],
                    onChanged: _isSaving || widget.lockParent || _hasChildren
                        ? null
                        : (value) => setState(() {
                            _parentUuid = value == _noParentValue
                                ? null
                                : value;
                          }),
                  ),
                  const SizedBox(height: 16),
                ],
                SizedBox(
                  width: double.infinity,
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Text('选择图标', style: theme.textTheme.titleSmall),
                      TextButton.icon(
                        key: const ValueKey('finance-more-emoji-button'),
                        onPressed: _isSaving ? null : _openFullEmojiPicker,
                        icon: const Icon(
                          Icons.emoji_emotions_outlined,
                          size: 16,
                        ),
                        label: const Text('全部 Emoji'),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final icon in _suggestedIcons)
                      Semantics(
                        button: true,
                        selected: _icon == icon,
                        label: '图标 $icon',
                        child: Material(
                          color: _icon == icon
                              ? colors.primaryContainer
                              : colors.surfaceContainerHighest.withValues(
                                  alpha: 0.5,
                                ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(
                              color: _icon == icon
                                  ? colors.primary
                                  : colors.outlineVariant.withValues(
                                      alpha: 0.4,
                                    ),
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            key: ValueKey('finance-icon-$icon'),
                            onTap: _isSaving
                                ? null
                                : () {
                                    FocusScope.of(context).unfocus();
                                    setState(() {
                                      _selectedIcon = icon;
                                      _iconController.text = icon;
                                      _iconError = null;
                                    });
                                  },
                            child: SizedBox(
                              width: 48,
                              height: 48,
                              child: Center(
                                child: Text(
                                  icon,
                                  textScaler: TextScaler.noScaling,
                                  style: const TextStyle(fontSize: 24),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const ValueKey('finance-catalog-icon'),
                  controller: _iconController,
                  enabled: !_isSaving,
                  decoration: InputDecoration(
                    labelText: '自定义 Emoji',
                    hintText: '输入或粘贴任意 Emoji',
                    helperText: _helperHintForPlatform(theme.platform),
                    helperMaxLines: 2,
                    errorText: _iconError,
                    prefixIcon: const Icon(Icons.emoji_emotions_outlined),
                    suffixIcon: _iconController.text.isNotEmpty
                        ? IconButton(
                            tooltip: '清空图标',
                            onPressed: _isSaving
                                ? null
                                : () {
                                    setState(() {
                                      _iconController.clear();
                                      _selectedIcon = _defaultFallbackIcon;
                                      _iconError = null;
                                    });
                                  },
                            icon: const Icon(Icons.close_rounded, size: 18),
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onChanged: _handleCustomIconChanged,
                ),
                if (_saveError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _saveError!,
                      style: TextStyle(color: colors.error),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _isSaving
                ? null
                : () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton.icon(
            key: const ValueKey('finance-catalog-save'),
            onPressed: _isSaving ? null : _save,
            icon: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_rounded, size: 18),
            label: Text(_isSaving ? '保存中' : '保存'),
          ),
        ],
      ),
    );
  }
}
