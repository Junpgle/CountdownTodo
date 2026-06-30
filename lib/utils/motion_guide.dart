import 'package:flutter/material.dart';

class MotionGuide {
  /// 🚀 Uni-Sync 核心：冲突微震动效 (Shake)
  /// 用于引起用户对冲突字段的强制关注
  static Widget shake({required Widget child, bool trigger = false}) {
    if (!trigger) return child;

    return TweenAnimationBuilder<double>(
      key: ValueKey(trigger),
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 500),
      builder: (context, value, child) {
        final dx = (value < 0.1 || value > 0.9)
            ? 0.0
            : (value % 0.2 < 0.1 ? -5.0 : 5.0);

        return Transform.translate(
          offset: Offset(dx, 0),
          child: child,
        );
      },
      child: child,
    );
  }

  /// 🚀 Uni-Sync 核心：远程更新脉冲动效 (Pulse)
  /// 用于暗示“此处刚刚被队友修改过”
  static Widget pulse({required Widget child, bool trigger = false}) {
    if (!trigger) return child;

    return TweenAnimationBuilder<double>(
      key: ValueKey(trigger),
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 1500),
      builder: (context, value, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            if (value < 1.0)
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.rectangle,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: (1 - value) * 0.5),
                    width: value * 20,
                  ),
                ),
              ),
            child!,
          ],
        );
      },
      child: child,
    );
  }
}

// 示例用法：
// MotionGuide.shake(trigger: todo.hasConflict, child: MyTodoCard())
