import 'dart:async';

import 'package:flutter/material.dart';

import '../../../utils/page_transitions.dart';
import '../../../widgets/floating_glass_control.dart';
import '../models/cloud_challenge.dart';
import '../models/thirty_day_challenge.dart';
import '../repositories/thirty_day_challenge_repository.dart';
import 'cloud_challenge_picker_screen.dart';
import 'new_challenge_screen.dart';
import 'thirty_day_challenge_screen.dart';

/// The entry page for challenges.
///
/// A challenge is a module rather than a single 30-day activity. The current
/// challenge remains available from this page, while new users can choose a
/// cloud template or create a list of their own.
class ChallengeCenterScreen extends StatefulWidget {
  const ChallengeCenterScreen({super.key});

  @override
  State<ChallengeCenterScreen> createState() => _ChallengeCenterScreenState();
}

class _ChallengeCenterScreenState extends State<ChallengeCenterScreen> {
  ThirtyDayChallengeState? _currentChallenge;
  bool _hasStarted = false;
  bool _isLoading = true;
  bool _isStarting = false;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    ThirtyDayChallengeRepository.activityRevision
        .addListener(_onChallengeActivityChanged);
    _load();
  }

  @override
  void dispose() {
    ThirtyDayChallengeRepository.activityRevision
        .removeListener(_onChallengeActivityChanged);
    super.dispose();
  }

  void _onChallengeActivityChanged() {
    unawaited(_load(showLoading: false));
  }

  Future<void> _load({bool showLoading = true}) async {
    final generation = ++_loadGeneration;
    if (showLoading && mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final hasStarted = await ThirtyDayChallengeRepository.hasStarted();
      final state =
          hasStarted ? await ThirtyDayChallengeRepository.load() : null;
      if (!mounted || generation != _loadGeneration) return;

      setState(() {
        _hasStarted = hasStarted;
        _currentChallenge = state;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _hasStarted = false;
        _currentChallenge = null;
        _isLoading = false;
      });
    }
  }

  Future<void> _openCurrentChallenge() async {
    await Navigator.of(context).push(
      PageTransitions.slideHorizontal(const ThirtyDayChallengeScreen()),
    );
    if (mounted) await _load(showLoading: false);
  }

  Future<void> _openClassicChallenge() async {
    await Navigator.of(context).push(
      PageTransitions.slideHorizontal(
        const ThirtyDayChallengeScreen(showBuiltInIntroduction: true),
      ),
    );
    if (mounted) await _load(showLoading: false);
  }

  Future<void> _openChallengeLibrary() async {
    final result = await Navigator.of(context).push<CloudChallengePickerResult>(
      PageTransitions.material(
        builder: (_) => const CloudChallengePickerScreen(),
      ),
    );
    if (result == null || !mounted) return;

    if (result.action == CloudChallengePickerAction.start) {
      final challenge = result.challenge;
      if (challenge != null) await _startChallenge(challenge.toDraft());
      return;
    }

    final draft = await Navigator.of(context).push<ChallengeDraft>(
      PageTransitions.material(
        builder: (_) => NewChallengeScreen(
          initialDraft: result.challenge?.toDraft(),
        ),
      ),
    );
    if (draft != null && mounted) await _startChallenge(draft);
  }

  Future<void> _openCustomChallenge() async {
    final draft = await Navigator.of(context).push<ChallengeDraft>(
      PageTransitions.material(
        builder: (_) => const NewChallengeScreen(),
      ),
    );
    if (draft != null && mounted) await _startChallenge(draft);
  }

  Future<void> _startChallenge(ChallengeDraft draft) async {
    if (_isStarting || !mounted) return;

    if (_hasStarted && _currentChallenge != null) {
      final current = _currentChallenge!;
      final shouldReplace = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.auto_awesome_rounded),
          title: const Text('开启新的挑战？'),
          content: Text(
            '当前正在进行「${current.challengeTitle}」。开启新挑战后，当前挑战的完成状态、感受和图片将被替换，无法恢复。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('继续当前挑战'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('开启新挑战'),
            ),
          ],
        ),
      );
      if (shouldReplace != true || !mounted) return;
    }

    setState(() => _isStarting = true);
    try {
      final state = await ThirtyDayChallengeRepository.startNewChallenge(
        title: draft.title,
        taskTitles: draft.taskTitles,
      );
      if (!mounted) return;

      setState(() {
        _hasStarted = true;
        _currentChallenge = state;
      });
      await _openCurrentChallenge();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('挑战开启失败，请稍后再试')),
      );
    } finally {
      if (mounted) setState(() => _isStarting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      extendBodyBehindAppBar: true,
      appBar: FloatingGlassAppBar(
        flexibleSpace: const FloatingGlassTopBarBackground(),
        title: const Text('挑战中心'),
        actions: [
          IconButton(
            style: floatingGlassPlainIconButtonStyle(),
            tooltip: '刷新挑战状态',
            onPressed: _isLoading ? null : () => _load(showLoading: false),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : FloatingGlassTopBarContentFade(
              topBarHeight: kToolbarHeight,
              child: Stack(
                children: [
                  Positioned.fill(child: _buildBackdrop(scheme)),
                  RefreshIndicator(
                    onRefresh: () => _load(showLoading: false),
                    color: scheme.primary,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth >= 760;
                        return SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: EdgeInsets.fromLTRB(
                            isWide ? 28 : 16,
                            floatingGlassTopBarHeight(context) + 16,
                            isWide ? 28 : 16,
                            40,
                          ),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 1080),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _buildHero(scheme, isWide: isWide),
                                  const SizedBox(height: 28),
                                  if (_hasStarted && _currentChallenge != null)
                                    _buildActiveSection(
                                      scheme,
                                      _currentChallenge!,
                                    )
                                  else
                                    _buildEmptyState(scheme),
                                  const SizedBox(height: 28),
                                  _buildStartSection(scheme, isWide: isWide),
                                  const SizedBox(height: 28),
                                  _buildRulesSection(scheme, isWide: isWide),
                                ],
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
    );
  }

  Widget _buildBackdrop(ColorScheme scheme) {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: -96,
            right: -72,
            child: _BackdropOrb(
              diameter: 240,
              color: scheme.primary.withValues(alpha: 0.09),
            ),
          ),
          Positioned(
            top: 330,
            left: -112,
            child: _BackdropOrb(
              diameter: 220,
              color: scheme.tertiary.withValues(alpha: 0.07),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHero(ColorScheme scheme, {required bool isWide}) {
    final titleStyle = Theme.of(context).textTheme.headlineLarge?.copyWith(
          color: scheme.onPrimaryContainer,
          fontWeight: FontWeight.w900,
          height: 1.08,
          letterSpacing: -1.0,
        );
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_awesome_rounded,
              size: 16,
              color: scheme.primary,
            ),
            const SizedBox(width: 7),
            Text(
              'CHALLENGE CENTER',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text('下一场挑战，\n由你决定', style: titleStyle),
        const SizedBox(height: 12),
        Text(
          '把想做的事变成一场可完成的挑战。选择一个主题，或从零写下你的清单。',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: scheme.onPrimaryContainer.withValues(alpha: 0.78),
                height: 1.5,
              ),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              onPressed: _isStarting ? null : _openChallengeLibrary,
              icon: const Icon(Icons.explore_rounded),
              label: const Text('探索挑战库'),
              style: FilledButton.styleFrom(
                backgroundColor: scheme.primary,
                foregroundColor: scheme.onPrimary,
                minimumSize: const Size(0, 48),
              ),
            ),
            OutlinedButton.icon(
              onPressed: _isStarting ? null : _openCustomChallenge,
              icon: const Icon(Icons.edit_note_rounded),
              label: const Text('创建自定义'),
              style: OutlinedButton.styleFrom(
                foregroundColor: scheme.onPrimaryContainer,
                side: BorderSide(
                  color: scheme.onPrimaryContainer.withValues(alpha: 0.35),
                ),
                minimumSize: const Size(0, 48),
              ),
            ),
          ],
        ),
      ],
    );

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primaryContainer, scheme.secondaryContainer],
        ),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -96,
            right: isWide ? 120 : -80,
            child: _BackdropOrb(
              diameter: 230,
              color: scheme.tertiary.withValues(alpha: 0.13),
            ),
          ),
          Positioned(
            bottom: -110,
            left: isWide ? 220 : -80,
            child: _BackdropOrb(
              diameter: 210,
              color: scheme.primary.withValues(alpha: 0.1),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              isWide ? 32 : 22,
              isWide ? 30 : 24,
              isWide ? 24 : 22,
              isWide ? 30 : 24,
            ),
            child: isWide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(child: copy),
                      const SizedBox(width: 22),
                      _buildHeroIllustration(scheme),
                    ],
                  )
                : copy,
          ),
        ],
      ),
    );
  }

  Widget _buildHeroIllustration(ColorScheme scheme) {
    return SizedBox(
      width: 180,
      height: 178,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            right: 2,
            top: 18,
            child: Transform.rotate(
              angle: 0.11,
              child: Container(
                width: 126,
                height: 144,
                decoration: BoxDecoration(
                  color: scheme.surface.withValues(alpha: 0.42),
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(
                    color: scheme.onPrimaryContainer.withValues(alpha: 0.12),
                  ),
                ),
              ),
            ),
          ),
          Transform.rotate(
            angle: -0.08,
            child: Container(
              width: 132,
              height: 148,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: scheme.surface.withValues(alpha: 0.84),
                borderRadius: BorderRadius.circular(25),
                boxShadow: [
                  BoxShadow(
                    color: scheme.primary.withValues(alpha: 0.14),
                    blurRadius: 22,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(17),
                    ),
                    child: Icon(
                      Icons.flag_rounded,
                      color: scheme.onPrimaryContainer,
                      size: 28,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    height: 8,
                    width: 76,
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 8,
                    width: 48,
                    decoration: BoxDecoration(
                      color: scheme.onSurface.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 2,
            bottom: 18,
            child: _HeroDot(color: scheme.tertiary, icon: Icons.bolt_rounded),
          ),
          Positioned(
            right: 12,
            bottom: 4,
            child: _HeroDot(
              color: scheme.secondary,
              icon: Icons.check_rounded,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.58),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              Icons.flag_outlined,
              color: scheme.onTertiaryContainer,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '还没有进行中的挑战',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 5),
                Text(
                  '从一个轻松的主题开始，今天完成第一项就算出发。',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveSection(
    ColorScheme scheme,
    ThirtyDayChallengeState challenge,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionHeading(
          '正在进行',
          challenge.isCompleted ? '这一场已经完成，回看你的记录' : '保持自己的节奏，下一项随时可以开始',
        ),
        const SizedBox(height: 12),
        _buildActiveChallengeCard(scheme, challenge),
      ],
    );
  }

  Widget _buildActiveChallengeCard(
    ColorScheme scheme,
    ThirtyDayChallengeState challenge,
  ) {
    final isCompleted = challenge.isCompleted;
    final foreground =
        isCompleted ? scheme.onTertiaryContainer : scheme.onPrimaryContainer;
    final backgroundColors = isCompleted
        ? [scheme.tertiaryContainer, scheme.secondaryContainer]
        : [scheme.primaryContainer, scheme.secondaryContainer];
    final progress = challenge.progress.clamp(0.0, 1.0).toDouble();
    final taskCount = challenge.tasks.length;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(28),
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: backgroundColors,
          ),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.42),
          ),
        ),
        child: InkWell(
          onTap: _isStarting ? null : _openCurrentChallenge,
          borderRadius: BorderRadius.circular(28),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 620;
                final heading = Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: scheme.surface.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Icon(
                        isCompleted
                            ? Icons.emoji_events_rounded
                            : Icons.flag_rounded,
                        color: foreground,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isCompleted ? '挑战完成' : '继续你的挑战',
                            style: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(
                                  color: foreground.withValues(alpha: 0.76),
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            challenge.challengeTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                  color: foreground,
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                        ],
                      ),
                    ),
                    if (isWide) ...[
                      const SizedBox(width: 12),
                      _buildProgressBadge(
                        foreground,
                        '${challenge.completedCount}/$taskCount',
                      ),
                    ],
                  ],
                );

                final progressContent = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Text(
                          '完成进度',
                          style:
                              Theme.of(context).textTheme.labelMedium?.copyWith(
                                    color: foreground.withValues(alpha: 0.78),
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                        const Spacer(),
                        Text(
                          '$taskCount 项任务 · ${challenge.completedCount} 项已完成',
                          style:
                              Theme.of(context).textTheme.labelMedium?.copyWith(
                                    color: foreground.withValues(alpha: 0.78),
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 9),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 10,
                        color: foreground,
                        backgroundColor: foreground.withValues(alpha: 0.16),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.tonalIcon(
                        onPressed: _isStarting ? null : _openCurrentChallenge,
                        icon: Icon(
                          isCompleted
                              ? Icons.auto_stories_rounded
                              : Icons.arrow_forward_rounded,
                        ),
                        label: Text(isCompleted ? '查看挑战记录' : '继续挑战'),
                        style: FilledButton.styleFrom(
                          backgroundColor: foreground.withValues(alpha: 0.14),
                          foregroundColor: foreground,
                        ),
                      ),
                    ),
                  ],
                );

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    heading,
                    if (!isWide) ...[
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _buildProgressBadge(
                          foreground,
                          '${challenge.completedCount}/$taskCount',
                        ),
                      ),
                    ],
                    progressContent,
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProgressBadge(Color foreground, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: foreground.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        value,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w900,
            ),
      ),
    );
  }

  Widget _buildStartSection(ColorScheme scheme, {required bool isWide}) {
    final libraryCard = _buildStartOption(
      scheme: scheme,
      icon: Icons.explore_rounded,
      accent: scheme.primary,
      title: '探索挑战库',
      description: '从现成主题开始，挑一场现在就想做的挑战。',
      onTap: _isStarting ? null : _openChallengeLibrary,
    );
    final customCard = _buildStartOption(
      scheme: scheme,
      icon: Icons.edit_note_rounded,
      accent: scheme.tertiary,
      title: '创建自定义挑战',
      description: '把自己的愿望、计划或任务清单，变成专属挑战。',
      onTap: _isStarting ? null : _openCustomChallenge,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionHeading('开始一场新的挑战', '有模板可选，也可以完全从零开始'),
        const SizedBox(height: 12),
        _buildClassicChallengeCard(scheme),
        const SizedBox(height: 12),
        if (isWide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: libraryCard),
              const SizedBox(width: 14),
              Expanded(child: customCard),
            ],
          )
        else
          Column(
            children: [
              libraryCard,
              const SizedBox(height: 12),
              customCard,
            ],
          ),
      ],
    );
  }

  Widget _buildClassicChallengeCard(ColorScheme scheme) {
    return Material(
      color: scheme.tertiaryContainer,
      borderRadius: BorderRadius.circular(26),
      child: InkWell(
        onTap: _isStarting ? null : _openClassicChallenge,
        borderRadius: BorderRadius.circular(26),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 58,
                height: 58,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [scheme.tertiary, scheme.primary],
                  ),
                  borderRadius: BorderRadius.circular(19),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.tertiary.withValues(alpha: 0.22),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.local_fire_department_rounded,
                  color: scheme.onPrimary,
                  size: 31,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '经典挑战',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelMedium
                                    ?.copyWith(
                                      color: scheme.onTertiaryContainer
                                          .withValues(alpha: 0.72),
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                ThirtyDayChallengeState.defaultTitle,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(
                                      color: scheme.onTertiaryContainer,
                                      fontWeight: FontWeight.w900,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.arrow_outward_rounded,
                          color: scheme.onTertiaryContainer,
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Text(
                      '30 项生活小任务 · 顺序自由安排',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: scheme.onTertiaryContainer.withValues(
                              alpha: 0.78,
                            ),
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '给平淡生活加一点新鲜感，重新找回对日常的感受力。',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: scheme.onTertiaryContainer.withValues(
                              alpha: 0.82,
                            ),
                            height: 1.4,
                          ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      '点击查看挑战介绍',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: scheme.onTertiaryContainer,
                            fontWeight: FontWeight.w900,
                          ),
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

  Widget _buildStartOption({
    required ColorScheme scheme,
    required IconData icon,
    required Color accent,
    required String title,
    required String description,
    required VoidCallback? onTap,
  }) {
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 50,
                height: 50,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(17),
                ),
                child: Icon(icon, color: accent, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                        ),
                        Icon(Icons.arrow_outward_rounded, color: accent),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      description,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.4,
                          ),
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

  Widget _buildRulesSection(ColorScheme scheme, {required bool isWide}) {
    const steps = [
      (
        icon: Icons.explore_outlined,
        title: '选一个方向',
        description: '从挑战库挑选，或写下自己的清单',
      ),
      (
        icon: Icons.check_circle_outline_rounded,
        title: '按自己的节奏',
        description: '不限定 30 天，也不要求连续完成',
      ),
      (
        icon: Icons.auto_stories_outlined,
        title: '留下这段经历',
        description: '完成任务后记录感受与生活照片',
      ),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '挑战可以很自由',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 5),
          Text(
            '这里没有标准答案，重要的是给自己一个愿意开始的小目标。',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.4,
                ),
          ),
          const SizedBox(height: 18),
          if (isWide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var index = 0; index < steps.length; index++) ...[
                  Expanded(child: _buildRuleItem(scheme, steps[index])),
                  if (index < steps.length - 1) const SizedBox(width: 14),
                ],
              ],
            )
          else
            Column(
              children: [
                for (var index = 0; index < steps.length; index++) ...[
                  _buildRuleItem(scheme, steps[index]),
                  if (index < steps.length - 1) const SizedBox(height: 14),
                ],
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildRuleItem(
    ColorScheme scheme,
    ({String description, IconData icon, String title}) step,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(step.icon, color: scheme.onPrimaryContainer, size: 21),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                step.title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 3),
              Text(
                step.description,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.35,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeading(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

class _BackdropOrb extends StatelessWidget {
  const _BackdropOrb({required this.diameter, required this.color});

  final double diameter;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      child: SizedBox.square(dimension: diameter),
    );
  }
}

class _HeroDot extends StatelessWidget {
  const _HeroDot({required this.color, required this.icon});

  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: scheme.surface.withValues(alpha: 0.82),
          width: 3,
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.onSurface.withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Icon(icon, color: scheme.onPrimary, size: 21),
    );
  }
}
