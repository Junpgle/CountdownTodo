part of '../island_ui.dart';

IconData _getSpecialTodoIcon(String? specialType) {
  switch (specialType) {
    case 'delivery':
      return Icons.local_shipping; // matches local_shipping.xml
    case 'food':
      return Icons.shopping_bag; // matches shopping_bag.xml
    case 'cafe':
      return Icons.local_cafe; // matches local_cafe.xml
    case 'restaurant':
      return Icons.restaurant; // matches restaurant.xml
    default:
      return Icons.task_alt;
  }
}

/// Get color for special todo type (matches Android drawable fillColor)
Color _getSpecialTodoColor(String? specialType) {
  switch (specialType) {
    case 'delivery':
      return const Color(0xFFFF8142); // orange from local_shipping.xml
    case 'food':
      return const Color(0xFFFFAF22); // yellow from shopping_bag.xml
    case 'cafe':
      return const Color(0xFF6CCE25); // green from local_cafe.xml
    case 'restaurant':
      return const Color(0xFFF5726E); // red from restaurant.xml
    default:
      return IslandConfig.warningColor;
  }
}

/// Get display label for special todo type
String _getSpecialTodoLabel(String? specialType) {
  switch (specialType) {
    case 'delivery':
      return '快递';
    case 'food':
      return '外卖';
    case 'cafe':
      return '饮品';
    case 'restaurant':
      return '餐饮';
    default:
      return '待办';
  }
}

/// Check if reminder data represents a special todo
bool _isSpecialTodo(Map<String, dynamic>? data) {
  return data?['specialType'] != null &&
      data!['specialType'].toString().isNotEmpty;
}

// ── 通用按钮 ─────────────────────────────────────────────────────────────

extension _IslandUIRemindersExt on _IslandUIState {
  Widget _buildMainIslandContent() {
    if (_isFocusing) {
      final fd = _currentPayload?['focusData'] as Map?;
      final title = fd?['title']?.toString() ?? '专注事项';
      return Container(
        width: 100,
        height: 46,
        decoration: BoxDecoration(
          color: IslandConfig.bgColor,
          borderRadius: BorderRadius.circular(IslandConfig.capsuleRadius),
          border: Border.all(
            color: Colors.black.withValues(alpha: 0.5),
            width: 0.8,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            ValueListenableBuilder<String>(
              valueListenable: _timeNotifier,
              builder: (_, time, _) => Text(
                time,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      return Container(
        width: 120,
        height: 34,
        decoration: BoxDecoration(
          color: IslandConfig.bgColor,
          borderRadius: BorderRadius.circular(IslandConfig.capsuleRadius),
          border: Border.all(
            color: Colors.black.withValues(alpha: 0.5),
            width: 0.8,
          ),
        ),
        alignment: Alignment.center,
        child: ValueListenableBuilder<String>(
          valueListenable: _timeNotifier,
          builder: (_, time, _) => Text(
            time,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.0,
            ),
          ),
        ),
      );
    }
  }

  // ── ReminderPopup ────────────────────────────────────────────────────────

  Widget _buildReminderPopup() {
    final d = _reminderPopupData;
    if (d == null) return const SizedBox.shrink();

    final isSpecial = _isSpecialTodo(d);
    final specialType = d['specialType']?.toString();
    final type = d['type']?.toString() ?? 'todo';

    final IconData iconData;
    final Color iconColor;
    final String iconStr;
    final String label;

    if (isSpecial) {
      iconData = _getSpecialTodoIcon(specialType);
      iconColor = _getSpecialTodoColor(specialType);
      iconStr = '';
      label = _getSpecialTodoLabel(specialType);
    } else {
      iconData = Icons.task_alt;
      iconColor = IslandConfig.warningColor;
      iconStr = type == 'course' ? '📚' : (type == 'todo' ? '📝' : '⏰');
      label = type == 'course' ? '课程' : (type == 'todo' ? '待办' : '倒计时');
    }

    final mins = d['minutesUntil'] as int? ?? 0;
    final isEnd = d['isEnding'] as bool? ?? false;
    final status = isEnd ? '还有 $mins 分钟结束' : '还有 $mins 分钟开始';
    final itemId = d['itemId']?.toString();
    final subtitle = (d['subtitle'] ?? '').toString();

    return GestureDetector(
      key: const ValueKey('reminderPopup'),
      onPanStart: (_) => _startDrag(),
      child: Container(
        color: Colors.transparent,
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: icon + title
            Row(
              children: [
                if (isSpecial)
                  Icon(iconData, color: iconColor, size: 20)
                else
                  Text(iconStr, style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$label：${d['title']}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            // Subtitle (remark/code) - highlighted for special todos
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  color: isSpecial ? Colors.white : Colors.white70,
                  fontSize: isSpecial ? 13 : 11,
                  fontWeight: isSpecial ? FontWeight.bold : FontWeight.normal,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 6),
            Text(
              status,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                // 好的 → 发 action，标记已确认，pop reminderPopup
                Expanded(
                  child: _btn('好的', IslandConfig.successColor, () {
                    debugPrint(
                      '[IslandUI] reminder_ok clicked (popup), itemId=$itemId',
                    );
                    widget.onAction?.call('reminder_ok', 0);
                    if (itemId != null) {
                      _acknowledgedReminderIds.add(itemId);
                    }
                    _reminderPopupData = null;
                    _stack.clearToIdle();
                    _animateToState(IslandState.idle);
                  }),
                ),
                const SizedBox(width: 12),
                // 稍后提醒 → 发 action，标记已确认，pop 回 reminderCapsule
                Expanded(
                  child: _btn('稍后提醒', IslandConfig.warningColor, () {
                    debugPrint('[IslandUI] remind_later clicked (popup)');
                    widget.onAction?.call('remind_later', 0);
                    if (itemId != null) {
                      _acknowledgedReminderIds.add(itemId);
                    }
                    _reminderPopupData = null;
                    _stack.clearToIdle();
                    _animateToState(IslandState.idle);
                  }),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── ReminderSplit ────────────────────────────────────────────────────────

  Widget _buildReminderSplit() {
    final d = _reminderPopupData;
    if (d == null) {
      // 提醒数据丢失时回退到专注显示，避免完全透明无响应
      return _buildFocusTimerDisplay();
    }

    final isSpecial = _isSpecialTodo(d);
    final specialType = d['specialType']?.toString();
    final type = d['type']?.toString() ?? 'todo';
    final mins = '${d['minutesUntil'] as int? ?? 0}min';
    final expanded = _expandedReminderPart;

    final Widget reminderCapsule;
    if (isSpecial) {
      final iconData = _getSpecialTodoIcon(specialType);
      final color = _getSpecialTodoColor(specialType);
      reminderCapsule = _capsuleWithWidget(
        Icon(iconData, color: Colors.white, size: 12),
        '${d['title']} $mins',
        color,
      );
    } else {
      final icon = type == 'course' ? '📚' : (type == 'todo' ? '📝' : '⏰');
      reminderCapsule = _capsule(
        icon,
        '${d['title']} $mins',
        IslandConfig.warningColor,
      );
    }

    final row = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Listener(
          onPointerSignal: (pointerSignal) {
            if (pointerSignal is PointerScrollEvent) {
              final delta = pointerSignal.scrollDelta.dy;
              _mutateState(() {
                if (delta > 0) {
                  _remainingSecs = (_remainingSecs - 60).clamp(0, 999999);
                } else {
                  _remainingSecs += 60;
                }
              });
              _updateDisplayTime();
            }
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              final newExpanded = expanded == 'focusing' ? null : 'focusing';
              _mutateState(() {
                _expandedReminderPart = newExpanded;
              });
              Future.microtask(
                () => _animateToState(IslandState.reminderSplit),
              );
            },
            child: _capsule('🎯', _timeNotifier.value, IslandConfig.focusColor),
          ),
        ),
        const SizedBox(width: 12),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            final newExpanded = expanded == 'reminder' ? null : 'reminder';
            _mutateState(() {
              _expandedReminderPart = newExpanded;
            });
            Future.microtask(() => _animateToState(IslandState.reminderSplit));
          },
          child: reminderCapsule,
        ),
      ],
    );

    if (expanded == null) {
      if (_splitController.value <= 0.001) {
        return Center(child: row);
      }
      return FadeTransition(
        opacity: ReverseAnimation(_splitController),
        child: Center(child: row),
      );
    }

    final card = expanded == 'focusing'
        ? _expandedFocusing()
        : _expandedReminder();
    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 46,
          child: AnimatedBuilder(
            animation: _splitRowOpacity,
            child: Center(child: row),
            builder: (context, child) {
              if (_splitRowOpacity.value >= 0.999) {
                return child!;
              }
              if (_splitRowOpacity.value <= 0.001) {
                return const SizedBox.shrink();
              }
              return FadeTransition(opacity: _splitRowOpacity, child: child);
            },
          ),
        ),
        AnimatedBuilder(
          animation: _splitCardTop,
          builder: (context, child) => Positioned(
            top: _splitCardTop.value,
            left: 8,
            right: 8,
            child: child!,
          ),
          child: AnimatedBuilder(
            animation: _splitProgress,
            child: card,
            builder: (context, child) {
              if (_splitProgress.value >= 0.999) {
                return child!;
              }
              return FadeTransition(
                opacity: _splitProgress,
                child: ScaleTransition(
                  scale: _splitCardScale,
                  alignment: Alignment.topCenter,
                  child: child,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _capsule(String icon, String text, Color color) => Container(
    height: 30,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(15),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(icon, style: const TextStyle(fontSize: 12)),
        const SizedBox(width: 4),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 60),
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );

  /// Capsule variant that accepts a Widget icon (e.g. Material Icons)
  Widget _capsuleWithWidget(Widget iconWidget, String text, Color color) =>
      Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            iconWidget,
            const SizedBox(width: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 60),
              child: Text(
                text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );

  Widget _expandedFocusing() {
    final fd = _currentPayload?['focusData'] as Map?;
    final title = fd?['title']?.toString() ?? (_isCountdown ? '倒计时' : '自由专注');
    final note = fd?['note']?.toString().trim() ?? '';
    return Container(
      width: 260,
      height: 120,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: IslandConfig.bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.black.withValues(alpha: 0.5),
          width: 0.8,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ValueListenableBuilder<String>(
            valueListenable: _timeNotifier,
            builder: (_, t, _) => Text(
              '$t | $title',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (note.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                note,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.74),
                  fontSize: 10,
                  height: 1.15,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          SizedBox(height: note.isNotEmpty ? 8 : 12),
          Row(
            children: [
              // 完成 → push finishConfirm
              Expanded(
                child: _btn('完成', IslandConfig.successColor, () {
                  _stack.push(IslandState.finishConfirm, data: _currentPayload);
                  _animateToState(IslandState.finishConfirm);
                }),
              ),
              const SizedBox(width: 8),
              // 放弃 → push abandonConfirm
              Expanded(
                child: _btn('放弃', IslandConfig.dangerColor, () {
                  _stack.push(
                    IslandState.abandonConfirm,
                    data: _currentPayload,
                  );
                  _animateToState(IslandState.abandonConfirm);
                }),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _expandedReminder() {
    final d = _reminderPopupData;
    if (d == null) return const SizedBox.shrink();

    final isSpecial = _isSpecialTodo(d);
    final specialType = d['specialType']?.toString();
    final type = d['type']?.toString() ?? 'todo';

    final IconData iconData;
    final Color iconColor;
    final String label;

    if (isSpecial) {
      iconData = _getSpecialTodoIcon(specialType);
      iconColor = _getSpecialTodoColor(specialType);
      label = _getSpecialTodoLabel(specialType);
    } else {
      iconData = Icons.task_alt;
      iconColor = Colors.transparent;
      label = type == 'course' ? '课程' : (type == 'todo' ? '待办' : '倒计时');
    }

    final iconStr = type == 'course' ? '📚' : (type == 'todo' ? '📝' : '⏰');
    final mins = d['minutesUntil'] as int? ?? 0;
    final isEnd = d['isEnding'] as bool? ?? false;
    final status = isEnd ? '还有 $mins 分钟结束' : '还有 $mins 分钟开始';
    final itemId = d['itemId']?.toString();
    final subtitle = (d['subtitle'] ?? '').toString();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: IslandConfig.bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row: icon + title
          Row(
            children: [
              if (isSpecial)
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(iconData, color: iconColor, size: 20),
                )
              else
                Text(iconStr, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isSpecial ? '$label：${d['title']}' : '$label：${d['title']}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                color: isSpecial ? Colors.white : Colors.white70,
                fontSize: isSpecial ? 13 : 11,
                fontWeight: isSpecial ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
          const SizedBox(height: 2),
          Text(
            status,
            style: const TextStyle(color: Colors.white, fontSize: 11),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              // 好的 → 发 action，标记已确认，恢复 focusing
              Expanded(
                child: _btn('好的', IslandConfig.successColor, () {
                  debugPrint('[IslandUI] reminder_ok clicked, itemId=$itemId');
                  widget.onAction?.call('reminder_ok', 0);
                  if (itemId != null) {
                    _acknowledgedReminderIds.add(itemId);
                  }
                  _reminderPopupData = null;
                  _expandedReminderPart = null;
                  _stack.replaceTop(
                    IslandState.focusing,
                    data: _currentPayload,
                  );
                  _animateToState(IslandState.focusing);
                }),
              ),
              const SizedBox(width: 8),
              // 稍后提醒 → 发 action，收起但保留双胶囊
              Expanded(
                child: _btn('稍后提醒', IslandConfig.warningColor, () {
                  debugPrint('[IslandUI] remind_later clicked');
                  widget.onAction?.call('remind_later', 0);
                  if (itemId != null) {
                    _acknowledgedReminderIds.add(itemId);
                  }
                  _mutateState(() => _expandedReminderPart = null);
                  _animateToState(IslandState.reminderSplit);
                }),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── ReminderCapsule ──────────────────────────────────────────────────────

  Widget _buildReminderCapsule() {
    final d = _reminderPopupData;
    if (d == null) return const SizedBox.shrink();

    final isSpecial = _isSpecialTodo(d);
    final specialType = d['specialType']?.toString();
    final type = d['type']?.toString() ?? 'todo';

    final Widget capsuleWidget;
    if (isSpecial) {
      final iconData = _getSpecialTodoIcon(specialType);
      final color = _getSpecialTodoColor(specialType);
      capsuleWidget = _capsuleWithWidget(
        Icon(iconData, color: Colors.white, size: 12),
        '${d['title']} ${d['minutesUntil']}min',
        color,
      );
    } else {
      final icon = type == 'course' ? '📚' : (type == 'todo' ? '📝' : '⏰');
      capsuleWidget = _capsule(
        icon,
        '${d['title']} ${d['minutesUntil']}min',
        IslandConfig.warningColor,
      );
    }

    return GestureDetector(
      key: const ValueKey('reminderCapsule'),
      onPanStart: (_) => _startDrag(),
      // 点击胶囊 → push reminderPopup
      onTap: () {
        _stack.push(IslandState.reminderPopup, data: _currentPayload);
        _animateToState(IslandState.reminderPopup);
      },
      child: Container(
        color: Colors.transparent,
        padding: const EdgeInsets.all(8),
        child: capsuleWidget,
      ),
    );
  }

  // ── 特殊待办工具方法 ─────────────────────────────────────────────────────

  /// Get Material icon for special todo type (matches Android res/drawable icons)

  Widget _miniBtn(String label, Color color, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(13),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 11,
            ),
          ),
        ),
      );

  Widget _btn(String label, Color color, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 12,
        ),
      ),
    ),
  );

  void _startDrag() {
    if (widget.inLayoutDebugMode) return;
    final onStartDrag = widget.onStartDrag;
    if (onStartDrag != null) {
      onStartDrag();
      return;
    }
    try {
      startWindowDragging();
    } catch (_) {}
  }

  // ── 卡片轮播相关方法 ────────────────────────────────────────────────────

  // 初始化卡片列表
}
