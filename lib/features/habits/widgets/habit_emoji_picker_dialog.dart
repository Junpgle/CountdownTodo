import 'package:flutter/material.dart';

import '../../../utils/app_dialogs.dart';
import '../../../widgets/emoji_picker_dialog.dart';

/// 习惯 Emoji 分类。
enum HabitEmojiCategory {
  habits('常用习惯'),
  foodAndDrink('饮食饮品'),
  sportsAndHealth('运动健康'),
  studyAndWork('学习效率'),
  lifestyleAndHobby('生活兴趣'),
  natureAndAnimals('自然动物'),
  facesAndSymbols('表情符号');

  final String label;

  const HabitEmojiCategory(this.label);

  EmojiPickerCategory toEmojiPickerCategory() {
    switch (this) {
      case HabitEmojiCategory.habits:
        return EmojiPickerCategory.habits;
      case HabitEmojiCategory.foodAndDrink:
        return EmojiPickerCategory.foodAndDrink;
      case HabitEmojiCategory.sportsAndHealth:
        return EmojiPickerCategory.sportsAndHealth;
      case HabitEmojiCategory.studyAndWork:
        return EmojiPickerCategory.studyAndWork;
      case HabitEmojiCategory.lifestyleAndHobby:
        return EmojiPickerCategory.lifestyleAndHobby;
      case HabitEmojiCategory.natureAndAnimals:
        return EmojiPickerCategory.natureAndAnimals;
      case HabitEmojiCategory.facesAndSymbols:
        return EmojiPickerCategory.facesAndSymbols;
    }
  }
}

/// 习惯模块通用 Emoji 选择器弹窗（委托至 [AppEmojiPickerDialog]）。
class HabitEmojiPickerDialog extends StatelessWidget {
  final String initialIcon;
  final HabitEmojiCategory initialCategory;
  final String title;

  const HabitEmojiPickerDialog({
    super.key,
    required this.initialIcon,
    this.initialCategory = HabitEmojiCategory.habits,
    this.title = '选择图标',
  });

  static const String _recentPrefsKey = 'habit_recent_custom_emojis';

  /// 弹出 Emoji 选择器并返回选中的单个 Emoji；取消返回 null。
  static Future<String?> show(
    BuildContext context, {
    required String initialIcon,
    HabitEmojiCategory initialCategory = HabitEmojiCategory.habits,
    String title = '选择图标',
  }) {
    return showAppDialog<String>(
      context: context,
      builder: (_) => HabitEmojiPickerDialog(
        initialIcon: initialIcon,
        initialCategory: initialCategory,
        title: title,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppEmojiPickerDialog(
      initialIcon: initialIcon,
      initialCategory: initialCategory.toEmojiPickerCategory(),
      title: title,
      recentPrefsKey: _recentPrefsKey,
      inputKey: const ValueKey('habit-emoji-custom-input'),
      confirmKey: const ValueKey('habit-emoji-confirm'),
    );
  }
}
