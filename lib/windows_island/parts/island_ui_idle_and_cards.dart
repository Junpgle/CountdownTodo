part of '../island_ui.dart';

Widget _buildCardTransition(Widget child, Animation<double> anim) {
  final offset = Tween<Offset>(
    begin: const Offset(0, 0.3),
    end: Offset.zero,
  ).animate(anim);
  return AnimatedBuilder(
    animation: anim,
    child: child,
    builder: (context, child) {
      if (anim.value <= 0.001) {
        return const SizedBox.shrink();
      }
      if (anim.value >= 0.999) {
        return child!;
      }
      return FadeTransition(
        opacity: anim,
        child: SlideTransition(position: offset, child: child),
      );
    },
  );
}

Widget _buildFadeSettleTransition(Widget child, Animation<double> anim) {
  return AnimatedBuilder(
    animation: anim,
    child: child,
    builder: (context, child) {
      if (anim.value <= 0.001) {
        return const SizedBox.shrink();
      }
      if (anim.value >= 0.999) {
        return child!;
      }
      return FadeTransition(opacity: anim, child: child);
    },
  );
}

extension _IslandUIIdleCardsExt on _IslandUIState {
  Widget _buildContent() {
    switch (_stack.current) {
      case IslandState.idle:
      case IslandState.focusing:
        return _buildIdle();
      case IslandState.hoverWide:
        return _buildHoverWide();
      case IslandState.stackedCard:
        return _buildStackedCard();
      case IslandState.splitAlert:
        return _buildSplitAlert();
      case IslandState.finishConfirm:
        return _buildConfirm('finish');
      case IslandState.abandonConfirm:
        return _buildConfirm('abandon');
      case IslandState.finishFinal:
        return _buildConfirm('final');
      case IslandState.copiedLink:
        return _buildCopiedLink();
      case IslandState.reminderPopup:
        return _buildReminderPopup();
      case IslandState.reminderSplit:
        return _buildReminderSplit();
      case IslandState.reminderCapsule:
        return _buildReminderCapsule();
      // 系统控制状态
      case IslandState.quickControls:
        return _buildQuickControls();
      case IslandState.musicPlayer:
        return _buildMusicPlayer();
      case IslandState.volumeControl:
        return _buildVolumeControl();
      case IslandState.brightnessControl:
        return _buildBrightnessControl();
      case IslandState.cardCarousel:
        return _buildCardCarousel();
    }
  }

  // ── SplitAlert ───────────────────────────────────────────────────────────

  Widget _buildSplitAlert() {
    return Container(
      padding: const EdgeInsets.all(2),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(20),
              ),
              alignment: Alignment.center,
              child: ValueListenableBuilder<String>(
                valueListenable: _timeNotifier,
                builder: (_, t, _) => Text(
                  t,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _startIdleAutoReturnTimer() {
    _idleAutoReturnTimer?.cancel();
    _idleAutoReturnTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      // 专注模式：滚回计时器
      if (_isFocusing && _isScrolledInFocus) {
        _mutateState(() {
          _isScrolledInFocus = false;
          _currentCardIndex = 0;
        });
        final newSize = _idleSizeForCard();
        _animateSizeTo(newSize);
        return;
      }
      if (_stack.current != IslandState.idle) return;
      _mutateState(() {
        _currentCardIndex = 0;
        _isScrolledInFocus = false;
      });
      final newSize = _idleSizeForCard();
      _animateSizeTo(newSize);
    });
  }

  void _resetIdleAutoReturnTimer() {
    _idleAutoReturnTimer?.cancel();
    _startIdleAutoReturnTimer();
  }

  void _returnToIdleCapsule() {
    _currentPayload?.remove('selectedCard');
    _stack.pop(IslandState.cardCarousel);
    _mutateState(() {
      _currentCardIndex = 0;
      _isScrolledInFocus = false;
    });
    _animateToState(_stack.base);
  }

  // ── Idle ─────────────────────────────────────────────────────────────────

  Widget _buildIdle() => GestureDetector(
    key: const ValueKey('idle'),
    behavior: HitTestBehavior.translucent,
    onTap: () {
      if (_isFocusing && !_isScrolledInFocus) {
        // 专注状态默认 → 展开专注详情
        _stack.push(IslandState.stackedCard, data: _currentPayload);
        _animateToState(IslandState.stackedCard);
      } else if (_isFocusing && _isScrolledInFocus) {
        // 专注状态下滚轮切换后
        final card = _cards[_currentCardIndex];
        if (card['type'] == 'focusing') {
          // 专注状态卡 → 展开专注详情（完成/放弃）
          _isScrolledInFocus = false;
          _currentCardIndex = 0;
          _stack.push(IslandState.stackedCard, data: _currentPayload);
          _animateToState(IslandState.stackedCard);
        } else if (card['type'] == 'focus') {
          // 今日专注统计 → 展开统计详情
          final detailData = {...?_currentPayload, 'selectedCard': card};
          _currentPayload = detailData;
          _stack.push(IslandState.stackedCard, data: detailData);
          _animateToState(IslandState.stackedCard);
        } else {
          // 其他卡片 → 展开对应详情
          final detailData = {...?_currentPayload, 'selectedCard': card};
          _currentPayload = detailData;
          _stack.push(IslandState.stackedCard, data: detailData);
          _animateToState(IslandState.stackedCard);
        }
      } else if (_cards.isNotEmpty &&
          _currentCardIndex > 0 &&
          _cards[_currentCardIndex]['type'] != 'time') {
        // 非时间卡片：直接展开对应类型详情
        final card = _cards[_currentCardIndex];
        final detailData = {...?_currentPayload, 'selectedCard': card};
        _currentPayload = detailData;
        _stack.push(IslandState.stackedCard, data: detailData);
        _animateToState(IslandState.stackedCard);
      } else {
        _initCards();
        _stack.push(IslandState.cardCarousel, data: _currentPayload);
        _animateToState(IslandState.cardCarousel);
        _startCarouselAutoReturnTimer();
      }
    },
    onLongPressStart: (_) => _startDrag(),
    child: Listener(
      onPointerSignal: (pointerSignal) {
        if (pointerSignal is PointerScrollEvent) {
          final delta = pointerSignal.scrollDelta.dy;

          // idle 态下滚轮切换卡片
          if (!_cardsLoaded) {
            _initCards();
          }

          if (_cards.isEmpty) return;

          // 重置自动返回定时器
          _resetIdleAutoReturnTimer();

          if (_isFocusing && _isScrolledInFocus) {
            // 专注状态下已滚轮切换：继续在卡片间滚动
            if (delta > 0) {
              // 向下滚 → 下一张卡片
              _mutateState(() {
                _currentCardIndex = (_currentCardIndex + 1) % _cards.length;
              });
            } else if (delta < 0) {
              // 向上滚 → 上一张卡片
              _mutateState(() {
                _currentCardIndex = _currentCardIndex == 0
                    ? _cards.length - 1
                    : _currentCardIndex - 1;
              });
            }
          } else if (!_isFocusing && _currentCardIndex > 0) {
            // idle 态下非计时显示：已经在卡片上，继续滚轮切换
            if (delta > 0) {
              _mutateState(() {
                _currentCardIndex = (_currentCardIndex + 1) % _cards.length;
              });
            } else if (delta < 0) {
              _mutateState(() {
                _currentCardIndex = _currentCardIndex == 0
                    ? _cards.length - 1
                    : _currentCardIndex - 1;
              });
            }
          } else if (_isFocusing && !_isScrolledInFocus) {
            // 专注状态默认显示计时：滚轮切换到卡片
            if (delta != 0) {
              _mutateState(() {
                _isScrolledInFocus = true;
                _currentCardIndex = delta > 0 ? 1 : _cards.length - 1;
              });
            }
          } else if (!_isFocusing && _currentCardIndex == 0) {
            // idle 态下显示计时：滚轮切换到卡片
            if (delta != 0) {
              _mutateState(() {
                _currentCardIndex = delta > 0 ? 1 : _cards.length - 1;
              });
            }
          }

          // 同时更新窗口大小
          final newSize = _idleSizeForCard();
          _animateSizeTo(newSize);
        }
      },
      child: Container(
        color: Colors.transparent,
        alignment: Alignment.center,
        child: (_isFocusing && !_isScrolledInFocus)
            ? _buildFocusTimerDisplay()
            : _buildIdleCardContent(),
      ),
    ),
  );

  // 专注计时器显示（从 _buildFocusing 提取，用于 idle 态下的专注显示）
  Widget _buildFocusTimerDisplay({bool forceTitle = false}) {
    final fd = _currentPayload?['focusData'] as Map?;
    final title = fd?['title']?.toString() ?? '专注事项';

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          return Transform.scale(
            scale: _isPulsing ? _pulseAnimation.value : 1.0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              alignment: Alignment.center,
              clipBehavior: Clip.hardEdge,
              decoration: const BoxDecoration(color: Colors.transparent),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxHeight <= 56;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (!compact)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (fd?['isPaused'] == true) ...[
                              const Text('⏸️ ', style: TextStyle(fontSize: 10)),
                            ],
                            Flexible(
                              child: ValueListenableBuilder<String>(
                                valueListenable: _pauseTimeNotifier,
                                builder: (context, pauseTime, _) {
                                  return Text(
                                    fd?['isPaused'] == true
                                        ? '暂停中 $pauseTime'
                                        : title,
                                    style: TextStyle(
                                      color: _isPulsing
                                          ? _colorAnimation.value?.withValues(
                                                  alpha: 0.7,
                                                ) ??
                                                Colors.white70
                                          : Colors.white70,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      height: 1.0,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      if (!compact) const SizedBox(height: 1),
                      ValueListenableBuilder<String>(
                        valueListenable: _timeNotifier,
                        builder: (_, time, _) {
                          if (_isCountdown &&
                              _remainingSecs == 0 &&
                              !_isPulsing) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              _triggerPomodoroAlert();
                            });
                          }
                          return FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              time,
                              style: TextStyle(
                                color: _isPulsing
                                    ? _colorAnimation.value ?? Colors.white
                                    : Colors.white,
                                fontSize: compact ? 16 : 16,
                                fontWeight: FontWeight.w900,
                                height: 1.0,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildIdleCardContent() {
    if (!_cardsLoaded || _cards.isEmpty) {
      if (!_cardsLoaded) {
        _initCards().then((_) {
          if (mounted) _mutateState(() {});
        });
      }
      return ValueListenableBuilder<String>(
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
      );
    }
    final card = _cards[_currentCardIndex];
    final type = card['type'] as String;
    final icon = card['icon'] as String;
    final title = card['title'] as String;
    final color = card['color'] as Color;

    // 时间卡片：显示当前时间
    if (type == 'time') {
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        transitionBuilder: _buildCardTransition,
        child: ValueListenableBuilder<String>(
          key: const ValueKey('idle_time_card'),
          valueListenable: _clockTimeNotifier,
          builder: (_, time, _) => Text(
            time,
            key: ValueKey(time),
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

    // 专注状态卡片：显示专注计时器
    if (type == 'focusing') {
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        transitionBuilder: _buildCardTransition,
        child: Container(
          key: ValueKey(_currentCardIndex),
          alignment: Alignment.center,
          child: _buildFocusTimerDisplay(forceTitle: true),
        ),
      );
    }

    // 数据卡片：显示内容
    final subtitle = card['subtitle'] as String;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      transitionBuilder: _buildCardTransition,
      child: Container(
        key: ValueKey(_currentCardIndex),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: IntrinsicWidth(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(icon, style: const TextStyle(fontSize: 12)),
              const SizedBox(width: 6),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 9,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 触发番茄钟结束强提醒
  void _triggerPomodoroAlert() {
    if (_isPulsing || !mounted) return;

    _mutateState(() {
      _isPulsing = true;
    });

    _pulseController.repeat(count: 3).then((_) {
      if (mounted) {
        _mutateState(() {
          _isPulsing = false;
        });

        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted && _stack.current == IslandState.focusing) {
            _showPomodoroFinishedCard();
          }
        });
      }
    });
  }

  void _showPomodoroFinishedCard() {
    _stack.push(IslandState.stackedCard, data: _currentPayload);
    _animateToState(IslandState.stackedCard);
  }

  // ── HoverWide ────────────────────────────────────────────────────────────

  Widget _buildHoverWide() {
    final p = _currentPayload;
    final dash = p?['dashboardData'] as Map?;
    final left =
        dash?['leftSlot']?.toString() ?? p?['topBarLeft']?.toString() ?? '';
    final right =
        dash?['rightSlot']?.toString() ?? p?['topBarRight']?.toString() ?? '';

    return GestureDetector(
      key: const ValueKey('hoverWide'),
      onTap: () {
        final restored = _stack.pop(IslandState.hoverWide);
        _animateToState(restored);
        if (_isFocusing) {
          _stack.push(IslandState.stackedCard, data: _currentPayload);
          _animateToState(IslandState.stackedCard);
        }
      },
      onLongPressStart: (_) => _startDrag(),
      child: Container(
        color: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Center(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  left,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ValueListenableBuilder<String>(
                  valueListenable: _timeNotifier,
                  builder: (_, t, _) => Text(
                    t,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  right,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── StackedCard ──────────────────────────────────────────────────────────

  Widget _buildStackedCard() {
    // 检查是否有选中的卡片类型（从 carousel 或 idle 点击进入）
    final selectedCard =
        _currentPayload?['selectedCard'] as Map<String, dynamic>?;
    if (selectedCard != null) {
      return _buildTypedDetail(selectedCard);
    }

    // 默认：专注详情
    final fd = _currentPayload?['focusData'] as Map?;
    final title = fd?['title']?.toString() ?? (_isCountdown ? '倒计时' : '自由专注');
    final tags = (fd?['tags'] as List?)?.join(' ') ?? '';
    final isLocal = fd?['syncMode']?.toString() != 'remote';

    return GestureDetector(
      key: const ValueKey('stackedCard'),
      onTap: () {
        _currentPayload?.remove('selectedCard');
        final restored = _stack.pop(IslandState.stackedCard);
        _animateToState(restored);
      },
      onLongPressStart: (_) => _startDrag(),
      child: Container(
        color: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ValueListenableBuilder<String>(
              valueListenable: _pauseTimeNotifier,
              builder: (context, pauseTime, _) {
                return ValueListenableBuilder<String>(
                  valueListenable: _timeNotifier,
                  builder: (_, t, _) => Text(
                    fd?['isPaused'] == true
                        ? '暂停中 $pauseTime | $t'
                        : '$t | $title',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      height: 1.0,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                );
              },
            ),
            if (tags.isNotEmpty)
              Text(
                tags,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                  height: 1.0,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            if (fd?['note']?.toString().trim().isNotEmpty == true) ...[
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  fd!['note'].toString().trim(),
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
            const SizedBox(height: 6),
            if (!isLocal)
              _btn('远端计时中，无法更改', Colors.white.withValues(alpha: 0.1), () {})
            else
              Row(
                children: [
                  Expanded(
                    child: _btn('完成', IslandConfig.successColor, () {
                      _stack.push(
                        IslandState.finishConfirm,
                        data: _currentPayload,
                      );
                      _animateToState(IslandState.finishConfirm);
                    }),
                  ),
                  const SizedBox(width: 8),
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
      ),
    );
  }

  // 卡片类型详情（待办/倒计时/课程/专注统计）
  Widget _buildTypedDetail(Map<String, dynamic> card) {
    final type = card['type'] as String;
    final icon = card['icon'] as String;
    final title = card['title'] as String;
    final subtitle = card['subtitle'] as String;
    final color = card['color'] as Color;

    String header;
    String detail;
    switch (type) {
      case 'todo':
        header = '📝 待办事项';
        detail = subtitle.isNotEmpty ? '到期时间: $subtitle' : '无截止日期';
        break;
      case 'countdown':
        header = '⏰ 倒计时';
        detail = subtitle.isNotEmpty ? subtitle : '目标日期已设置';
        break;
      case 'course':
        final dateLabel = card['dateLabel']?.toString() ?? '';
        final roomName = card['roomName']?.toString() ?? '';
        final startTime = card['startTime']?.toString() ?? '';
        header = '📚 课程';
        String info = dateLabel;
        if (startTime.isNotEmpty) info += ' $startTime';
        if (roomName.isNotEmpty) info += ' $roomName';
        detail = info.isNotEmpty ? info : '暂无详细信息';
        break;
      case 'focus':
        header = '🎯 专注统计';
        detail = subtitle.isNotEmpty ? subtitle : '暂无专注记录';
        break;
      default:
        header = '$icon $title';
        detail = subtitle;
    }

    return GestureDetector(
      key: const ValueKey('typedDetail'),
      onTap: () {
        _currentPayload?.remove('selectedCard');
        final restored = _stack.pop(IslandState.stackedCard);
        _animateToState(restored);
      },
      onLongPressStart: (_) => _startDrag(),
      child: Container(
        color: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              header,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
            const SizedBox(height: 3),
            Text(
              detail,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 10,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            _btn('关闭', color.withValues(alpha: 0.8), () {
              _currentPayload?.remove('selectedCard');
              final restored = _stack.pop(IslandState.stackedCard);
              _animateToState(restored);
            }),
          ],
        ),
      ),
    );
  }

  // ── Confirm (finish / abandon / final) ───────────────────────────────────

  Widget _buildConfirm(String mode) {
    String text = mode == 'finish'
        ? '确认完成?'
        : mode == 'abandon'
        ? '确认放弃?'
        : '专注完成';
    String ok = mode == 'final' ? '好的' : '确认';
    String cancel = '手滑了';
    final fd = _currentPayload?['focusData'] as Map?;
    final title = fd?['title']?.toString() ?? '专注内容';
    final isReverse = mode == 'abandon';
    final disabled = _confirmActionSent && mode != 'final';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w900,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$title | ${_timeNotifier.value}',
            style: const TextStyle(color: Colors.white70, fontSize: 11),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),
          if (mode == 'final')
            // FinishFinal: 好的 → clearToIdle
            _btn(ok, IslandConfig.successColor, () {
              _stack.clearToIdle();
              _animateToState(IslandState.idle);
            })
          else
            Row(
              children: [
                if (!isReverse) ...[
                  // FinishConfirm: 确认 → 发 action，清栈，push finishFinal
                  Expanded(
                    child: _btn(ok, IslandConfig.successColor, () {
                      if (disabled) return;
                      _confirmActionSent = true;
                      widget.onAction?.call('finish', _remainingSecs);
                      _stack.clearToIdle();
                      _stack.push(IslandState.finishFinal);
                      _animateToState(IslandState.finishFinal);
                    }),
                  ),
                  const SizedBox(width: 10),
                  // FinishConfirm: 手滑了 → pop，回到 stackedCard
                  Expanded(
                    child: _btn(cancel, IslandConfig.dangerColor, () {
                      _confirmActionSent = false;
                      final restored = _stack.pop(IslandState.finishConfirm);
                      _animateToState(restored);
                    }),
                  ),
                ] else ...[
                  // AbandonConfirm: 手滑了 → pop，回到 stackedCard
                  Expanded(
                    child: _btn(cancel, IslandConfig.successColor, () {
                      _confirmActionSent = false;
                      final restored = _stack.pop(IslandState.abandonConfirm);
                      _animateToState(restored);
                    }),
                  ),
                  const SizedBox(width: 10),
                  // AbandonConfirm: 确认 → 发 action，清栈到 idle
                  Expanded(
                    child: _btn(ok, IslandConfig.dangerColor, () {
                      if (disabled) return;
                      _confirmActionSent = true;
                      widget.onAction?.call('abandon', 0);
                      _stack.clearToIdle();
                      _animateToState(IslandState.idle);
                    }),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }

  // ── CopiedLink（双层灵动岛设计）──────────────────────────────────────────

  Widget _buildCopiedLink() {
    final d = _currentPayload?['copiedLinkData'] as Map?;
    if (d == null) return const SizedBox.shrink();
    final url = d['url']?.toString() ?? '';
    final display =
        d['displayUrl']?.toString() ??
        (url.length > 25 ? '${url.substring(0, 25)}...' : url);

    return Column(
      key: const ValueKey('copiedLink'),
      mainAxisSize: MainAxisSize.min,
      children: [
        // 主岛：居中显示
        Center(child: _buildMainIslandContent()),
        const SizedBox(height: 4),
        // 副岛：链接提示
        GestureDetector(
          onPanStart: (_) => _startDrag(),
          child: Container(
            width: 340,
            height: 46,
            decoration: BoxDecoration(
              color: IslandConfig.bgColor,
              borderRadius: BorderRadius.circular(IslandConfig.capsuleRadius),
              border: Border.all(
                color: Colors.black.withValues(alpha: 0.5),
                width: 0.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const Text('🔗', style: TextStyle(fontSize: 14)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '已复制: $display',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                _miniBtn('打开', IslandConfig.successColor, () {
                  widget.onAction?.call('open_link', 0, url);
                  _autoDismissTimer?.cancel();
                  final restored = _stack.pop(IslandState.copiedLink);
                  _animateToState(restored);
                }),
                const SizedBox(width: 6),
                _miniBtn('✕', Colors.white.withValues(alpha: 0.2), () {
                  _autoDismissTimer?.cancel();
                  final restored = _stack.pop(IslandState.copiedLink);
                  _animateToState(restored);
                }),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // 构建主岛内容（时钟或专注状态）
}
