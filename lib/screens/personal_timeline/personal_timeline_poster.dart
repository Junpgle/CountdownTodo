part of '../personal_timeline_screen.dart';

extension _PersonalTimelinePosterExt on _PersonalTimelineScreenState {
  Future<void> _chooseAndExportTimelinePoster() async {
    if (_summary == null || _isExportingPoster) return;

    final choice =
        await showAppModalBottomSheet<
          ({
            TimelineDimension dimension,
            DateTime date,
            bool includeMedals,
            _TimelinePosterAction action,
          })
        >(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (context) {
            final cs = Theme.of(context).colorScheme;
            var selectedDimension = _dimension;
            var selectedDate = _selectedDate;
            var includeMedals = true;
            var action = _TimelinePosterAction.save;

            return StatefulBuilder(
              builder: (context, setModalState) {
                Future<void> pickPeriod() async {
                  final picked = await showAppDatePicker(
                    context: context,
                    initialDate: selectedDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                    helpText:
                        '选择${_getDimensionFullName(selectedDimension)}报告时段',
                  );
                  if (picked != null) {
                    setModalState(() => selectedDate = picked);
                  }
                }

                return SafeArea(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      20,
                      8,
                      20,
                      20 + MediaQuery.viewInsetsOf(context).bottom,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '导出报告长图',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildPosterChoiceSection(
                          '报告维度',
                          Icons.tune_rounded,
                          cs,
                          SegmentedButton<TimelineDimension>(
                            showSelectedIcon: false,
                            segments: TimelineDimension.values
                                .map(
                                  (d) => ButtonSegment(
                                    value: d,
                                    label: Text(_getDimensionName(d)),
                                  ),
                                )
                                .toList(),
                            selected: {selectedDimension},
                            onSelectionChanged: (value) {
                              setModalState(() {
                                selectedDimension = value.first;
                              });
                            },
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildPosterChoiceSection(
                          '具体时段',
                          Icons.event_rounded,
                          cs,
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest.withValues(
                                alpha: 0.42,
                              ),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Row(
                              children: [
                                IconButton.filledTonal(
                                  tooltip: '上一个时段',
                                  onPressed: () => setModalState(() {
                                    selectedDate = _shiftTimelineDate(
                                      selectedDate,
                                      selectedDimension,
                                      -1,
                                    );
                                  }),
                                  icon: const Icon(Icons.chevron_left_rounded),
                                ),
                                Expanded(
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(14),
                                    onTap: pickPeriod,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 10,
                                      ),
                                      child: Column(
                                        children: [
                                          Text(
                                            _formatTimelinePeriod(
                                              selectedDimension,
                                              selectedDate,
                                            ),
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w800,
                                              color: cs.onSurface,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '点击选择',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: cs.onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                IconButton.filledTonal(
                                  tooltip: '下一个时段',
                                  onPressed: () => setModalState(() {
                                    selectedDate = _shiftTimelineDate(
                                      selectedDate,
                                      selectedDimension,
                                      1,
                                    );
                                  }),
                                  icon: const Icon(Icons.chevron_right_rounded),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildPosterChoiceSection(
                          '勋章墙',
                          Icons.emoji_events_outlined,
                          cs,
                          SegmentedButton<bool>(
                            showSelectedIcon: false,
                            segments: const [
                              ButtonSegment(value: true, label: Text('带上')),
                              ButtonSegment(value: false, label: Text('不带')),
                            ],
                            selected: {includeMedals},
                            onSelectionChanged: (value) {
                              setModalState(() => includeMedals = value.first);
                            },
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildPosterChoiceSection(
                          '导出方式',
                          Icons.outbox_rounded,
                          cs,
                          SegmentedButton<_TimelinePosterAction>(
                            showSelectedIcon: false,
                            segments: const [
                              ButtonSegment(
                                value: _TimelinePosterAction.save,
                                icon: Icon(Icons.photo_library_outlined),
                                label: Text('保存到相册'),
                              ),
                              ButtonSegment(
                                value: _TimelinePosterAction.share,
                                icon: Icon(Icons.ios_share_rounded),
                                label: Text('分享'),
                              ),
                            ],
                            selected: {action},
                            onSelectionChanged: (value) {
                              setModalState(() => action = value.first);
                            },
                          ),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () => Navigator.pop(context, (
                              dimension: selectedDimension,
                              date: selectedDate,
                              includeMedals: includeMedals,
                              action: action,
                            )),
                            icon: Icon(
                              action == _TimelinePosterAction.save
                                  ? Icons.photo_library_outlined
                                  : Icons.ios_share_rounded,
                            ),
                            label: Text(
                              action == _TimelinePosterAction.save
                                  ? '保存到相册'
                                  : '打开分享面板',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );

    if (choice == null) return;
    if (choice.dimension != _dimension ||
        !_isSameTimelinePeriod(choice.dimension, choice.date, _selectedDate)) {
      _mutateState(() {
        _dimension = choice.dimension;
        _selectedDate = choice.date;
      });
      await _loadData();
    }
    await _saveTimelinePoster(
      includeMedals: choice.includeMedals,
      action: choice.action,
    );
  }

  Widget _buildPosterChoiceSection(
    String title,
    IconData icon,
    ColorScheme cs,
    Widget child,
  ) {
    return OptionalLiquidGlassCard(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      borderRadius: 20,
      fallbackDecoration: BoxDecoration(
        color: cs.surfaceContainer.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  String _getDimensionFullName(TimelineDimension dimension) {
    switch (dimension) {
      case TimelineDimension.daily:
        return '日';
      case TimelineDimension.weekly:
        return '周';
      case TimelineDimension.monthly:
        return '月';
      case TimelineDimension.yearly:
        return '年';
    }
  }

  DateTime _shiftTimelineDate(
    DateTime date,
    TimelineDimension dimension,
    int direction,
  ) {
    switch (dimension) {
      case TimelineDimension.daily:
        return AppTimeFormats.localDayStartOffset(date, direction);
      case TimelineDimension.weekly:
        return AppTimeFormats.localDayStartOffset(date, direction * 7);
      case TimelineDimension.monthly:
        return DateTime(date.year, date.month + direction, 1);
      case TimelineDimension.yearly:
        return DateTime(date.year + direction, 1, 1);
    }
  }

  String _formatTimelinePeriod(TimelineDimension dimension, DateTime date) {
    final day = CalendarDateMath.dateOnly(date);
    switch (dimension) {
      case TimelineDimension.daily:
        return AppTimeFormats.dateFormatter('yyyy年MM月dd日').format(day);
      case TimelineDimension.weekly:
        final start = AppTimeFormats.localDayStartOffset(
          day,
          -(day.weekday - 1),
        );
        final end = AppTimeFormats.localDayStartOffset(start, 6);
        return '${AppTimeFormats.dateFormatter('MM/dd').format(start)} - ${AppTimeFormats.dateFormatter('MM/dd').format(end)}';
      case TimelineDimension.monthly:
        return AppTimeFormats.dateFormatter('yyyy年MM月').format(day);
      case TimelineDimension.yearly:
        return '${day.year}年';
    }
  }

  bool _isSameTimelinePeriod(
    TimelineDimension dimension,
    DateTime a,
    DateTime b,
  ) {
    switch (dimension) {
      case TimelineDimension.daily:
        return AppTimeFormats.isSameDay(a, b);
      case TimelineDimension.weekly:
        final aStart = AppTimeFormats.localDayStartOffset(
          AppTimeFormats.dayStart(a),
          -(a.weekday - 1),
        );
        final bStart = AppTimeFormats.localDayStartOffset(
          AppTimeFormats.dayStart(b),
          -(b.weekday - 1),
        );
        return AppTimeFormats.isSameDay(aStart, bStart);
      case TimelineDimension.monthly:
        return a.year == b.year && a.month == b.month;
      case TimelineDimension.yearly:
        return a.year == b.year;
    }
  }

  Future<void> _saveTimelinePoster({
    required bool includeMedals,
    required _TimelinePosterAction action,
  }) async {
    if (_summary == null || _isExportingPoster) return;

    _mutateState(() => _isExportingPoster = true);
    final messenger = ScaffoldMessenger.of(context);
    final posterKey = GlobalKey();
    OverlayEntry? entry;

    try {
      final overlay = Overlay.of(context);
      final theme = Theme.of(context);
      final cs = theme.colorScheme;

      entry = OverlayEntry(
        builder: (_) => Positioned(
          left: 0,
          top: 0,
          child: IgnorePointer(
            child: Opacity(
              opacity: 0.01,
              child: Material(
                color: Colors.transparent,
                child: RepaintBoundary(
                  key: posterKey,
                  child: Theme(
                    data: theme,
                    child: MediaQuery(
                      data: const MediaQueryData(
                        size: Size(1080, 1920),
                        devicePixelRatio: 1,
                        textScaler: TextScaler.noScaling,
                      ),
                      child: _buildSharePoster(
                        cs,
                        includeMedals: includeMedals,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      overlay.insert(entry);
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 80));

      final boundary =
          posterKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) {
        throw StateError('分享长图渲染失败');
      }

      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) {
        throw StateError('PNG 编码失败');
      }

      final safePeriod = _getPeriodName();
      final timestamp = AppTimeFormats.dateFormatter('yyyyMMdd_HHmmss')
          .format(DateTime.now());
      final fileName = 'CountDownTodo_${safePeriod}_timeline_$timestamp.png';
      final pngBytes = bytes.buffer.asUint8List();
      final filePath = await BrowserFileService.saveBytesFile(
        pngBytes,
        fileName,
        mimeType: 'image/png',
      );

      if (!mounted) return;
      if (action == _TimelinePosterAction.share) {
        try {
          await BrowserFileService.shareBytesFile(
            pngBytes,
            fileName,
            mimeType: 'image/png',
            text: 'CountDownTodo ${_getPeriodName()} 总结',
          );
        } catch (e) {
          AppSnackBars.showSnackBarFromMessenger(
            messenger,
            SnackBar(content: Text('打开分享失败：$e')),
          );
        }
        AppSnackBars.showSnackBarFromMessenger(
          messenger,
          SnackBar(content: Text('长图已保存，可从本地文件继续使用：$filePath')),
        );
      }

      if (action == _TimelinePosterAction.save) {
        if (!kIsWeb && AppPlatform.isAndroid) {
          await _nativeChannel.invokeMethod('saveImageToGallery', {
            'path': filePath,
          });
        }
        AppSnackBars.showSnackBarFromMessenger(
          messenger,
          SnackBar(
            content: Text(
              !kIsWeb && AppPlatform.isAndroid ? '长图已保存到相册' : '长图已保存：$filePath',
            ),
            action: !kIsWeb
                ? SnackBarAction(
                    label: '打开',
                    onPressed: () => FileOpenService.open(filePath),
                  )
                : null,
          ),
        );
      }
    } catch (e) {
      // debugPrint('保存时间线长图失败: $e');
      if (mounted) {
        AppSnackBars.showSnackBarFromMessenger(
          messenger,
          SnackBar(content: Text('保存长图失败：$e')),
        );
      }
    } finally {
      entry?.remove();
      if (mounted) _mutateState(() => _isExportingPoster = false);
    }
  }

  Widget _buildSharePoster(ColorScheme cs, {required bool includeMedals}) {
    return Container(
      width: 1080,
      color: cs.surface,
      padding: const EdgeInsets.fromLTRB(56, 56, 56, 64),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CountDownTodo ${_getPeriodName()}总结',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: cs.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _getDateRangeString(),
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w900,
                        color: cs.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                AppTimeFormats.dateFormatter('yyyy.MM.dd HH:mm')
                    .format(DateTime.now()),
                style: TextStyle(
                  fontSize: 15,
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          _buildStatsOverview(cs, true),
          const SizedBox(height: 36),
          _buildSectionTitle('概览回顾', Icons.insights_rounded, cs),
          const SizedBox(height: 16),
          _buildRangeSummary(cs, true),
          _buildOverviewInsightPanels(cs, true),
          if (includeMedals) _buildMedalWall(cs, true),
          const SizedBox(height: 36),
          _buildSectionTitle('数据深度洞察', Icons.analytics_outlined, cs),
          const SizedBox(height: 16),
          _buildSubjectDonutChart(cs),
          const SizedBox(height: 36),
          _buildReflection(cs),
          const SizedBox(height: 28),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  '由 CountDownTodo 生成',
                  style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.62),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _buildWebsiteQr(cs),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWebsiteQr(ColorScheme cs) {
    const siteUrl = 'https://countdowntodo.junpgle.me/';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '扫码访问',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade800,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                siteUrl,
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          QrImageView(
            data: siteUrl,
            version: QrVersions.auto,
            size: 96,
            gapless: false,
            backgroundColor: Colors.white,
            eyeStyle: const QrEyeStyle(
              eyeShape: QrEyeShape.square,
              color: Colors.black,
            ),
            dataModuleStyle: const QrDataModuleStyle(
              dataModuleShape: QrDataModuleShape.square,
              color: Colors.black,
            ),
          ),
        ],
      ),
    );
  }
}
