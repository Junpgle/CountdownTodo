import 'package:flutter/material.dart';

import '../services/feature_tip_service.dart';
import 'coach_mark_overlay.dart';

/// A separate chapter lets existing users learn voice without replaying home.
class QuickVoiceChatGuide {
  static const tipId = 'coach_home_quick_voice';

  static Future<bool?> showIfNeeded({
    required BuildContext context,
    required GlobalKey addButtonKey,
  }) async {
    if (await FeatureTipService.hasTipBeenShown(tipId)) return null;
    if (!context.mounted || addButtonKey.currentContext == null) return null;

    final finished = await CoachMarkOverlay.show(
      context: context,
      steps: [
        CoachMarkStep(
          targetKey: addButtonKey,
          title: '长按加号，开口说话',
          description:
              '除了点击新增，你还可以按住加号录音，松手后自动转写并发送给 AI。'
              '例如：“明天上午九点提醒我交报告”。AI 会先生成操作确认卡片。',
        ),
        CoachMarkStep(
          targetKey: addButtonKey,
          title: '右上划，松手取消',
          description:
              '按住录音时，向右上方滑动，看到“松手取消”后松手，'
              '本次录音会被丢弃，不会上传。滑回普通区域可以恢复松手发送。',
        ),
        CoachMarkStep(
          targetKey: addButtonKey,
          title: '左上划，进入 AI 草稿',
          description:
              '想先核对内容？按住时向左上方滑动，再松手。'
              '语音会转成文字放入 AI 输入框，不会自动发送，你可以编辑后再发送。',
        ),
        CoachMarkStep(
          targetKey: addButtonKey,
          title: '使用前准备',
          description:
              '在“模型与 API 配置”中配置 AI 对话模型和普通小米 MiMo API Key。'
              '首次使用需要麦克风权限；授权前已松手的话，再次按住即可录音。'
              '识别与对话费用可在“AI 用量与费用”中查看。',
        ),
      ],
      onFinish: () {},
      onSkip: () {},
    );
    await FeatureTipService.markTipShown(tipId);
    return finished;
  }
}
