part of '../island_ui.dart';

extension _IslandUICarouselControlsExt on _IslandUIState {
  Future<void> _initCards() async {
    if (_cardsLoaded) return;

    final focusingCard = _cards
        .where((c) => c['type'] == 'focusing')
        .firstOrNull;

    _cards.clear();
    _currentCardIndex = 0;

    // index 0: 时间卡片（始终在首位）
    _cards.add({
      'type': 'time',
      'icon': '🕐',
      'title': '当前时间',
      'subtitle': '',
      'color': Colors.white54,
    });

    final p = _currentPayload;
    final seenCards = <String>{};

    void addPayloadCard(
      String type,
      String icon,
      String title,
      String subtitle,
      Color color, [
      Map<String, dynamic>? extra,
    ]) {
      if (title.trim().isEmpty) return;
      final key = '$type|$title|$subtitle';
      if (!seenCards.add(key)) return;
      _cards.add({
        'type': type,
        'icon': icon,
        'title': title,
        'subtitle': subtitle,
        'color': color,
        ...?extra,
      });
    }

    String iconForType(String type) => switch (type) {
      'todo' => '📝',
      'course' => '📚',
      'countdown' => '⏰',
      'focus' => '🎯',
      'date' => '📅',
      'weekday' => '📆',
      'record' => '✅',
      _ => '📋',
    };

    Color colorForType(String type) => switch (type) {
      'course' => IslandConfig.warningColor,
      'countdown' => IslandConfig.dangerColor,
      'focus' => IslandConfig.successColor,
      _ => IslandConfig.focusColor,
    };

    final rawSlotCards = p?['slotCards'];
    if (rawSlotCards is List) {
      for (final rawCard in rawSlotCards) {
        if (rawCard is! Map) continue;
        final type = rawCard['type']?.toString() ?? 'slot';
        final title =
            rawCard['title']?.toString() ??
            rawCard['display']?.toString() ??
            '';
        final subtitle =
            rawCard['subtitle']?.toString() ??
            rawCard['note']?.toString() ??
            rawCard['time']?.toString() ??
            '';
        addPayloadCard(
          type,
          iconForType(type),
          title,
          subtitle,
          colorForType(type),
          {
            'display': rawCard['display']?.toString() ?? '',
            'dateLabel': rawCard['time']?.toString() ?? '',
            'roomName': rawCard['location']?.toString() ?? '',
            'startTime': rawCard['time']?.toString() ?? '',
            'note': rawCard['note']?.toString() ?? '',
            'specialType': rawCard['specialType']?.toString() ?? '',
          },
        );
      }
    }

    if (_cards.length == 1) {
      final dash = p?['dashboardData'] as Map?;
      final legacy = p?['legacy'] as Map?;
      final detailType =
          legacy?['detail_type']?.toString() ?? p?['detail_type']?.toString();
      final detailTitle =
          legacy?['detail_title']?.toString() ?? p?['detail_title']?.toString();
      final detailSubtitle =
          legacy?['detail_note']?.toString().isNotEmpty == true
          ? legacy!['detail_note']?.toString()
          : legacy?['detail_subtitle']?.toString() ??
                p?['detail_subtitle']?.toString();

      if (detailType != null && detailTitle != null && detailTitle.isNotEmpty) {
        addPayloadCard(
          detailType,
          iconForType(detailType),
          detailTitle,
          detailSubtitle ?? '',
          colorForType(detailType),
        );
      }

      final leftSlot = dash?['leftSlot']?.toString() ?? '';
      final rightSlot = dash?['rightSlot']?.toString() ?? '';
      addPayloadCard('slot_left', '📌', leftSlot, '', IslandConfig.focusColor);
      addPayloadCard(
        'slot_right',
        '📌',
        rightSlot,
        '',
        IslandConfig.warningColor,
      );
    }

    if (_cards.length == 1) {
      _addDefaultCard();
    }

    if (focusingCard != null) {
      _cards.add(focusingCard);
    }

    _cardsLoaded = true;
  }

  void _addDefaultCard() {
    _cards.add({
      'type': 'default',
      'icon': '📋',
      'title': '暂无内容',
      'subtitle': '点击添加待办或课程',
      'color': Colors.white54,
    });
  }

  // 启动自动返回定时器
  void _startCarouselAutoReturnTimer() {
    _carouselAutoReturnTimer?.cancel();
    _carouselAutoReturnTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _stack.current == IslandState.cardCarousel) {
        _returnToIdleCapsule();
      }
    });
  }

  // 构建卡片并排平铺
  Widget _buildCardCarousel() {
    final visibleCards = _cards.where((c) => c['type'] != 'focusing').toList();
    if (visibleCards.isEmpty) {
      return const Center(
        child: Text(
          '暂无卡片',
          style: TextStyle(color: Colors.white70, fontSize: 12),
        ),
      );
    }

    return GestureDetector(
      key: const ValueKey('cardCarousel'),
      onTap: () {
        _returnToIdleCapsule();
      },
      onLongPressStart: (_) => _startDrag(),
      child: Container(
        color: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: SizedBox.expand(
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            findItemIndexCallback: (Key key) {
              if (key is ValueKey<String>) {
                final t = key.value;
                final idx = visibleCards.indexWhere((c) => c['type'] == t);
                return idx != -1 ? idx : null;
              }
              return null;
            },
            itemCount: visibleCards.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (context, index) {
              final card = visibleCards[index];
              final type = card['type'] as String;
              final icon = card['icon'] as String;
              final title = card['title'] as String;
              final subtitle = card['subtitle'] as String;
              final color = card['color'] as Color;

              Widget cardContent;
              VoidCallback onTap;

              if (type == 'time') {
                cardContent = Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(icon, style: const TextStyle(fontSize: 14)),
                    const SizedBox(height: 4),
                    ValueListenableBuilder<String>(
                      valueListenable: _timeNotifier,
                      builder: (_, time, _) => Text(
                        time,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                );
                onTap = () {
                  _returnToIdleCapsule();
                };
              } else {
                cardContent = Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(icon, style: const TextStyle(fontSize: 14)),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 8,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                );
                onTap = () {
                  final detailData = {
                    ...?_currentPayload,
                    'selectedCard': card,
                  };
                  _currentPayload = detailData;
                  _stack.pop(IslandState.cardCarousel);
                  _stack.push(IslandState.stackedCard, data: detailData);
                  _animateToState(IslandState.stackedCard);
                };
              }

              return RepaintBoundary(
                key: ValueKey<String>(type),
                child: SizedBox(
                  width: 76,
                  height: 80,
                  child: GestureDetector(
                    onTap: onTap,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: cardContent,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  // ── 系统控制UI ─────────────────────────────────────────────────────────

  // 快速控制面板（3 按钮横排：音量 / 亮度 / 音乐）
  Widget _buildQuickControls() {
    return GestureDetector(
      key: const ValueKey('quickControls'),
      onTap: () {
        _cancelAllSystemControlTimers();
        _stack.pop(IslandState.quickControls);
        _animateToState(_stack.current);
      },
      onPanStart: (_) => _startDrag(),
      child: Container(
        color: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _quickControlBtn('🔊', '音量', IslandConfig.focusColor, () {
              SystemControlService.initVolume();
              _stack.push(IslandState.volumeControl, data: _currentPayload);
              _animateToState(IslandState.volumeControl);
              _startSystemControlAutoReturnTimer();
            }),
            _quickControlBtn('☀️', '亮度', IslandConfig.warningColor, () {
              _stack.push(IslandState.brightnessControl, data: _currentPayload);
              _animateToState(IslandState.brightnessControl);
              _startSystemControlAutoReturnTimer();
            }),
            _quickControlBtn('🎵', '音乐', IslandConfig.focusColor, () {
              _ensureMediaPollingStarted();
              _stack.push(IslandState.musicPlayer, data: _currentPayload);
              _animateToState(IslandState.musicPlayer);
              _startSystemControlAutoReturnTimer();
            }),
          ],
        ),
      ),
    );
  }

  Widget _quickControlBtn(
    String icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 80,
      height: 50,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    ),
  );

  // ── 音乐播放器 ─────────────────────────────────────────────────────────

  // 音乐播放器（包含歌词显示）
  Widget _buildMusicPlayer() {
    return GestureDetector(
      key: const ValueKey('musicPlayer'),
      onTap: () {
        _systemControlAutoReturnTimer?.cancel();
        _stack.pop(IslandState.musicPlayer);
        _stack.push(IslandState.quickControls, data: _currentPayload);
        _animateToState(IslandState.quickControls);
        _startQuickControlsAutoReturnTimer();
      },
      onPanStart: (_) => _startDrag(),
      child: Container(
        color: Colors.transparent,
        padding: const EdgeInsets.all(14),
        child: ValueListenableBuilder<MediaInfo>(
          valueListenable: SystemControlService.mediaInfoListenable,
          builder: (context, smtc, _) {
            final musicData = _currentPayload?['musicData'] as Map?;
            final hasMusic = musicData != null && musicData.isNotEmpty;
            final smtcHasMusic = !smtc.isEmpty;
            final title =
                musicData?['title']?.toString() ??
                (smtcHasMusic ? smtc.title : '');
            final artist =
                musicData?['artist']?.toString() ??
                (smtcHasMusic ? smtc.artist : '');
            final isPlaying =
                musicData?['isPlaying'] as bool? ??
                (smtc.status == PlaybackStatus.playing);
            final currentTime = musicData?['currentTime']?.toString() ?? '0:00';
            final totalTime = musicData?['totalTime']?.toString() ?? '0:00';
            final lyrics = musicData?['lyrics']?.toString() ?? '';
            final currentLyricIndex =
                musicData?['currentLyricIndex'] as int? ?? 0;
            final shuffleOn = musicData?['shuffle'] as bool? ?? false;
            final repeatMode = musicData?['repeat']?.toString() ?? 'off';
            final showContent = hasMusic || smtcHasMusic;
            return showContent
                ? _buildMusicPlayerContent(
                    title,
                    artist,
                    isPlaying,
                    currentTime,
                    totalTime,
                    lyrics,
                    currentLyricIndex,
                    shuffleOn,
                    repeatMode,
                  )
                : _buildMusicEmptyState();
          },
        ),
      ),
    );
  }

  Widget _buildMusicEmptyState() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('🎵', style: TextStyle(fontSize: 28)),
        const SizedBox(height: 8),
        const Text(
          '暂无播放中的音乐',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '打开音乐播放器后将自动显示',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.4),
            fontSize: 10,
          ),
        ),
        const SizedBox(height: 12),
        _miniBtn('返回', Colors.white.withValues(alpha: 0.15), () {
          _systemControlAutoReturnTimer?.cancel();
          _quickControlsAutoReturnTimer?.cancel();
          _sliderDebounce?.cancel();
          _quickControlsAutoReturnTimer?.cancel();
          _quickControlsAutoReturnTimer?.cancel();
          _stack.pop(IslandState.musicPlayer);
          _stack.push(IslandState.quickControls, data: _currentPayload);
          _animateToState(IslandState.quickControls);
        }),
      ],
    );
  }

  Widget _buildMusicPlayerContent(
    String title,
    String artist,
    bool isPlaying,
    String currentTime,
    String totalTime,
    String lyrics,
    int currentLyricIndex,
    bool shuffleOn,
    String repeatMode,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: IslandConfig.focusColor.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.music_note,
                color: Colors.white,
                size: 26,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title.isNotEmpty ? title : '未知歌曲',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    artist.isNotEmpty ? artist : '未知艺术家',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        currentTime,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 9,
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onPanStart: (details) {
                            final box =
                                context.findRenderObject() as RenderBox?;
                            if (box == null) return;
                            final pos = box.globalToLocal(
                              details.localPosition,
                            );
                            final fraction = (pos.dx / box.size.width).clamp(
                              0.0,
                              1.0,
                            );
                            widget.onAction?.call(
                              'music_seek',
                              (fraction * 1000).round(),
                            );
                          },
                          child: Container(
                            height: 6,
                            margin: const EdgeInsets.symmetric(horizontal: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: _calculateProgress(
                                currentTime,
                                totalTime,
                              ),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: IslandConfig.focusColor,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Text(
                        totalTime,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // 控制按钮行
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _miniBtn(
              shuffleOn ? '🔀' : '➡️',
              shuffleOn
                  ? IslandConfig.focusColor.withValues(alpha: 0.4)
                  : Colors.white.withValues(alpha: 0.1),
              () => widget.onAction?.call('music_shuffle'),
            ),
            const SizedBox(width: 10),
            _miniBtn('⏮', Colors.white.withValues(alpha: 0.15), () {
              widget.onAction?.call('music_prev');
              _resetSystemControlAutoReturnTimer();
            }),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                widget.onAction?.call('music_toggle');
                _resetSystemControlAutoReturnTimer();
              },
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: IslandConfig.focusColor,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(
                  isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
            const SizedBox(width: 8),
            _miniBtn('⏭', Colors.white.withValues(alpha: 0.15), () {
              widget.onAction?.call('music_next');
              _resetSystemControlAutoReturnTimer();
            }),
            const SizedBox(width: 10),
            _miniBtn(
              repeatMode == 'one'
                  ? '🔂'
                  : repeatMode == 'all'
                  ? '🔁'
                  : '➡️',
              repeatMode != 'off'
                  ? IslandConfig.focusColor.withValues(alpha: 0.4)
                  : Colors.white.withValues(alpha: 0.1),
              () => widget.onAction?.call('music_repeat'),
            ),
          ],
        ),
        // 歌词显示区域
        if (lyrics.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Text(
                  '🎵 歌词',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                ..._buildLyricsLines(lyrics, currentLyricIndex),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // 计算播放进度
  double _calculateProgress(String current, String total) {
    try {
      final currentParts = current.split(':');
      final totalParts = total.split(':');

      if (currentParts.length == 2 && totalParts.length == 2) {
        final currentSeconds =
            int.parse(currentParts[0]) * 60 + int.parse(currentParts[1]);
        final totalSeconds =
            int.parse(totalParts[0]) * 60 + int.parse(totalParts[1]);

        if (totalSeconds > 0) {
          return (currentSeconds / totalSeconds).clamp(0.0, 1.0);
        }
      }
    } catch (_) {}
    return 0.0;
  }

  // 构建歌词行
  List<Widget> _buildLyricsLines(String lyrics, int currentIndex) {
    final lines = lyrics.split('\n');
    final widgets = <Widget>[];

    for (int i = 0; i < lines.length && i < 3; i++) {
      final line = lines[i].trim();
      if (line.isNotEmpty) {
        final isCurrentLine = i == currentIndex;
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              line,
              style: TextStyle(
                color: isCurrentLine ? Colors.white : Colors.white70,
                fontSize: isCurrentLine ? 12 : 11,
                fontWeight: isCurrentLine ? FontWeight.bold : FontWeight.normal,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      }
    }

    return widgets;
  }

  // ── 音量控制 ─────────────────────────────────────────────────────────

  Widget _buildVolumeControl() {
    final currentVolume = SystemControlService.getVolumeSync();
    final isMuted = currentVolume <= 0.01;
    final volumePercent = (currentVolume * 100).round();

    String volumeIcon;
    if (isMuted) {
      volumeIcon = '🔇';
    } else if (volumePercent < 30) {
      volumeIcon = '🔈';
    } else if (volumePercent < 70) {
      volumeIcon = '🔉';
    } else {
      volumeIcon = '🔊';
    }

    return GestureDetector(
      key: const ValueKey('volumeControl'),
      onTap: () {
        _systemControlAutoReturnTimer?.cancel();
        _stack.pop(IslandState.volumeControl);
        _stack.push(IslandState.quickControls, data: _currentPayload);
        _animateToState(IslandState.quickControls);
        _startQuickControlsAutoReturnTimer();
      },
      onPanStart: (_) => _startDrag(),
      child: Listener(
        onPointerSignal: (pointerSignal) {
          if (pointerSignal is PointerScrollEvent) {
            final delta = pointerSignal.scrollDelta.dy;
            final current = SystemControlService.getVolumeSync();
            final newVol = (current - delta * 0.003).clamp(0.0, 1.0);
            SystemControlService.setVolume(newVol);
            _mutateState(() {});
            _resetSystemControlAutoReturnTimer();
          }
        },
        child: Container(
          color: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(volumeIcon, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      '音量',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 150),
                    transitionBuilder: _buildFadeSettleTransition,
                    child: Text(
                      '$volumePercent%',
                      key: ValueKey(volumePercent),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  // 静音/取消静音
                  _miniBtn(
                    isMuted ? '🔇' : '🔈',
                    isMuted
                        ? IslandConfig.dangerColor.withValues(alpha: 0.3)
                        : Colors.white.withValues(alpha: 0.1),
                    () {
                      if (isMuted) {
                        SystemControlService.setVolume(_savedVolumeBeforeMute);
                      } else {
                        _savedVolumeBeforeMute = currentVolume;
                        SystemControlService.setVolume(0);
                      }
                      _mutateState(() {});
                      _resetSystemControlAutoReturnTimer();
                    },
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 4,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 7,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 14,
                        ),
                        activeTrackColor: IslandConfig.focusColor,
                        inactiveTrackColor: Colors.white.withValues(
                          alpha: 0.15,
                        ),
                        thumbColor: Colors.white,
                        overlayColor: IslandConfig.focusColor.withValues(
                          alpha: 0.2,
                        ),
                      ),
                      child: Slider(
                        value: currentVolume,
                        onChanged: (value) {
                          SystemControlService.setVolume(value);
                          _mutateState(() {});
                          _resetSystemControlAutoReturnTimer();
                        },
                        onChangeEnd: (value) {
                          SystemControlService.commitVolume(value);
                          _mutateState(() {});
                        },
                      ),
                    ),
                  ),
                  // 最大音量
                  _miniBtn('🔊', Colors.white.withValues(alpha: 0.1), () {
                    SystemControlService.setVolume(1.0);
                    _mutateState(() {});
                    _resetSystemControlAutoReturnTimer();
                  }),
                ],
              ),
              // 快捷音量档位
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [0, 25, 50, 75, 100].map((level) {
                  final isActive = (volumePercent - level).abs() < 13;
                  return GestureDetector(
                    onTap: () {
                      SystemControlService.setVolume(level / 100.0);
                      _mutateState(() {});
                      _resetSystemControlAutoReturnTimer();
                    },
                    child: Container(
                      width: 40,
                      height: 24,
                      decoration: BoxDecoration(
                        color: isActive
                            ? IslandConfig.focusColor.withValues(alpha: 0.3)
                            : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isActive
                              ? IslandConfig.focusColor.withValues(alpha: 0.5)
                              : Colors.white.withValues(alpha: 0.1),
                          width: 0.5,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$level',
                        style: TextStyle(
                          color: isActive ? Colors.white : Colors.white54,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 亮度控制 ─────────────────────────────────────────────────────────

  Widget _buildBrightnessControl() {
    final currentBrightness = SystemControlService.getBrightness();
    final brightnessPercent = (currentBrightness * 100).round();

    String brightnessIcon;
    if (brightnessPercent < 20) {
      brightnessIcon = '🌙';
    } else if (brightnessPercent < 60) {
      brightnessIcon = '⛅';
    } else {
      brightnessIcon = '☀️';
    }

    return GestureDetector(
      key: const ValueKey('brightnessControl'),
      onTap: () {
        _systemControlAutoReturnTimer?.cancel();
        _stack.pop(IslandState.brightnessControl);
        _stack.push(IslandState.quickControls, data: _currentPayload);
        _animateToState(IslandState.quickControls);
        _startQuickControlsAutoReturnTimer();
      },
      onPanStart: (_) => _startDrag(),
      child: Listener(
        onPointerSignal: (pointerSignal) {
          if (pointerSignal is PointerScrollEvent) {
            final delta = pointerSignal.scrollDelta.dy;
            final current = SystemControlService.getBrightness();
            final newBri = (current - delta * 0.003).clamp(0.0, 1.0);
            SystemControlService.setBrightness(newBri);
            _mutateState(() {});
            _resetSystemControlAutoReturnTimer();
          }
        },
        child: Container(
          color: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(brightnessIcon, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      '亮度',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 150),
                    transitionBuilder: _buildFadeSettleTransition,
                    child: Text(
                      '$brightnessPercent%',
                      key: ValueKey(brightnessPercent),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  // 最低亮度
                  _miniBtn('🌙', Colors.white.withValues(alpha: 0.1), () {
                    SystemControlService.setBrightness(0.05);
                    _mutateState(() {});
                    _resetSystemControlAutoReturnTimer();
                  }),
                  Expanded(
                    child: SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 4,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 7,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 14,
                        ),
                        activeTrackColor: IslandConfig.warningColor,
                        inactiveTrackColor: Colors.white.withValues(
                          alpha: 0.15,
                        ),
                        thumbColor: Colors.white,
                        overlayColor: IslandConfig.warningColor.withValues(
                          alpha: 0.2,
                        ),
                      ),
                      child: Slider(
                        value: currentBrightness,
                        onChanged: (value) {
                          SystemControlService.setBrightness(value);
                          _mutateState(() {});
                          _resetSystemControlAutoReturnTimer();
                        },
                      ),
                    ),
                  ),
                  // 最高亮度
                  _miniBtn('☀️', Colors.white.withValues(alpha: 0.1), () {
                    SystemControlService.setBrightness(1.0);
                    _mutateState(() {});
                    _resetSystemControlAutoReturnTimer();
                  }),
                ],
              ),
              // 快捷亮度档位
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [5, 25, 50, 75, 100].map((level) {
                  final isActive = (brightnessPercent - level).abs() < 13;
                  return GestureDetector(
                    onTap: () {
                      SystemControlService.setBrightness(level / 100.0);
                      _mutateState(() {});
                      _resetSystemControlAutoReturnTimer();
                    },
                    child: Container(
                      width: 40,
                      height: 24,
                      decoration: BoxDecoration(
                        color: isActive
                            ? IslandConfig.warningColor.withValues(alpha: 0.3)
                            : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isActive
                              ? IslandConfig.warningColor.withValues(alpha: 0.5)
                              : Colors.white.withValues(alpha: 0.1),
                          width: 0.5,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$level',
                        style: TextStyle(
                          color: isActive ? Colors.white : Colors.white54,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
