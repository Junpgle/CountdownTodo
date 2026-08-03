import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';

import '../../../services/browser_file_service.dart';
import '../models/thirty_day_challenge.dart';
import '../repositories/thirty_day_challenge_repository.dart';

class ThirtyDayChallengeScreen extends StatefulWidget {
  const ThirtyDayChallengeScreen({super.key});

  @override
  State<ThirtyDayChallengeScreen> createState() =>
      _ThirtyDayChallengeScreenState();
}

class _ThirtyDayChallengeScreenState extends State<ThirtyDayChallengeScreen>
    with SingleTickerProviderStateMixin {
  final _pageController = PageController(viewportFraction: 0.88);
  late final AnimationController _entranceController;
  late final Animation<double> _entranceAnimation;

  ThirtyDayChallengeState? _state;
  int _currentIndex = 0;
  bool _isShuffling = false;
  bool _isExportingReport = false;
  bool _showWelcome = false;
  bool _showOverview = false;
  bool _isPaused = false;
  int? _imageTaskId;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _entranceAnimation = CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOutCubic,
    );
    _load();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final state = await ThirtyDayChallengeRepository.load();
    final introSeen = await ThirtyDayChallengeRepository.hasSeenIntro();
    final isPaused = await ThirtyDayChallengeRepository.isPaused();
    if (!mounted) return;
    setState(() {
      _state = state;
      _showWelcome = !introSeen;
      _isPaused = isPaused;
    });
    _entranceController.forward();
  }

  Future<void> _enterChallenge() async {
    final shouldStart = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final scheme = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          icon: Icon(Icons.cloud_off_rounded, color: scheme.primary),
          title: const Text('本活动仅保存在当前设备'),
          content: const Text(
            '“30天找到全新自我”目前不支持跨端同步。完成状态、任务调整、感受和图片记录只会保存在当前设备。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('暂不开始'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('知道了，开始挑战'),
            ),
          ],
        );
      },
    );
    if (shouldStart != true || !mounted) return;

    try {
      await ThirtyDayChallengeRepository.markIntroSeen();
      if (!mounted) return;
      setState(() {
        _showWelcome = false;
        _isPaused = false;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('欢迎页保存失败，请稍后再试')),
      );
    }
  }

  Future<void> _deferChallenge() async {
    final didPop = await Navigator.of(context).maybePop();
    if (!didPop && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('可以稍后从帮助与反馈再次进入挑战')),
      );
    }
  }

  Future<void> _toggleChallengePause() async {
    if (_isShuffling) return;
    final nextPaused = !_isPaused;
    try {
      await ThirtyDayChallengeRepository.setPaused(nextPaused);
      if (!mounted) return;
      setState(() => _isPaused = nextPaused);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nextPaused ? '已暂停首页活动 Banner，记录仍然保留' : '已恢复参与，首页 Banner 已显示',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('操作失败，请稍后再试')),
      );
    }
  }

  Future<void> _abandonChallenge() async {
    if (_isShuffling) return;

    final shouldAbandon = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final scheme = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          icon: Icon(Icons.delete_sweep_rounded, color: scheme.error),
          title: const Text('放弃这次挑战？'),
          content: const Text(
            '放弃后会清空 30 项任务的完成状态、任务调整、感受和图片记录，之后可以重新开始。此操作无法恢复。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('继续挑战'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('放弃并清空'),
            ),
          ],
        );
      },
    );
    if (shouldAbandon != true) return;

    try {
      await ThirtyDayChallengeRepository.abandonChallenge();
      if (!mounted) return;
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      } else {
        setState(() {
          _state = ThirtyDayChallengeState.initial();
          _showWelcome = true;
          _isPaused = false;
          _currentIndex = 0;
        });
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('放弃失败，请稍后再试')),
      );
    }
  }

  Future<void> _resetProgress() async {
    final state = _state;
    if (state == null || _isShuffling) return;

    final shouldReset = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.restart_alt_rounded),
        title: const Text('重置全部打卡状态？'),
        content: const Text(
          '这会清除 30 项任务的完成标记和完成时间，但会保留你调整过的任务、感受和图片记录。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('重置状态'),
          ),
        ],
      ),
    );
    if (shouldReset != true || !mounted) return;

    try {
      await ThirtyDayChallengeRepository.resetProgress(state);
      if (!mounted) return;
      setState(() => _currentIndex = 0);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pageController.hasClients) {
          _pageController.jumpToPage(0);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已重置全部打卡状态，记录内容仍然保留')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('重置失败，请稍后再试')),
      );
    }
  }

  Future<void> _shareChallengeReport(ThirtyDayChallengeState state) async {
    if (_isExportingReport) return;

    setState(() => _isExportingReport = true);
    final messenger = ScaffoldMessenger.of(context);
    final posterKey = GlobalKey();
    OverlayEntry? entry;

    try {
      final overlay = Overlay.of(context);
      final theme = Theme.of(context);
      final colorScheme = theme.colorScheme;
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
                      child: _buildChallengeReportPoster(
                        state,
                        colorScheme,
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
      await Future<void>.delayed(const Duration(milliseconds: 120));

      final boundary = posterKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        throw StateError('报告长图渲染失败');
      }

      final image = await boundary.toImage(pixelRatio: 1.5);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (byteData == null) {
        throw StateError('报告长图编码失败');
      }

      final pngBytes = byteData.buffer.asUint8List();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final fileName = 'CountDownTodo_30天找到全新自我_$timestamp.png';
      if (!kIsWeb) {
        await BrowserFileService.saveBytesFile(
          pngBytes,
          fileName,
          mimeType: 'image/png',
        );
      }
      await BrowserFileService.shareBytesFile(
        pngBytes,
        fileName,
        mimeType: 'image/png',
        text: '我的 30 天找到全新自我报告\n#30天找到全新自我 #生活实验 #CountDownTodo',
      );

      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            kIsWeb ? '报告长图已下载' : '报告长图已生成，已打开分享面板',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('报告长图生成失败：$error')),
      );
    } finally {
      entry?.remove();
      if (mounted) setState(() => _isExportingReport = false);
    }
  }

  Future<void> _setCompleted(int taskId, bool completed) async {
    final state = _state;
    if (state == null) return;

    try {
      await ThirtyDayChallengeRepository.setCompleted(
        state,
        taskId,
        completed,
      );
      if (!mounted) return;
      setState(() {});
      if (completed) {
        final message = state.isCompleted
            ? '30 项挑战全部完成了，恭喜你遇见新的自己！'
            : '已完成 ${state.completedCount}/30，继续感受生活吧';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('保存失败，请稍后再试')),
      );
    }
  }

  Future<void> _saveFeeling(int taskId, String feeling) async {
    final state = _state;
    if (state == null) return;

    try {
      await ThirtyDayChallengeRepository.updateTask(
        state,
        taskId,
        feeling: feeling,
      );
      if (mounted) setState(() {});
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('感受保存失败，请稍后再试')),
      );
    }
  }

  Future<void> _pickTaskImage(ThirtyDayChallengeTask task) async {
    if (_imageTaskId != null) return;
    final state = _state;
    if (state == null) return;

    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;

    setState(() => _imageTaskId = task.id);
    try {
      final originalBytes = await picked.readAsBytes();
      if (originalBytes.isEmpty) throw Exception('empty image');

      Uint8List compressedBytes;
      try {
        compressedBytes = await FlutterImageCompress.compressWithList(
          originalBytes,
          minWidth: 1200,
          minHeight: 1200,
          quality: 74,
          format: CompressFormat.jpeg,
        );
      } catch (_) {
        // 某些桌面平台可能没有压缩插件实现；ImagePicker 的质量和尺寸参数
        // 仍然会先做一次压缩，此处保留可用图片作为降级路径。
        compressedBytes = originalBytes;
      }

      await ThirtyDayChallengeRepository.updateTask(
        state,
        task.id,
        imageBase64: base64Encode(compressedBytes),
      );
      if (mounted) setState(() {});
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('图片保存失败，请重新选择')),
      );
    } finally {
      if (mounted) setState(() => _imageTaskId = null);
    }
  }

  Future<void> _editTask(ThirtyDayChallengeTask task) async {
    final editedTitle = await showDialog<String>(
      context: context,
      builder: (_) => _ChallengeTaskEditDialog(
        task: task,
      ),
    );

    if (editedTitle == null || !mounted) return;
    await ThirtyDayChallengeRepository.updateTask(
      _state!,
      task.id,
      customTitle: editedTitle,
    );
    if (mounted) setState(() {});
  }

  Future<void> _showRandomTask() async {
    final state = _state;
    if (state == null) return;

    final task = state.randomUnfinishedTask();
    if (task == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('所有任务都完成了，去回味一下你的记录吧')),
      );
      return;
    }

    if (!mounted) return;
    setState(() => _isShuffling = true);
  }

  Future<void> _finishShuffle(ThirtyDayChallengeTask task) async {
    final state = _state;
    if (state == null || !mounted) return;
    final taskIndex = state.tasks.indexOf(task);
    if (taskIndex < 0) return;

    setState(() {
      _isShuffling = false;
      _currentIndex = taskIndex;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageController.hasClients) return;
      _pageController.jumpToPage(taskIndex);
    });
  }

  Future<void> _goToPage(int offset) async {
    final state = _state;
    if (state == null || state.tasks.isEmpty) return;
    final nextIndex =
        (_currentIndex + offset).clamp(0, state.tasks.length - 1).toInt();
    if (nextIndex == _currentIndex) return;
    await _pageController.animateToPage(
      nextIndex,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    final isCompactMobile = MediaQuery.sizeOf(context).width < 600;
    return Scaffold(
      appBar: _showWelcome
          ? null
          : AppBar(
              title: Text(
                '30天找到全新自我',
                style: isCompactMobile
                    ? Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontSize: 18)
                    : null,
              ),
            ),
      body: state == null
          ? const Center(child: CircularProgressIndicator())
          : FadeTransition(
              opacity: _entranceAnimation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.035),
                  end: Offset.zero,
                ).animate(_entranceAnimation),
                child: _showWelcome ? _buildWelcomeBody() : _buildBody(state),
              ),
            ),
    );
  }

  Widget _buildWelcomeBody() {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isLandscape = constraints.maxWidth > constraints.maxHeight &&
              constraints.maxHeight > 0;
          final isCompactMobile = !isLandscape && constraints.maxWidth < 600;
          final titleStyle = Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontSize: isCompactMobile ? 26 : null,
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w900,
                    height: 1.15,
                    letterSpacing: -1,
                  ) ??
              TextStyle(
                color: scheme.onSurface,
                fontWeight: FontWeight.w900,
                height: 1.15,
                letterSpacing: -1,
              );
          final welcomePrimary = scheme.primary;
          final welcomeSecondary = scheme.secondary;
          final welcomeTertiary = scheme.tertiary;
          if (isCompactMobile) {
            return _buildCompactWelcomeBody(
              scheme: scheme,
              welcomePrimary: welcomePrimary,
              welcomeSecondary: welcomeSecondary,
              welcomeTertiary: welcomeTertiary,
              availableHeight: constraints.maxHeight,
            );
          }
          return DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surface,
            ),
            child: Stack(
              children: [
                // Background blurred blobs
                Positioned(
                  top: -100,
                  left: -50,
                  child: Container(
                    width: 300,
                    height: 300,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: welcomePrimary.withValues(alpha: 0.15),
                    ),
                  ),
                ),
                Positioned(
                  bottom: -50,
                  right: -50,
                  child: Container(
                    width: 250,
                    height: 250,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: welcomeTertiary.withValues(alpha: 0.15),
                    ),
                  ),
                ),
                Positioned(
                  top: 96,
                  right: -34,
                  child: Container(
                    width: 132,
                    height: 132,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: welcomeSecondary.withValues(alpha: 0.15),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 60, sigmaY: 60),
                    child: const SizedBox(),
                  ),
                ),
                // Content
                SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    isLandscape ? 48 : 24,
                    isLandscape ? 32 : 48,
                    isLandscape ? 48 : 24,
                    isLandscape ? 40 : 64,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: isLandscape ? 1000 : 680,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(99),
                                border: Border.all(
                                  color: scheme.outlineVariant
                                      .withValues(alpha: 0.5),
                                ),
                              ),
                              child: Text(
                                'A LITTLE LIFE EXPERIMENT',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelMedium
                                    ?.copyWith(
                                      color: welcomePrimary,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.5,
                                    ),
                              ),
                            ),
                          ),
                          SizedBox(height: isLandscape ? 30 : 40),
                          Center(
                            child: Container(
                              width: isLandscape ? 100 : 120,
                              height: isLandscape ? 100 : 120,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [scheme.primary, scheme.tertiary],
                                ),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color:
                                      scheme.onSurface.withValues(alpha: 0.14),
                                  width: 6,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color:
                                        welcomePrimary.withValues(alpha: 0.42),
                                    blurRadius: 32,
                                    offset: const Offset(0, 16),
                                  ),
                                  BoxShadow(
                                    color:
                                        scheme.tertiary.withValues(alpha: 0.18),
                                    blurRadius: 8,
                                    spreadRadius: 4,
                                  ),
                                ],
                              ),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Icon(
                                    Icons.auto_awesome_rounded,
                                    size: isLandscape ? 50 : 60,
                                    color: scheme.onPrimary,
                                  ),
                                  Positioned(
                                    right: isLandscape ? 10 : 12,
                                    top: isLandscape ? 10 : 12,
                                    child: Icon(
                                      Icons.star_rounded,
                                      size: isLandscape ? 16 : 20,
                                      color: scheme.onPrimary.withValues(
                                        alpha: 0.75,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),
                          Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(text: '欢迎来到\n', style: titleStyle),
                                TextSpan(text: '30天找到', style: titleStyle),
                                TextSpan(
                                  text: '全新自我',
                                  style: titleStyle.copyWith(
                                    color: welcomePrimary,
                                  ),
                                ),
                              ],
                            ),
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .displaySmall
                                ?.copyWith(
                                  fontSize: isCompactMobile ? 26 : null,
                                  color: scheme.onSurface,
                                  fontWeight: FontWeight.w900,
                                  height: 1.15,
                                  letterSpacing: -1,
                                ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '给平淡生活加一点新鲜感，重新找回生命的感受力。',
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                  fontSize: isCompactMobile ? 16 : null,
                                  color: scheme.onSurfaceVariant,
                                  height: 1.5,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          SizedBox(height: isLandscape ? 32 : 48),
                          Container(
                            padding: const EdgeInsets.all(28),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(32),
                              border: Border.all(
                                color: scheme.outlineVariant
                                    .withValues(alpha: 0.5),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: scheme.shadow.withValues(alpha: 0.05),
                                  blurRadius: 24,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 42,
                                      height: 42,
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            scheme.primary,
                                            scheme.tertiary,
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Icon(
                                        Icons.explore_rounded,
                                        color: scheme.onPrimary,
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Text(
                                      '从一个新鲜念头开始',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            color: welcomePrimary,
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                Text(
                                  '你有多久没尝试过做打破常规的事情了？\n'
                                  '每天两点一线的生活实在枯燥，休假的时间要么被工作填满，'
                                  '要么宅在家里玩手机，好久没做一些新奇的事情了。\n'
                                  '做新事情会减缓我们对时间流逝的主观感觉，并破坏根深蒂固的思维模式。',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyLarge
                                      ?.copyWith(
                                        color: scheme.onSurface,
                                        height: 1.8,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(28),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainer,
                              borderRadius: BorderRadius.circular(32),
                              border: Border.all(
                                color: scheme.outlineVariant
                                    .withValues(alpha: 0.5),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color:
                                        scheme.primary.withValues(alpha: 0.16),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.format_quote_rounded,
                                    color: scheme.primary,
                                    size: 30,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '一句话提醒',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelLarge
                                            ?.copyWith(
                                              color: scheme.primary,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: 0.5,
                                            ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        '“单调瓦解了时间，而新奇展开了时间。”\n——乔舒亚·福尔《与爱因斯坦月球漫步》',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              color: scheme.onPrimaryContainer,
                                              height: 1.6,
                                              fontWeight: FontWeight.w700,
                                              fontStyle: FontStyle.italic,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(28),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(32),
                              border: Border.all(
                                color: scheme.outlineVariant
                                    .withValues(alpha: 0.5),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.local_activity_rounded,
                                  color: scheme.secondary,
                                  size: 30,
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Text(
                                    '如果你也想在乏味的生活中来点不一样的调味剂，不妨看看这份火爆外网的自我挑战人生清单。\n'
                                    '📍 清单里有 30 件小事，顺序随意，你自己调整，也不需要连续 30 天打卡。空闲时间挑一件事去尝试就好。',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyLarge
                                        ?.copyWith(
                                          color: scheme.onSurface,
                                          height: 1.8,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: isLandscape ? 32 : 48),
                          FilledButton.icon(
                            onPressed: _enterChallenge,
                            icon: const Icon(Icons.bolt_rounded),
                            label: const Text('开始这场挑战'),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(64),
                              elevation: 6,
                              shadowColor:
                                  scheme.primary.withValues(alpha: 0.35),
                              textStyle: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: _deferChallenge,
                            icon: const Icon(Icons.schedule_outlined),
                            label: const Text('暂不参与'),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '记录感受和照片，让这段改变真正留下来。',
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                _buildWelcomeBackButton(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildCompactWelcomeBody({
    required ColorScheme scheme,
    required Color welcomePrimary,
    required Color welcomeSecondary,
    required Color welcomeTertiary,
    required double availableHeight,
  }) {
    final titleStyle = Theme.of(context).textTheme.displaySmall?.copyWith(
              fontSize: 24,
              color: scheme.onSurface,
              fontWeight: FontWeight.w900,
              height: 1.05,
              letterSpacing: -0.8,
            ) ??
        TextStyle(
          color: scheme.onSurface,
          fontSize: 24,
          fontWeight: FontWeight.w900,
          height: 1.05,
          letterSpacing: -0.8,
        );
    final minContentHeight =
        availableHeight.isFinite ? max(0.0, availableHeight - 24) : 0.0;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
      ),
      child: Stack(
        children: [
          Positioned(
            top: -80,
            left: -80,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: welcomePrimary.withValues(alpha: 0.15),
              ),
            ),
          ),
          Positioned(
            bottom: -90,
            right: -70,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: welcomeTertiary.withValues(alpha: 0.15),
              ),
            ),
          ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 48, sigmaY: 48),
              child: const SizedBox(),
            ),
          ),
          Positioned.fill(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 480,
                    minHeight: minContentHeight,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(99),
                            border: Border.all(
                              color:
                                  scheme.outlineVariant.withValues(alpha: 0.5),
                            ),
                          ),
                          child: Text(
                            'A LITTLE LIFE EXPERIMENT',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  fontSize: 10,
                                  color: welcomePrimary,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.2,
                                ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: Container(
                          width: 68,
                          height: 68,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [scheme.primary, scheme.tertiary],
                            ),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: scheme.onSurface.withValues(alpha: 0.14),
                              width: 4,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: welcomePrimary.withValues(alpha: 0.32),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Icon(
                                Icons.auto_awesome_rounded,
                                size: 34,
                                color: scheme.onPrimary,
                              ),
                              Positioned(
                                right: 8,
                                top: 8,
                                child: Icon(
                                  Icons.star_rounded,
                                  size: 12,
                                  color:
                                      scheme.onPrimary.withValues(alpha: 0.75),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: '欢迎来到\n', style: titleStyle),
                            TextSpan(text: '30天找到', style: titleStyle),
                            TextSpan(
                              text: '全新自我',
                              style: titleStyle.copyWith(color: welcomePrimary),
                            ),
                          ],
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '给平淡生活加一点新鲜感，重新找回生命的感受力。',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              fontSize: 14,
                              color: scheme.onSurfaceVariant,
                              height: 1.25,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: scheme.outlineVariant.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [scheme.primary, scheme.tertiary],
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.explore_rounded,
                                color: scheme.onPrimary,
                                size: 17,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '从一个新鲜念头开始',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(
                                          color: welcomePrimary,
                                          fontWeight: FontWeight.w800,
                                        ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '你有多久没尝试过做打破常规的事情了？\n'
                                    '每天两点一线的生活实在枯燥，休假的时间要么被工作填满，'
                                    '要么宅在家里玩手机，好久没做一些新奇的事情了。\n'
                                    '做新事情会减缓我们对时间流逝的主观感觉，并破坏根深蒂固的思维模式。',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: scheme.onSurface,
                                          fontSize: 12,
                                          height: 1.35,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildCompactWelcomeQuoteCard(
                        scheme: scheme,
                        welcomePrimary: welcomePrimary,
                        welcomeSecondary: welcomeSecondary,
                      ),
                      const SizedBox(height: 16),
                      _buildCompactWelcomeDescriptionCard(
                        scheme: scheme,
                        welcomeSecondary: welcomeSecondary,
                        welcomeTertiary: welcomeTertiary,
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: _enterChallenge,
                        icon: const Icon(Icons.bolt_rounded, size: 18),
                        label: const Text('开始这场挑战'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                          textStyle: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                      ),
                      const SizedBox(height: 0),
                      TextButton.icon(
                        onPressed: _deferChallenge,
                        icon: const Icon(Icons.schedule_outlined, size: 18),
                        label: const Text('暂不参与'),
                        style: TextButton.styleFrom(
                          minimumSize: const Size.fromHeight(40),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          textStyle: const TextStyle(fontSize: 13),
                        ),
                      ),
                      Text(
                        '记录感受和照片，让这段改变真正留下来。',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontSize: 12,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          _buildWelcomeBackButton(),
        ],
      ),
    );
  }

  Widget _buildWelcomeBackButton() {
    return Positioned(
      top: 2,
      left: 4,
      child: IconButton(
        tooltip: '返回',
        onPressed: () => Navigator.of(context).maybePop(),
        icon: const Icon(Icons.arrow_back_rounded),
      ),
    );
  }

  Widget _buildCompactWelcomeQuoteCard({
    required ColorScheme scheme,
    required Color welcomePrimary,
    required Color welcomeSecondary,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.format_quote_rounded,
              color: scheme.primary,
              size: 19,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '一句话提醒',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontSize: 10,
                        color: scheme.primary,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                      ),
                ),
                const SizedBox(height: 1),
                Text(
                  '“单调瓦解了时间，而新奇展开了时间。”\n——乔舒亚·福尔《与爱因斯坦月球漫步》',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        color: scheme.onPrimaryContainer,
                        height: 1.25,
                        fontWeight: FontWeight.w700,
                        fontStyle: FontStyle.italic,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactWelcomeDescriptionCard({
    required ColorScheme scheme,
    required Color welcomeSecondary,
    required Color welcomeTertiary,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.local_activity_rounded,
            color: scheme.secondary,
            size: 22,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '如果你也想在乏味的生活中来点不一样的调味剂，不妨看看这份火爆外网的自我挑战人生清单。\n'
              '📍 清单里有 30 件小事，顺序随意，你自己调整，也不需要连续 30 天打卡。空闲时间挑一件事去尝试就好。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    color: scheme.onSurface,
                    height: 1.35,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(ThirtyDayChallengeState state) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    return isLandscape ? _buildLandscapeBody(state) : _buildPortraitBody(state);
  }

  Widget _buildPortraitBody(ThirtyDayChallengeState state) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: _buildHeader(state, isLandscape: false),
        ),
        Expanded(
          child:
              _showOverview ? _buildGridOverview(state) : _buildCardArea(state),
        ),
        if (!_showOverview)
          _isShuffling ? _buildShuffleFooter() : _buildPager(state),
      ],
    );
  }

  Widget _buildLandscapeBody(ThirtyDayChallengeState state) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final sidebarWidth = min(400.0, max(300.0, screenWidth * 0.35));

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: sidebarWidth,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                child: _buildHeader(state, isLandscape: true),
              ),
              Expanded(
                child: _buildGridOverview(state, isLandscapeSidebar: true),
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(8, 12, 16, 16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(32),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(32),
              child: Column(
                children: [
                  Expanded(
                    child: _buildCardArea(state, isLandscapeDetail: true),
                  ),
                  _isShuffling ? _buildShuffleFooter() : _buildPager(state),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGridOverview(ThirtyDayChallengeState state,
      {bool isLandscapeSidebar = false}) {
    final scheme = Theme.of(context).colorScheme;
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        isLandscapeSidebar ? 8 : 16,
        16,
      ),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isLandscapeSidebar ? 4 : 5,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1,
      ),
      itemCount: state.tasks.length,
      itemBuilder: (context, index) {
        final task = state.tasks[index];
        final isSelected = _currentIndex == index;
        final hasImage =
            task.imageBase64 != null && task.imageBase64!.isNotEmpty;
        final taskColors = _challengeTaskGradientColors(task, scheme);
        final overviewColors = task.isCompleted
            ? [
                Color.alphaBlend(
                  scheme.primary.withValues(alpha: 0.12),
                  taskColors[0],
                ),
                Color.alphaBlend(
                  scheme.primary.withValues(alpha: 0.08),
                  taskColors[1],
                ),
                taskColors[2],
              ]
            : taskColors;

        return InkWell(
          onTap: () {
            setState(() {
              _currentIndex = index;
              if (!isLandscapeSidebar) {
                _showOverview = false;
              }
            });
            if (!isLandscapeSidebar) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _pageController.hasClients) {
                  _pageController.jumpToPage(index);
                }
              });
            } else {
              _pageController.animateToPage(
                index,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
              );
            }
          },
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: overviewColors,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected
                    ? taskColors.first
                    : task.isCompleted
                        ? taskColors[1].withValues(alpha: 0.62)
                        : taskColors.first.withValues(alpha: 0.32),
                width: isSelected ? 2 : 1,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: scheme.primary.withValues(alpha: 0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      )
                    ]
                  : null,
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (hasImage && task.isCompleted)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: Opacity(
                      opacity: 0.4,
                      child: Image.memory(
                        base64Decode(task.imageBase64!),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                Center(
                  child: task.isCompleted
                      ? Icon(
                          Icons.check_rounded,
                          color: isSelected ? scheme.primary : scheme.secondary,
                          size: 24,
                        )
                      : Text(
                          '${task.id}',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: scheme.onSurface,
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCardArea(ThirtyDayChallengeState state,
      {bool isLandscapeDetail = false}) {
    return _isShuffling
        ? _ShuffleCardStack(
            tasks: state.unfinishedTasks,
            onFinished: _finishShuffle,
          )
        : PageView.builder(
            controller: _pageController,
            itemCount: state.tasks.length,
            onPageChanged: (index) => setState(() => _currentIndex = index),
            itemBuilder: (context, index) {
              final task = state.tasks[index];
              return Padding(
                padding: EdgeInsets.symmetric(
                  vertical: isLandscapeDetail ? 24 : 12,
                  horizontal: isLandscapeDetail ? 8 : 4,
                ),
                child: _ChallengeTaskCard(
                  task: task,
                  onComplete: (completed) => _setCompleted(task.id, completed),
                  onSaveFeeling: (feeling) => _saveFeeling(task.id, feeling),
                  onEdit: () => _editTask(task),
                  isImageLoading: _imageTaskId == task.id,
                  onPickImage: () => _pickTaskImage(task),
                ),
              );
            },
          );
  }

  Widget _buildHeader(ThirtyDayChallengeState state,
      {bool isLandscape = false}) {
    final scheme = Theme.of(context).colorScheme;
    final isCompactMobile =
        !isLandscape && MediaQuery.sizeOf(context).width < 600;
    final headerColors = [
      _vividChallengeColor(scheme.primary, scheme, hueShift: 6),
      _vividChallengeColor(scheme.secondary, scheme, hueShift: -10),
      _vividChallengeColor(scheme.tertiary, scheme, hueShift: 8),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: headerColors,
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      state.isCompleted
                          ? '挑战完成！'
                          : _isPaused
                              ? '挑战已暂停'
                              : '今天想做点不一样的事',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontSize: isCompactMobile ? 17 : null,
                            fontWeight: FontWeight.w900,
                            color: scheme.onPrimaryContainer,
                            letterSpacing: -0.5,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _isPaused
                          ? '首页 Banner 已隐藏，记录仍然保留。'
                          : '左右滑动，找一件让生活重新有感觉的小事。',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontSize: isCompactMobile ? 12 : null,
                            color: scheme.onPrimaryContainer.withValues(
                              alpha: 0.8,
                            ),
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip:
                        state.isCompleted || _isShuffling ? '挑战已完成' : '随机一个任务',
                    onPressed: state.isCompleted || _isShuffling
                        ? null
                        : _showRandomTask,
                    icon: const Icon(Icons.shuffle_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor: scheme.surface.withValues(alpha: 0.35),
                      foregroundColor: scheme.onSurface,
                    ),
                  ),
                  if (!isLandscape) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: _showOverview ? '查看详情' : '网格总览',
                      onPressed: () {
                        setState(() {
                          _showOverview = !_showOverview;
                        });
                        if (!_showOverview) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted && _pageController.hasClients) {
                              _pageController.jumpToPage(_currentIndex);
                            }
                          });
                        }
                      },
                      icon: Icon(_showOverview
                          ? Icons.view_agenda_rounded
                          : Icons.grid_view_rounded),
                      style: IconButton.styleFrom(
                        backgroundColor: scheme.surface.withValues(alpha: 0.35),
                        foregroundColor: scheme.onSurface,
                      ),
                    ),
                  ],
                ],
              )
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: state.progress),
                  duration: const Duration(milliseconds: 850),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, _) => ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      minHeight: 12,
                      value: value,
                      backgroundColor: scheme.surface.withValues(alpha: 0.6),
                      valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, animation) => ScaleTransition(
                  scale: animation,
                  child: child,
                ),
                child: Text(
                  '${state.completedCount}/30',
                  key: ValueKey(state.completedCount),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: scheme.onPrimaryContainer,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                FilledButton.tonalIcon(
                  onPressed: _isExportingReport
                      ? null
                      : () => _shareChallengeReport(state),
                  icon: _isExportingReport
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.ios_share_rounded),
                  label: Text(_isExportingReport ? '生成中…' : '导出并分享'),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _isExportingReport || _isShuffling
                      ? null
                      : _resetProgress,
                  icon: const Icon(Icons.restart_alt_rounded),
                  label: const Text('重置状态'),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _isExportingReport || _isShuffling
                      ? null
                      : _toggleChallengePause,
                  icon: Icon(
                    _isPaused
                        ? Icons.play_circle_outline_rounded
                        : Icons.pause_circle_outline_rounded,
                  ),
                  label: Text(_isPaused ? '恢复参与' : '暂停挑战'),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _isExportingReport || _isShuffling
                      ? null
                      : _abandonChallenge,
                  icon: const Icon(Icons.delete_sweep_outlined),
                  label: const Text('放弃挑战'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPager(ThirtyDayChallengeState state) {
    final scheme = Theme.of(context).colorScheme;
    final currentTask = state.tasks[_currentIndex];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Row(
        children: [
          IconButton.filledTonal(
            tooltip: '上一项',
            onPressed: _currentIndex == 0 ? null : () => _goToPage(-1),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.25),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: Text(
                    '第 ${currentTask.id} 项 / ${state.tasks.length}',
                    key: ValueKey(currentTask.id),
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    minHeight: 6,
                    value: (currentTask.id) / state.tasks.length,
                    backgroundColor: scheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(scheme.tertiary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          IconButton.filledTonal(
            tooltip: '下一项',
            onPressed: _currentIndex == state.tasks.length - 1
                ? null
                : () => _goToPage(1),
            icon: const Icon(Icons.arrow_forward_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildShuffleFooter() {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: scheme.tertiary,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '正在从未完成的任务中洗牌…',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildChallengeReportPoster(
    ThirtyDayChallengeState state,
    ColorScheme scheme,
  ) {
    final feelingCount =
        state.tasks.where((task) => task.feeling.trim().isNotEmpty).length;
    final imageCount = state.tasks
        .where((task) => task.imageBase64?.isNotEmpty == true)
        .length;
    final generatedAt = DateFormat('yyyy年M月d日').format(DateTime.now());
    final startedAt = DateFormat('yyyy年M月d日').format(state.startedAt);

    return Container(
      width: 1080,
      color: scheme.surface,
      padding: const EdgeInsets.fromLTRB(56, 56, 56, 72),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(46, 42, 46, 42),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  scheme.primaryContainer,
                  scheme.secondaryContainer,
                  scheme.tertiaryContainer,
                ],
              ),
              borderRadius: BorderRadius.circular(36),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CountDownTodo · LIFE REPORT',
                  style: TextStyle(
                    color: scheme.onPrimaryContainer,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  '我的 30 天',
                  style: TextStyle(
                    color: scheme.onPrimaryContainer,
                    fontSize: 64,
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '重新找回生活中的兴奋感',
                  style: TextStyle(
                    color: scheme.onPrimaryContainer.withValues(alpha: 0.82),
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 32),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${state.completedCount}',
                      style: TextStyle(
                        color: scheme.onPrimaryContainer,
                        fontSize: 72,
                        fontWeight: FontWeight.w900,
                        height: 0.9,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 10, bottom: 5),
                      child: Text(
                        '/ ${state.tasks.length} 项完成',
                        style: TextStyle(
                          color: scheme.onPrimaryContainer.withValues(
                            alpha: 0.78,
                          ),
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    minHeight: 14,
                    value: state.progress,
                    backgroundColor: scheme.surface.withValues(alpha: 0.42),
                    valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  '开始于 $startedAt  ·  生成于 $generatedAt',
                  style: TextStyle(
                    color: scheme.onPrimaryContainer.withValues(alpha: 0.72),
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Text(
            '我为自己留下了',
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildReportMetric(
                scheme,
                value: '$feelingCount',
                label: '条感受',
                icon: Icons.format_quote_rounded,
              ),
              const SizedBox(width: 16),
              _buildReportMetric(
                scheme,
                value: '$imageCount',
                label: '张照片',
                icon: Icons.photo_library_outlined,
              ),
              const SizedBox(width: 16),
              _buildReportMetric(
                scheme,
                value: '${state.tasks.length}',
                label: '次尝试',
                icon: Icons.explore_outlined,
              ),
            ],
          ),
          const SizedBox(height: 40),
          Text(
            '30 项生活体验',
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 32,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 16),
          ...state.tasks.map(
            (task) => _buildChallengeReportTask(task, scheme),
          ),
          const SizedBox(height: 28),
          Center(
            child: Text(
              '单调瓦解了时间，而新奇展开了时间。',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 18),
          Center(
            child: Text(
              '把自己重新放回生活里 · CountDownTodo',
              style: TextStyle(
                color: scheme.primary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportMetric(
    ColorScheme scheme, {
    required String value,
    required String label,
    required IconData icon,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          children: [
            Icon(icon, color: scheme.primary, size: 30),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChallengeReportTask(
    ThirtyDayChallengeTask task,
    ColorScheme scheme,
  ) {
    final imageBytes = _decodeChallengeImage(task.imageBase64);
    final hasImage = imageBytes != null;
    final taskColors = _challengeTaskGradientColors(task, scheme);
    final cardColors = task.isCompleted
        ? [
            Color.alphaBlend(
              scheme.primary.withValues(alpha: 0.12),
              taskColors[0],
            ),
            Color.alphaBlend(
              scheme.primary.withValues(alpha: 0.08),
              taskColors[1],
            ),
            taskColors[2],
          ]
        : taskColors;
    final foreground = hasImage ? scheme.onInverseSurface : scheme.onSurface;
    final mutedForeground = hasImage
        ? scheme.onInverseSurface.withValues(alpha: 0.78)
        : scheme.onSurfaceVariant;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      constraints: const BoxConstraints(minHeight: 168),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: hasImage
              ? [
                  taskColors[0].withValues(alpha: 0.28),
                  taskColors[1].withValues(alpha: 0.16),
                  taskColors[2].withValues(alpha: 0.42),
                ]
              : cardColors,
        ),
        image: imageBytes == null
            ? null
            : DecorationImage(
                image: MemoryImage(imageBytes),
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
              ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: task.isCompleted
              ? (hasImage
                  ? scheme.onInverseSurface.withValues(alpha: 0.64)
                  : taskColors.first.withValues(alpha: 0.66))
              : taskColors.first.withValues(alpha: 0.42),
          width: task.isCompleted ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 28, 24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 58,
              height: 58,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: task.isCompleted
                    ? scheme.primary
                    : (hasImage
                        ? scheme.scrim.withValues(alpha: 0.48)
                        : scheme.secondaryContainer),
                shape: BoxShape.circle,
              ),
              child: task.isCompleted
                  ? Icon(Icons.check_rounded, color: scheme.onPrimary, size: 32)
                  : Text(
                      '${task.id}',
                      style: TextStyle(
                        color: hasImage
                            ? scheme.onInverseSurface
                            : scheme.onSecondaryContainer,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 27,
                      fontWeight: FontWeight.w900,
                      height: 1.25,
                      decoration:
                          task.isCompleted ? TextDecoration.lineThrough : null,
                      decorationColor: mutedForeground,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    task.isCompleted
                        ? '已完成 · ${_formatReportDate(task.completedAt)}'
                        : '还没有完成',
                    style: TextStyle(
                      color: mutedForeground,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (task.feeling.trim().isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
                      decoration: BoxDecoration(
                        color: hasImage
                            ? scheme.scrim.withValues(alpha: 0.42)
                            : scheme.surfaceContainerHighest.withValues(
                                alpha: 0.78,
                              ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.format_quote_rounded,
                            size: 22,
                            color: foreground,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              task.feeling,
                              style: TextStyle(
                                color: foreground,
                                fontSize: 19,
                                height: 1.45,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatReportDate(DateTime? date) {
    if (date == null) return '日期未知';
    return DateFormat('yyyy年M月d日').format(date);
  }
}

class _ChallengeTaskEditDialog extends StatefulWidget {
  final ThirtyDayChallengeTask task;

  const _ChallengeTaskEditDialog({required this.task});

  @override
  State<_ChallengeTaskEditDialog> createState() =>
      _ChallengeTaskEditDialogState();
}

class _ChallengeTaskEditDialogState extends State<_ChallengeTaskEditDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.task.title);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('调整第 ${widget.task.id} 项'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLines: 3,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          labelText: '任务内容',
          hintText: widget.task.originalTitle,
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(''),
          child: const Text('恢复原任务'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class _ShuffleCardStack extends StatefulWidget {
  final List<ThirtyDayChallengeTask> tasks;
  final Future<void> Function(ThirtyDayChallengeTask) onFinished;

  const _ShuffleCardStack({
    required this.tasks,
    required this.onFinished,
  });

  @override
  State<_ShuffleCardStack> createState() => _ShuffleCardStackState();
}

class _ShuffleCardStackState extends State<_ShuffleCardStack>
    with SingleTickerProviderStateMixin {
  late final List<ThirtyDayChallengeTask> _sequence;
  late final AnimationController _controller;
  late final Animation<int> _stepAnimation;
  bool _hasNotified = false;

  @override
  void initState() {
    super.initState();
    _sequence = _buildSequence(widget.tasks);
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1750),
    );
    _stepAnimation = IntTween(
      begin: 0,
      end: _sequence.length - 1,
    ).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic),
    );
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && !_hasNotified) {
        _hasNotified = true;
        unawaited(widget.onFinished(_sequence.last));
      }
    });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<ThirtyDayChallengeTask> _buildSequence(
    List<ThirtyDayChallengeTask> tasks,
  ) {
    final pool = List<ThirtyDayChallengeTask>.of(tasks);
    final random = Random();
    final previewCount = min(6, max(1, pool.length));
    final sequence = [
      for (var index = 0; index < previewCount; index++)
        pool[random.nextInt(pool.length)],
    ];
    var finalTask = pool[random.nextInt(pool.length)];
    if (pool.length > 1 && finalTask.id == sequence.last.id) {
      finalTask = pool.firstWhere((task) => task.id != sequence.last.id);
    }
    sequence.add(finalTask);
    return sequence;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = min(
          constraints.maxHeight.isFinite ? constraints.maxHeight : 520.0,
          560.0,
        );
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: SizedBox(
            height: height,
            width: double.infinity,
            child: AnimatedBuilder(
              animation: _stepAnimation,
              builder: (context, _) {
                final step = _stepAnimation.value;
                final current = _sequence[step];
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    for (var layer = 3; layer >= 1; layer--)
                      Positioned.fill(
                        child: Padding(
                          padding: EdgeInsets.only(
                            top: layer * 10,
                            left: layer * 4,
                            right: layer * 4,
                          ),
                          child: Transform.scale(
                            scale: 1 - layer * 0.035,
                            alignment: Alignment.topCenter,
                            child: _ShuffleCardSurface(
                              task:
                                  _sequence[(step + layer) % _sequence.length],
                              isFront: false,
                            ),
                          ),
                        ),
                      ),
                    Positioned.fill(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        switchInCurve: Curves.easeOutBack,
                        switchOutCurve: Curves.easeIn,
                        layoutBuilder: (currentChild, previousChildren) =>
                            Stack(
                          fit: StackFit.expand,
                          children: [
                            ...previousChildren,
                            if (currentChild != null) currentChild,
                          ],
                        ),
                        transitionBuilder: (child, animation) {
                          final slide = Tween<Offset>(
                            begin: const Offset(0, 0.8),
                            end: Offset.zero,
                          ).animate(animation);
                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: slide,
                              child: ScaleTransition(
                                scale: animation,
                                child: child,
                              ),
                            ),
                          );
                        },
                        child: _ShuffleCardSurface(
                          key: ValueKey('${current.id}-$step'),
                          task: current,
                          isFront: true,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _ShuffleCardSurface extends StatelessWidget {
  final ThirtyDayChallengeTask task;
  final bool isFront;

  const _ShuffleCardSurface({
    super.key,
    required this.task,
    required this.isFront,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isCompact =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final taskColors = _challengeTaskGradientColors(task, scheme);
    final cardTextColor =
        isFront ? scheme.onPrimaryContainer : scheme.onSurfaceVariant;
    final colors = isFront
        ? taskColors
        : [
            Color.alphaBlend(
              taskColors.first.withValues(alpha: 0.18),
              scheme.surface,
            ),
            Color.alphaBlend(
              taskColors[1].withValues(alpha: 0.12),
              scheme.surface,
            ),
          ];
    return Container(
      padding: EdgeInsets.all(isCompact ? 18 : 26),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: isFront
              ? taskColors.first.withValues(alpha: 0.62)
              : scheme.outlineVariant,
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: isFront ? 0.12 : 0.05),
            blurRadius: isFront ? 24 : 12,
            offset: Offset(0, isFront ? 10 : 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '第 ${task.id} 项',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: cardTextColor,
                      fontWeight: FontWeight.w800,
                    ),
              ),
              Icon(
                isFront ? Icons.auto_awesome_rounded : Icons.layers_rounded,
                color: scheme.primary,
              ),
            ],
          ),
          const Spacer(),
          Icon(
            isFront ? Icons.explore_rounded : Icons.style_rounded,
            size: isCompact ? 42 : 56,
            color: scheme.primary,
          ),
          SizedBox(height: isCompact ? 8 : 18),
          Text(
            isFront ? '正在寻找一项没做过的事' : '下一张体验',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
          ),
          SizedBox(height: isCompact ? 6 : 12),
          Text(
            task.title,
            textAlign: TextAlign.center,
            style: (isCompact
                    ? Theme.of(context).textTheme.titleLarge
                    : Theme.of(context).textTheme.headlineSmall)
                ?.copyWith(
              color: cardTextColor,
              fontWeight: FontWeight.w900,
              height: 1.25,
            ),
          ),
          const Spacer(),
          if (isFront)
            Text(
              '这项任务还没有完成，准备好了吗？',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cardTextColor,
                  ),
            ),
        ],
      ),
    );
  }
}

class _ChallengeTaskCard extends StatefulWidget {
  final ThirtyDayChallengeTask task;
  final ValueChanged<bool> onComplete;
  final Future<void> Function(String) onSaveFeeling;
  final VoidCallback onEdit;
  final bool isImageLoading;
  final Future<void> Function() onPickImage;

  const _ChallengeTaskCard({
    required this.task,
    required this.onComplete,
    required this.onSaveFeeling,
    required this.onEdit,
    required this.isImageLoading,
    required this.onPickImage,
  });

  @override
  State<_ChallengeTaskCard> createState() => _ChallengeTaskCardState();
}

Uint8List? _decodeChallengeImage(String? encoded) {
  if (encoded == null || encoded.isEmpty) return null;
  try {
    return base64Decode(encoded);
  } catch (_) {
    return null;
  }
}

/// 为每项挑战分配一组有语义倾向的主题色：餐饮、交通、自然、社交、
/// 创作和情绪表达会使用不同的 Material 主题角色，再通过 HSL 提高饱和度，
/// 避免动态主题生成的浅灰色容器让卡片失去活力。
List<Color> _challengeTaskGradientColors(
  ThirtyDayChallengeTask task,
  ColorScheme scheme,
) {
  final starts = <Color>[
    scheme.secondary, // 餐厅
    scheme.primary, // 交通
    scheme.tertiary, // 老友
    scheme.primary, // 阅读
    scheme.secondary, // 离开网络
    scheme.tertiary, // 早餐
    scheme.tertiary, // 家人
    scheme.primary, // 饮料
    scheme.primary, // 电影
    scheme.secondary, // 跟点
    scheme.tertiary, // 写信
    scheme.secondary, // 手工
    scheme.tertiary, // 自然
    scheme.primary, // 陌生人
    scheme.tertiary, // 回忆
    scheme.secondary, // 整理
    scheme.primary, // 慢跑
    scheme.primary, // 早睡
    scheme.error, // 爱与表达
    scheme.tertiary, // 花
    scheme.secondary, // 野餐
    scheme.error, // 拒绝
    scheme.secondary, // KTV
    scheme.error, // 不加班
    scheme.primary, // 新朋友
    scheme.tertiary, // 礼物
    scheme.primary, // 过夜
    scheme.secondary, // 购物
    scheme.tertiary, // 妆容
    scheme.primary, // 总结
  ];
  final ends = <Color>[
    scheme.tertiary,
    scheme.secondary,
    scheme.primary,
    scheme.tertiary,
    scheme.primary,
    scheme.secondary,
    scheme.secondary,
    scheme.secondary,
    scheme.tertiary,
    scheme.tertiary,
    scheme.primary,
    scheme.tertiary,
    scheme.primary,
    scheme.secondary,
    scheme.primary,
    scheme.primary,
    scheme.tertiary,
    scheme.secondary,
    scheme.tertiary,
    scheme.secondary,
    scheme.tertiary,
    scheme.primary,
    scheme.primary,
    scheme.secondary,
    scheme.tertiary,
    scheme.secondary,
    scheme.tertiary,
    scheme.primary,
    scheme.secondary,
    scheme.tertiary,
  ];
  final hueShifts = <double>[
    16,
    -18,
    10,
    -8,
    24,
    -14,
    8,
    20,
    -12,
    14,
    -20,
    12,
    -10,
    18,
    -16,
    8,
    -14,
    18,
    0,
    -12,
    14,
    0,
    20,
    4,
    -18,
    12,
    -10,
    18,
    -14,
    8,
  ];
  final index = (task.id - 1).clamp(0, starts.length - 1).toInt();
  final shift = hueShifts[index];
  return [
    _vividChallengeColor(starts[index], scheme, hueShift: shift),
    _vividChallengeColor(ends[index], scheme, hueShift: shift - 8),
    _vividChallengeColor(starts[index], scheme, hueShift: shift + 10),
  ];
}

Color _vividChallengeColor(
  Color source,
  ColorScheme scheme, {
  double hueShift = 0,
}) {
  final hsl = HSLColor.fromColor(source);
  final hue = (hsl.hue + hueShift) % 360;

  final vibrantColor = HSLColor.fromAHSL(1, hue, 0.85, 0.5).toColor();
  final opacity = scheme.brightness == Brightness.dark ? 0.35 : 0.18;
  return Color.alphaBlend(
      vibrantColor.withValues(alpha: opacity), scheme.surface);
}

class _ChallengeTaskCardState extends State<_ChallengeTaskCard> {
  late final TextEditingController _feelingController;
  bool _expanded = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _feelingController = TextEditingController(text: widget.task.feeling);
  }

  @override
  void didUpdateWidget(covariant _ChallengeTaskCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.task.feeling != _feelingController.text && !_saving) {
      _feelingController.text = widget.task.feeling;
    }
  }

  @override
  void dispose() {
    _feelingController.dispose();
    super.dispose();
  }

  Future<void> _saveFeeling() async {
    setState(() => _saving = true);
    try {
      await widget.onSaveFeeling(_feelingController.text);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final task = widget.task;
    final isCompactMobile = MediaQuery.sizeOf(context).width < 600 &&
        MediaQuery.of(context).orientation == Orientation.portrait;
    final imageBytes = _decodeChallengeImage(task.imageBase64);
    final hasImage = imageBytes != null;
    final taskColors = _challengeTaskGradientColors(task, scheme);
    final cardColors = task.isCompleted
        ? [
            Color.alphaBlend(
              scheme.primary.withValues(alpha: 0.12),
              taskColors[0],
            ),
            Color.alphaBlend(
              scheme.primary.withValues(alpha: 0.08),
              taskColors[1],
            ),
            taskColors[2],
          ]
        : taskColors;
    final cardForeground = hasImage ? Colors.white : scheme.onSurface;
    final mutedForeground = hasImage
        ? Colors.white.withValues(alpha: 0.8)
        : scheme.onSurfaceVariant;
    final borderColor = task.isCompleted
        ? (hasImage
            ? Colors.white.withValues(alpha: 0.5)
            : taskColors.first.withValues(alpha: 0.66))
        : taskColors.first.withValues(alpha: 0.48);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: hasImage
              ? [
                  taskColors[0].withValues(alpha: 0.3),
                  taskColors[1].withValues(alpha: 0.18),
                  taskColors[2].withValues(alpha: 0.42),
                ]
              : cardColors,
        ),
        image: hasImage
            ? DecorationImage(
                image: MemoryImage(imageBytes),
                fit: BoxFit.cover,
                alignment: Alignment.center,
                filterQuality: FilterQuality.medium,
              )
            : null,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: borderColor, width: task.isCompleted ? 2 : 1),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.15),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: Stack(
          children: [
            if (hasImage)
              Positioned.fill(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          scheme.scrim.withValues(alpha: 0.4),
                          taskColors[1].withValues(alpha: 0.12),
                          scheme.scrim.withValues(alpha: 0.52),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 8),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight.isFinite
                        ? constraints.maxHeight
                        : 450,
                  ),
                  child: Column(
                  children: [
                    InkWell(
                      onTap: () => setState(() => _expanded = !_expanded),
                      borderRadius: BorderRadius.circular(32),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(28, 32, 24, 28),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: task.isCompleted
                                        ? scheme.primary
                                        : hasImage
                                            ? Colors.white
                                                .withValues(alpha: 0.25)
                                            : scheme.surface
                                                .withValues(alpha: 0.4),
                                    borderRadius: BorderRadius.circular(20),
                                    border: hasImage && !task.isCompleted
                                        ? Border.all(
                                            color: Colors.white
                                                .withValues(alpha: 0.5))
                                        : null,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (task.isCompleted) ...[
                                        Icon(
                                          Icons.check_rounded,
                                          size: 18,
                                          color: scheme.onPrimary,
                                        ),
                                        const SizedBox(width: 6),
                                      ],
                                      Text(
                                        task.isCompleted
                                            ? '已完成'
                                            : 'DAY ${task.id}',
                                        style: TextStyle(
                                          color: task.isCompleted
                                              ? scheme.onPrimary
                                              : (hasImage
                                                  ? Colors.white
                                                  : scheme.onSurface),
                                          fontSize: 15,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Row(
                                  children: [
                                    IconButton(
                                      tooltip: '调整任务',
                                      onPressed: widget.onEdit,
                                      icon: const Icon(Icons.edit_note_rounded),
                                      style: IconButton.styleFrom(
                                        backgroundColor: hasImage
                                            ? Colors.white
                                                .withValues(alpha: 0.25)
                                            : scheme.surface
                                                .withValues(alpha: 0.4),
                                        foregroundColor: hasImage
                                            ? Colors.white
                                            : scheme.onSurface,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      tooltip: task.imageBase64 == null
                                          ? '添加背景图'
                                          : '更换背景图',
                                      onPressed: widget.isImageLoading
                                          ? null
                                          : widget.onPickImage,
                                      style: IconButton.styleFrom(
                                        backgroundColor: hasImage
                                            ? Colors.white
                                                .withValues(alpha: 0.25)
                                            : scheme.surface
                                                .withValues(alpha: 0.4),
                                        foregroundColor: hasImage
                                            ? Colors.white
                                            : scheme.onSurface,
                                      ),
                                      icon: widget.isImageLoading
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : Icon(
                                              task.imageBase64 == null
                                                  ? Icons
                                                      .add_photo_alternate_outlined
                                                  : Icons.image_outlined,
                                            ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            Text(
                              task.title,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineMedium
                                  ?.copyWith(
                                    fontSize: isCompactMobile ? 22 : null,
                                    fontWeight: FontWeight.w900,
                                    color: cardForeground,
                                    height: 1.35,
                                    decoration: task.isCompleted
                                        ? TextDecoration.lineThrough
                                        : null,
                                    decorationColor: mutedForeground,
                                  ),
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                if (task.isCompleted)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: hasImage
                                          ? Colors.white.withValues(alpha: 0.2)
                                          : scheme.surface
                                              .withValues(alpha: 0.4),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      '完成于 ${_formatDate(task.completedAt)}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: hasImage
                                                ? Colors.white
                                                : scheme.onSurfaceVariant,
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  )
                                else
                                  Text(
                                    '点击下方展开 · 记录这次感受',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: mutedForeground,
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                if (task.isCustomized)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: hasImage
                                          ? Colors.white.withValues(alpha: 0.2)
                                          : scheme.surface
                                              .withValues(alpha: 0.4),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      '已调整',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: hasImage
                                                ? Colors.white
                                                : scheme.onSurfaceVariant,
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (task.feeling.trim().isNotEmpty)
                      _buildFeelingPreview(
                        context,
                        task,
                        scheme,
                        hasImage,
                      ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 350),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: _expanded
                          ? Padding(
                              padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Divider(
                                      color: hasImage
                                          ? Colors.white.withValues(alpha: 0.2)
                                          : taskColors.first.withValues(
                                              alpha: 0.32,
                                            )),
                                  const SizedBox(height: 12),
                                  Text(
                                    '记下这次的感受',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          color: mutedForeground,
                                          fontWeight: FontWeight.w800,
                                        ),
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: _feelingController,
                                    minLines: 3,
                                    maxLines: 6,
                                    textCapitalization:
                                        TextCapitalization.sentences,
                                    style: TextStyle(
                                        color: hasImage
                                            ? Colors.white
                                            : scheme.onSurface),
                                    decoration: InputDecoration(
                                      hintText: '当时发生了什么？你有什么感觉？',
                                      hintStyle: TextStyle(
                                          color: hasImage
                                              ? Colors.white
                                                  .withValues(alpha: 0.6)
                                              : null),
                                      filled: true,
                                      fillColor: hasImage
                                          ? Colors.white.withValues(alpha: 0.1)
                                          : Color.alphaBlend(
                                              taskColors.first.withValues(
                                                alpha: 0.12,
                                              ),
                                              scheme.surfaceContainerHighest,
                                            ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        borderSide: BorderSide(
                                          color: hasImage
                                              ? Colors.transparent
                                              : scheme.outlineVariant,
                                        ),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        borderSide: BorderSide(
                                          color: hasImage
                                              ? Colors.white
                                                  .withValues(alpha: 0.3)
                                              : scheme.outlineVariant,
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        borderSide: BorderSide(
                                          color: hasImage
                                              ? Colors.white
                                              : scheme.primary,
                                        ),
                                      ),
                                      alignLabelWithHint: true,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    children: [
                                      OutlinedButton.icon(
                                        onPressed:
                                            _saving ? null : _saveFeeling,
                                        icon: _saving
                                            ? const SizedBox(
                                                width: 16,
                                                height: 16,
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                ),
                                              )
                                            : const Icon(
                                                Icons.bookmark_add_outlined),
                                        label: const Text('保存感受'),
                                        style: hasImage
                                            ? OutlinedButton.styleFrom(
                                                foregroundColor: Colors.white,
                                                side: BorderSide(
                                                    color: Colors.white
                                                        .withValues(
                                                            alpha: 0.5)),
                                              )
                                            : null,
                                      ),
                                      const Spacer(),
                                      FilledButton.icon(
                                        onPressed: () => widget
                                            .onComplete(!task.isCompleted),
                                        icon: Icon(task.isCompleted
                                            ? Icons.undo_rounded
                                            : Icons.check_rounded),
                                        label: Text(
                                            task.isCompleted ? '撤销完成' : '完成打卡'),
                                        style: hasImage
                                            ? FilledButton.styleFrom(
                                                backgroundColor: Colors.white,
                                                foregroundColor: Colors.black,
                                              )
                                            : null,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                    const SizedBox(height: 12),
                    if (!_expanded)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: mutedForeground,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '日期未知';
    return DateFormat('M月d日').format(date);
  }

  Widget _buildFeelingPreview(
    BuildContext context,
    ThirtyDayChallengeTask task,
    ColorScheme scheme,
    bool hasImage,
  ) {
    final foreground = hasImage ? scheme.onInverseSurface : scheme.onSurface;
    final taskColors = _challengeTaskGradientColors(task, scheme);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
        decoration: BoxDecoration(
          color: hasImage
              ? scheme.scrim.withValues(alpha: 0.42)
              : Color.alphaBlend(
                  taskColors[1].withValues(alpha: 0.16),
                  scheme.surfaceContainerHighest,
                ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: hasImage
                ? scheme.onInverseSurface.withValues(alpha: 0.24)
                : taskColors.first.withValues(alpha: 0.36),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.format_quote_rounded, size: 20, color: foreground),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                task.feeling,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: foreground,
                      height: 1.35,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
