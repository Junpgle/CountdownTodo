import 'package:flutter/material.dart';

import '../models/finance_models.dart';

class FinanceCatalogDraft {
  final String name;
  final String icon;
  final FinanceCategoryType? type;

  const FinanceCatalogDraft({
    required this.name,
    required this.icon,
    required this.type,
  });
}

/// Owns its form state until the dialog route has finished closing.
class FinanceCatalogEditor extends StatefulWidget {
  final String initialName;
  final String initialIcon;
  final FinanceCategoryType? categoryType;
  final bool isEditing;
  final Future<void> Function(FinanceCatalogDraft draft) onSave;

  const FinanceCatalogEditor({
    super.key,
    this.initialName = '',
    required this.initialIcon,
    this.categoryType,
    this.isEditing = false,
    required this.onSave,
  });

  @override
  State<FinanceCatalogEditor> createState() => _FinanceCatalogEditorState();
}

class _FinanceCatalogEditorState extends State<FinanceCatalogEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _iconController;
  late FinanceCategoryType? _type;
  bool _isSaving = false;
  String? _saveError;

  bool get _isPayment => widget.categoryType == null;
  String get _label => _isPayment ? '付款方式' : '分类';
  String get _icon => _iconController.text.trim().isEmpty
      ? (_isPayment ? '💼' : '📦')
      : _iconController.text.trim();

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
          '🧾'
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
              '➕'
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
    _iconController = TextEditingController(text: widget.initialIcon);
    _type = widget.categoryType;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _iconController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving || !_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _isSaving = true;
      _saveError = null;
    });
    try {
      await widget.onSave(FinanceCatalogDraft(
        name: _nameController.text.trim(),
        icon: _icon,
        type: _type,
      ));
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
                      Text(_icon,
                          textScaler: TextScaler.noScaling,
                          style: const TextStyle(fontSize: 32)),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _nameController.text.trim().isEmpty
                                  ? '你的$_label'
                                  : _nameController.text.trim(),
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
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  onChanged: (_) => setState(() {}),
                  onFieldSubmitted: (_) => _save(),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? '请填写$_label名称'
                      : null,
                ),
                if (!_isPayment) ...[
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
                              : (_) => setState(() => _type = type),
                        ),
                    ],
                  ),
                  if (widget.isEditing)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '分类类型创建后不可修改',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: colors.onSurfaceVariant),
                      ),
                    ),
                  const SizedBox(height: 16),
                ],
                Text('选择图标', style: theme.textTheme.titleSmall),
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
                              : colors.surfaceContainerHighest
                                  .withValues(alpha: 0.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(
                              color: _icon == icon
                                  ? colors.primary
                                  : colors.outlineVariant
                                      .withValues(alpha: 0.4),
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            key: ValueKey('finance-icon-$icon'),
                            onTap: _isSaving
                                ? null
                                : () {
                                    FocusScope.of(context).unfocus();
                                    setState(() => _iconController.text = icon);
                                  },
                            child: SizedBox(
                              width: 48,
                              height: 48,
                              child: Center(
                                  child: Text(icon,
                                      textScaler: TextScaler.noScaling,
                                      style: const TextStyle(fontSize: 24))),
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
                  maxLength: 4,
                  decoration: InputDecoration(
                    labelText: '自定义图标',
                    helperText: '也可以粘贴喜欢的表情',
                    prefixIcon: const Icon(Icons.emoji_emotions_outlined),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                if (_saveError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_saveError!,
                        style: TextStyle(color: colors.error)),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed:
                _isSaving ? null : () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton.icon(
            key: const ValueKey('finance-catalog-save'),
            onPressed: _isSaving ? null : _save,
            icon: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check_rounded, size: 18),
            label: Text(_isSaving ? '保存中' : '保存'),
          ),
        ],
      ),
    );
  }
}
