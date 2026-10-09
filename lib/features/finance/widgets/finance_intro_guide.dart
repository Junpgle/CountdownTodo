import 'package:flutter/material.dart';

import '../../../services/feature_tip_service.dart';
import '../../../widgets/coach_mark_overlay.dart';

class FinanceIntroGuide {
  static const tipId = 'coach_finance_intro';

  static Future<bool?> show({
    required BuildContext context,
    required GlobalKey addKey,
    required GlobalKey budgetKey,
    required GlobalKey moreKey,
    required VoidCallback onOpenSettings,
    bool force = false,
  }) async {
    if (!force && await FeatureTipService.hasTipBeenShown(tipId)) return null;
    if (!context.mounted ||
        addKey.currentContext == null ||
        moreKey.currentContext == null) {
      return null;
    }
    final completed = await CoachMarkOverlay.show(
      context: context,
      steps: [
        CoachMarkStep(
          targetKey: addKey,
          title: '从记一笔开始',
          description:
              '点击底部加号，记录支出、收入或退款，并选择分类、付款方式和发生日期。'
              '概览查看收支，底部“账单”可以搜索、筛选和修改记录。',
        ),
        CoachMarkStep(
          targetKey: moreKey,
          title: '分类可以自己定',
          description:
              '从右上角“更多操作”进入“记账设置 → 分类目录”，'
              '可新增支出或收入的一级分类，也能添加二级小类，例如“餐饮 → 早餐”。'
              '分类名称和图标也可以按自己的习惯调整。',
        ),
        CoachMarkStep(
          targetKey: moreKey,
          title: '管理自己的付款方式',
          description:
              '同样在“分类目录”中切换到“付款方式”，可以添加常用账户或银行卡。'
              '记账时选择对应付款方式，之后更方便按账户查看收支。',
        ),
        CoachMarkStep(
          targetKey: budgetKey,
          title: '预算与周期账单',
          description:
              '点击这里设置月度总预算或分类预算，了解还可以花多少。'
              '房租、订阅等固定收支，可以到“更多操作 → 自动化与快捷模板”中设置周期账单。',
        ),
        CoachMarkStep(
          targetKey: moreKey,
          title: '需要时再开启云同步',
          description:
              '记账默认仅保存在本机。如需在多台设备使用，登录同一账号，'
              '到“记账设置 → 其他设置”打开“记账云同步”。'
              '开启后现有本地记账数据也会排队同步；不需要时保持关闭即可。',
          buttonLabel: '去设置',
          finishOnButtonTap: true,
          onButtonTap: () {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) onOpenSettings();
            });
          },
        ),
      ],
      onFinish: () {},
      onSkip: () {},
      dismissOnBack: true,
    );
    await FeatureTipService.markTipShown(tipId);
    return completed;
  }
}
