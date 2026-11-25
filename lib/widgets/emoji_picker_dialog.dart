import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_dialogs.dart';
import '../utils/emoji_utils.dart';

/// 通用 Emoji 选择器分类。
enum EmojiPickerCategory {
  habits('常用习惯'),
  finance('消费账务'),
  foodAndDrink('饮食饮品'),
  sportsAndHealth('运动健康'),
  studyAndWork('学习效率'),
  lifestyleAndHobby('生活兴趣'),
  natureAndAnimals('自然动物'),
  facesAndSymbols('表情符号');

  final String label;

  const EmojiPickerCategory(this.label);
}

/// 通用 Emoji 选择器弹窗：
/// 支持任意 Unicode Emoji 的系统键盘输入/粘贴、分类浏览与最近使用记录。
class AppEmojiPickerDialog extends StatefulWidget {
  final String initialIcon;
  final EmojiPickerCategory initialCategory;
  final String title;
  final String recentPrefsKey;
  final Key inputKey;
  final Key confirmKey;

  const AppEmojiPickerDialog({
    super.key,
    required this.initialIcon,
    this.initialCategory = EmojiPickerCategory.habits,
    this.title = '选择图标',
    this.recentPrefsKey = defaultRecentPrefsKey,
    this.inputKey = const ValueKey('emoji-picker-custom-input'),
    this.confirmKey = const ValueKey('emoji-picker-confirm'),
  });

  static const String defaultRecentPrefsKey = 'app_recent_custom_emojis';
  static const int _maxRecentCount = 16;

  /// 弹出 Emoji 选择器并返回选中的单个 Emoji；取消返回 null。
  static Future<String?> show(
    BuildContext context, {
    required String initialIcon,
    EmojiPickerCategory initialCategory = EmojiPickerCategory.habits,
    String title = '选择图标',
    String recentPrefsKey = defaultRecentPrefsKey,
    Key inputKey = const ValueKey('emoji-picker-custom-input'),
    Key confirmKey = const ValueKey('emoji-picker-confirm'),
  }) {
    return showAppDialog<String>(
      context: context,
      builder: (_) => AppEmojiPickerDialog(
        initialIcon: initialIcon,
        initialCategory: initialCategory,
        title: title,
        recentPrefsKey: recentPrefsKey,
        inputKey: inputKey,
        confirmKey: confirmKey,
      ),
    );
  }

  /// 将选中的图标记录到指定偏好键的最近使用列表（最多保留 16 个）。
  static Future<void> recordRecentEmoji(
    String emoji, {
    String prefsKey = defaultRecentPrefsKey,
  }) async {
    final clean = emoji.trim();
    if (clean.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getStringList(prefsKey) ?? const <String>[];
      final updated = <String>[
        clean,
        ...existing.where((item) => item != clean && item.trim().isNotEmpty),
      ].take(_maxRecentCount).toList(growable: false);
      await prefs.setStringList(prefsKey, updated);
    } catch (_) {
      // 忽略最近记录写入失败。
    }
  }

  static final Map<EmojiPickerCategory, List<String>> _categoryEmojis =
      <EmojiPickerCategory, List<String>>{
        EmojiPickerCategory.habits: _dedupe(<String>[
          '🎯',
          '✅',
          '💧',
          '🧋',
          '🥤',
          '☕',
          '🌅',
          '🌙',
          '🛌',
          '💪',
          '📖',
          '🏃',
          '📚',
          '🧘',
          '💊',
          '🧹',
          '🔤',
          '🍎',
          '🦷',
          '🌿',
          '🥗',
          '🍰',
          '🍺',
          '🏊',
          '🚶',
          '✍️',
          '🎹',
          '⏰',
          '🌞',
          '🚰',
          '🛁',
          '🧼',
          '🪥',
          '🧴',
          '📝',
          '📔',
          '🎧',
          '📵',
          '💤',
          '🔥',
          '⭐',
          '🏆',
          '🌱',
        ]),
        EmojiPickerCategory.finance: _dedupe(<String>[
          '💰',
          '💳',
          '💵',
          '🏦',
          '👛',
          '💼',
          '🪙',
          '🧧',
          '🧾',
          '📈',
          '💹',
          '🛍️',
          '🛒',
          '🍜',
          '🥐',
          '🍱',
          '🥡',
          '☕',
          '🧋',
          '🍿',
          '🥬',
          '🚇',
          '🚕',
          '⛽',
          '🅿️',
          '✈️',
          '🚲',
          '🏠',
          '🔑',
          '💡',
          '🏢',
          '📶',
          '🔧',
          '📱',
          '💻',
          '👕',
          '💄',
          '🛋️',
          '🧴',
          '🐾',
          '📚',
          '🎓',
          '🎮',
          '🎬',
          '🎧',
          '🧳',
          '💊',
          '🩺',
          '🩻',
          '🏋️',
          '🎁',
          '🍻',
          '💌',
          '🔔',
          '📺',
          '🎵',
          '☁️',
          '🔌',
          '📦',
          '💬',
          '🌐',
          '🏆',
          '✨',
          '➕',
          '🧑‍💻',
        ]),
        EmojiPickerCategory.foodAndDrink: _dedupe(<String>[
          '🧋',
          '🥤',
          '☕',
          '🧃',
          '🍵',
          '🍺',
          '🍋',
          '🥥',
          '🥛',
          '🍓',
          '🍑',
          '🍇',
          '🍉',
          '🍹',
          '🍸',
          '🍷',
          '🫧',
          '🧊',
          '🍫',
          '🍰',
          '🍶',
          '🍾',
          '🥂',
          '🍻',
          '🧉',
          '🫖',
          '🍼',
          '🥗',
          '🍎',
          '🍏',
          '🍐',
          '🍊',
          '🍌',
          '🫐',
          '🍒',
          '🥝',
          '🥑',
          '🥦',
          '🥕',
          '🌽',
          '🍞',
          '🥐',
          '🥚',
          '🍳',
          '🥣',
          '🍱',
          '🍜',
          '🍣',
          '🍪',
          '🍩',
          '🍨',
          '🍯',
          '🥜',
        ]),
        EmojiPickerCategory.sportsAndHealth: _dedupe(<String>[
          '🏃',
          '🚶',
          '🏋️',
          '🧘',
          '🤸',
          '🚴',
          '🏊',
          '🧗',
          '⛹️',
          '🤾',
          '🏌️',
          '🏄',
          '🚣',
          '⛷️',
          '🏂',
          '🤼',
          '🥋',
          '🥊',
          '⚽',
          '🏀',
          '🏈',
          '⚾',
          '🎾',
          '🏐',
          '🏸',
          '🏓',
          '🏒',
          '🎯',
          '💪',
          '🦵',
          '🫀',
          '🫁',
          '🧠',
          '🩺',
          '💊',
          '🩹',
          '🩻',
          '🩸',
          '🦷',
          '👁️',
          '😴',
          '💤',
          '🛌',
          '🧖',
        ]),
        EmojiPickerCategory.studyAndWork: _dedupe(<String>[
          '📚',
          '📖',
          '📝',
          '✍️',
          '🔤',
          '🔢',
          '💻',
          '⌨️',
          '🖥️',
          '📱',
          '🎧',
          '🎙️',
          '📷',
          '🧠',
          '💡',
          '🔍',
          '📐',
          '📏',
          '📌',
          '📎',
          '🗂️',
          '📁',
          '📅',
          '🗓️',
          '⏰',
          '⏱️',
          '⏳',
          '⌛',
          '🎓',
          '🏫',
          '🔬',
          '🔭',
          '🧪',
          '🧬',
          '📊',
          '📈',
          '📉',
          '💼',
          '💰',
          '🪙',
          '🧾',
          '✉️',
          '🗞️',
          '📰',
        ]),
        EmojiPickerCategory.lifestyleAndHobby: _dedupe(<String>[
          '🎹',
          '🎸',
          '🎻',
          '🥁',
          '🎺',
          '🎷',
          '🎵',
          '🎶',
          '🎨',
          '🖌️',
          '🖍️',
          '🧶',
          '🪡',
          '📷',
          '🎬',
          '🎭',
          '🎮',
          '🕹️',
          '♟️',
          '🧩',
          '🎲',
          '🪁',
          '🧹',
          '🧺',
          '🧽',
          '🫧',
          '🪣',
          '🛏️',
          '🛋️',
          '🪴',
          '🕯️',
          '🫖',
          '🛍️',
          '🎁',
          '✈️',
          '🚂',
          '🚗',
          '🚲',
          '⛺',
          '🏖️',
          '🏔️',
          '🗺️',
          '🧭',
          '📸',
        ]),
        EmojiPickerCategory.natureAndAnimals: _dedupe(<String>[
          '🌱',
          '🌿',
          '☘️',
          '🍀',
          '🪴',
          '🌵',
          '🌴',
          '🌳',
          '🌲',
          '🍁',
          '🍂',
          '🌸',
          '🌺',
          '🌻',
          '🌼',
          '🌷',
          '🌹',
          '🪷',
          '☀️',
          '🌤️',
          '⛅',
          '🌈',
          '🌧️',
          '❄️',
          '🌊',
          '🔥',
          '💧',
          '🌙',
          '⭐',
          '🌟',
          '✨',
          '⚡',
          '🐱',
          '🐶',
          '🦊',
          '🐼',
          '🐨',
          '🐯',
          '🦁',
          '🐸',
          '🐧',
          '🦉',
          '🦋',
          '🐝',
          '🐢',
          '🐳',
          '🐬',
          '🦄',
        ]),
        EmojiPickerCategory.facesAndSymbols: _dedupe(<String>[
          '😀',
          '😄',
          '😁',
          '😊',
          '🥰',
          '😎',
          '🤓',
          '🥳',
          '😌',
          '🤔',
          '🫡',
          '🤗',
          '🙌',
          '👏',
          '👍',
          '✌️',
          '🤞',
          '👌',
          '🙏',
          '🫶',
          '❤️',
          '🧡',
          '💛',
          '💚',
          '🩵',
          '💙',
          '💜',
          '🤍',
          '💯',
          '✅',
          '☑️',
          '⭕',
          '❌',
          '❗',
          '❓',
          '⚡',
          '🔔',
          '🔕',
          '🎉',
          '🎊',
          '🏆',
          '🥇',
          '🎖️',
          '💎',
          '🔮',
          '🧿',
          '♾️',
          '🚀',
        ]),
      };

  static List<String> _dedupe(List<String> items) {
    final seen = <String>{};
    final result = <String>[];
    for (final item in items) {
      if (seen.add(item)) result.add(item);
    }
    return List<String>.unmodifiable(result);
  }

  @override
  State<AppEmojiPickerDialog> createState() => _AppEmojiPickerDialogState();
}

class _AppEmojiPickerDialogState extends State<AppEmojiPickerDialog> {
  final TextEditingController _customController = TextEditingController();
  final FocusNode _customFocusNode = FocusNode();

  late String _selectedIcon;
  EmojiPickerCategory? _selectedCategory;
  bool _showRecent = false;
  List<String> _recentEmojis = const <String>[];
  String? _customError;

  @override
  void initState() {
    super.initState();
    _selectedIcon = widget.initialIcon.trim().isNotEmpty
        ? widget.initialIcon.trim()
        : '🎯';
    _selectedCategory = widget.initialCategory;
    _loadRecentEmojis();
  }

  @override
  void dispose() {
    _customController.dispose();
    _customFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadRecentEmojis() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved =
          prefs.getStringList(widget.recentPrefsKey) ?? const <String>[];
      if (!mounted) return;
      final cleaned = saved
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
      setState(() {
        _recentEmojis = cleaned;
      });
    } catch (_) {
      // 忽略本地最近记录读取异常，不阻塞弹窗使用。
    }
  }

  String _helperHintForPlatform(TargetPlatform platform) {
    switch (platform) {
      case TargetPlatform.macOS:
        return '可用 ⌃⌘Space 调出系统表情键盘，或直接粘贴';
      case TargetPlatform.windows:
        return '可用 Win + . 调出系统表情键盘，或直接粘贴';
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return '可用系统表情键盘输入或粘贴任意 Emoji';
    }
  }

  void _handleCustomInputChanged(String value) {
    final composing = _customController.value.composing;
    if (composing.isValid && !composing.isCollapsed) {
      return;
    }

    if (value.trim().isEmpty) {
      setState(() => _customError = null);
      return;
    }

    final extracted = EmojiUtils.extractSingleEmoji(value);
    if (extracted == null) {
      setState(() => _customError = '请输入或粘贴 1 个 Emoji');
      return;
    }

    setState(() {
      _selectedIcon = extracted;
      _customError = null;
    });
  }

  void _selectPresetEmoji(String emoji) {
    _customFocusNode.unfocus();
    setState(() {
      _selectedIcon = emoji;
      _customController.clear();
      _customError = null;
    });
  }

  void _confirmSelection() {
    if (_customError != null) return;
    final clean = _selectedIcon.trim();
    if (clean.isEmpty) return;
    unawaited(
      AppEmojiPickerDialog.recordRecentEmoji(
        clean,
        prefsKey: widget.recentPrefsKey,
      ),
    );
    Navigator.of(context).pop(clean);
  }

  List<String> get _displayedEmojis {
    if (_showRecent) return _recentEmojis;
    final category = _selectedCategory ?? widget.initialCategory;
    return AppEmojiPickerDialog._categoryEmojis[category] ?? const <String>[];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final media = MediaQuery.of(context);
    final dialogWidth = math.min(media.size.width - 64, 420.0);
    final gridHeight = (media.size.height - media.viewInsets.bottom - 380)
        .clamp(140.0, 230.0);
    final emojis = _displayedEmojis;
    final canConfirm = _customError == null && _selectedIcon.trim().isNotEmpty;

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: dialogWidth,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: colorScheme.primary,
                        width: 1.5,
                      ),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Text(
                          _selectedIcon,
                          style: const TextStyle(fontSize: 28),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      key: widget.inputKey,
                      controller: _customController,
                      focusNode: _customFocusNode,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        labelText: '自定义 Emoji',
                        hintText: '输入或粘贴任意 Emoji',
                        helperText: _helperHintForPlatform(theme.platform),
                        helperMaxLines: 2,
                        errorText: _customError,
                        border: const OutlineInputBorder(),
                        isDense: true,
                        suffixIcon: _customController.text.isNotEmpty
                            ? IconButton(
                                tooltip: '清空',
                                onPressed: () {
                                  setState(() {
                                    _customController.clear();
                                    _customError = null;
                                  });
                                },
                                icon: const Icon(Icons.close_rounded, size: 18),
                              )
                            : null,
                      ),
                      onChanged: _handleCustomInputChanged,
                      onSubmitted: (_) {
                        if (canConfirm) _confirmSelection();
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    if (_recentEmojis.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: const Text('最近'),
                          selected: _showRecent,
                          onSelected: (_) {
                            setState(() => _showRecent = true);
                          },
                        ),
                      ),
                    for (final category in EmojiPickerCategory.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(category.label),
                          selected:
                              !_showRecent && _selectedCategory == category,
                          onSelected: (_) {
                            setState(() {
                              _showRecent = false;
                              _selectedCategory = category;
                            });
                          },
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: gridHeight,
                child: GridView.builder(
                  itemCount: emojis.length,
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 48,
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 6,
                  ),
                  itemBuilder: (context, index) {
                    final emoji = emojis[index];
                    final isSelected = _selectedIcon == emoji;
                    return Material(
                      color: isSelected
                          ? colorScheme.primaryContainer
                          : colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => _selectPresetEmoji(emoji),
                        child: Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected
                                  ? colorScheme.primary
                                  : colorScheme.outlineVariant.withValues(
                                      alpha: 0.4,
                                    ),
                              width: isSelected ? 1.5 : 1,
                            ),
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Padding(
                              padding: const EdgeInsets.all(2),
                              child: Text(
                                emoji,
                                style: const TextStyle(fontSize: 22),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: widget.confirmKey,
          onPressed: canConfirm ? _confirmSelection : null,
          child: const Text('确定'),
        ),
      ],
    );
  }
}
