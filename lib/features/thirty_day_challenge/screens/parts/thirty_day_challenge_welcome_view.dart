part of '../thirty_day_challenge_screen.dart';

extension _ThirtyDayChallengeWelcomeExt on _ThirtyDayChallengeScreenState {
  Widget _buildWelcomeBody() {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isLandscape =
              constraints.maxWidth > constraints.maxHeight &&
              constraints.maxHeight > 0;
          final isCompactMobile = !isLandscape && constraints.maxWidth < 600;
          final titleStyle =
              Theme.of(context).textTheme.displaySmall?.copyWith(
                fontSize: isCompactMobile ? 30 : null,
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
          // Keep a smaller fallback for exceptionally narrow devices only.
          // Regular phones should use the scrollable, more spacious layout.
          if (isCompactMobile && constraints.maxWidth < 320) {
            return _buildCompactWelcomeBody(
              scheme: scheme,
              welcomePrimary: welcomePrimary,
              welcomeSecondary: welcomeSecondary,
              welcomeTertiary: welcomeTertiary,
              availableHeight: constraints.maxHeight,
            );
          }
          final contentHorizontalPadding = isLandscape
              ? 48.0
              : (isCompactMobile ? 20.0 : 24.0);
          final contentTopPadding = isLandscape
              ? 32.0
              : (isCompactMobile ? 72.0 : 48.0);
          return DecoratedBox(
            decoration: BoxDecoration(color: scheme.surface),
            child: Stack(
              children: [
                // Background blurred blobs isolated in a static RepaintBoundary
                // so scrolling never re-triggers full-screen blur60.
                Positioned.fill(
                  child: IgnorePointer(
                    child: RepaintBoundary(
                      child: Stack(
                        children: [
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
                          if (!AppPlatform.isWindows)
                            Positioned.fill(
                              child: BackdropFilter.grouped(
                                filter: AppImageFilters.blur60,
                                child: const SizedBox(),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Content
                FloatingGlassTopBarContentFade(
                  topBarHeight: kToolbarHeight,
                  tailExtent: _welcomeTopBarFadeTail,
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      contentHorizontalPadding,
                      contentTopPadding,
                      contentHorizontalPadding,
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
                                    color: scheme.outlineVariant.withValues(
                                      alpha: 0.5,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  'A LITTLE LIFE EXPERIMENT',
                                  style: Theme.of(context).textTheme.labelMedium
                                      ?.copyWith(
                                        color: welcomePrimary,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1.5,
                                      ),
                                ),
                              ),
                            ),
                            SizedBox(height: isLandscape ? 30 : 36),
                            Center(
                              child: Container(
                                width: isLandscape
                                    ? 100
                                    : (isCompactMobile ? 104 : 120),
                                height: isLandscape
                                    ? 100
                                    : (isCompactMobile ? 104 : 120),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [scheme.primary, scheme.tertiary],
                                  ),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: scheme.onSurface.withValues(
                                      alpha: 0.14,
                                    ),
                                    width: 6,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: welcomePrimary.withValues(
                                        alpha: 0.42,
                                      ),
                                      blurRadius: AppPlatform.isAndroid
                                          ? 14
                                          : 32,
                                      offset: AppPlatform.isAndroid
                                          ? const Offset(0, 6)
                                          : const Offset(0, 16),
                                    ),
                                    BoxShadow(
                                      color: scheme.tertiary.withValues(
                                        alpha: 0.18,
                                      ),
                                      blurRadius: AppPlatform.isAndroid ? 4 : 8,
                                      spreadRadius: AppPlatform.isAndroid
                                          ? 2
                                          : 4,
                                    ),
                                  ],
                                ),
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Icon(
                                      Icons.auto_awesome_rounded,
                                      size: isLandscape
                                          ? 50
                                          : (isCompactMobile ? 52 : 60),
                                      color: scheme.onPrimary,
                                    ),
                                    Positioned(
                                      right: isLandscape
                                          ? 10
                                          : (isCompactMobile ? 10 : 12),
                                      top: isLandscape
                                          ? 10
                                          : (isCompactMobile ? 10 : 12),
                                      child: Icon(
                                        Icons.star_rounded,
                                        size: isLandscape
                                            ? 16
                                            : (isCompactMobile ? 18 : 20),
                                        color: scheme.onPrimary.withValues(
                                          alpha: 0.75,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 28),
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
                              style: Theme.of(context).textTheme.displaySmall
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
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
                                    fontSize: isCompactMobile ? 17 : null,
                                    color: scheme.onSurfaceVariant,
                                    height: 1.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                            SizedBox(height: isLandscape ? 32 : 36),
                            OptionalLiquidGlassCard(
                              borderRadius: 32,
                              highContrast: true,
                              padding: EdgeInsets.all(
                                isCompactMobile ? 22 : 28,
                              ),
                              fallbackDecoration: BoxDecoration(
                                color: scheme.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(32),
                                border: Border.all(
                                  color: scheme.outlineVariant.withValues(
                                    alpha: 0.5,
                                  ),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: scheme.shadow.withValues(
                                      alpha: 0.05,
                                    ),
                                    blurRadius: AppPlatform.isAndroid ? 10 : 24,
                                    offset: AppPlatform.isAndroid
                                        ? const Offset(0, 4)
                                        : const Offset(0, 8),
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
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
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
                                    style: Theme.of(context).textTheme.bodyLarge
                                        ?.copyWith(
                                          color: scheme.onSurface,
                                          height: isCompactMobile ? 1.7 : 1.8,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            OptionalLiquidGlassCard(
                              borderRadius: 32,
                              highContrast: true,
                              padding: EdgeInsets.all(
                                isCompactMobile ? 22 : 28,
                              ),
                              fallbackDecoration: BoxDecoration(
                                color: scheme.surfaceContainer,
                                borderRadius: BorderRadius.circular(32),
                                border: Border.all(
                                  color: scheme.outlineVariant.withValues(
                                    alpha: 0.5,
                                  ),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: scheme.primary.withValues(
                                        alpha: 0.16,
                                      ),
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
                                                color:
                                                    scheme.onPrimaryContainer,
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
                            OptionalLiquidGlassCard(
                              borderRadius: 32,
                              highContrast: true,
                              padding: EdgeInsets.all(
                                isCompactMobile ? 22 : 28,
                              ),
                              fallbackDecoration: BoxDecoration(
                                color: scheme.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(32),
                                border: Border.all(
                                  color: scheme.outlineVariant.withValues(
                                    alpha: 0.5,
                                  ),
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
                                            height: isCompactMobile ? 1.7 : 1.8,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(height: isLandscape ? 32 : 36),
                            FilledButton.icon(
                              onPressed: _enterChallenge,
                              icon: const Icon(Icons.bolt_rounded),
                              label: const Text('开始这场挑战'),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(64),
                                elevation: 6,
                                shadowColor: scheme.primary.withValues(
                                  alpha: 0.35,
                                ),
                                textStyle: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(24),
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            _buildDeferButton(scheme),
                            const SizedBox(height: 8),
                            Text(
                              '记录感受和照片，让这段改变真正留下来。',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDeferButton(ColorScheme scheme, {bool compact = false}) {
    final buttonHeight = compact ? 50.0 : 64.0;
    final buttonRadius = compact ? 18.0 : 24.0;
    return OutlinedButton.icon(
      onPressed: _deferChallenge,
      icon: Icon(Icons.schedule_outlined, size: compact ? 18 : null),
      label: const Text('暂不参与'),
      style: OutlinedButton.styleFrom(
        minimumSize: Size.fromHeight(buttonHeight),
        foregroundColor: scheme.onSurfaceVariant,
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(buttonRadius),
        ),
        textStyle: TextStyle(
          fontSize: compact ? 15 : 18,
          fontWeight: FontWeight.w800,
        ),
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
    final titleStyle =
        Theme.of(context).textTheme.displaySmall?.copyWith(
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
    final minContentHeight = availableHeight.isFinite
        ? max(0.0, availableHeight - 24)
        : 0.0;

    return DecoratedBox(
      decoration: BoxDecoration(color: scheme.surface),
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
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
                    if (!AppPlatform.isWindows)
                      Positioned.fill(
                        child: BackdropFilter.grouped(
                          filter: AppImageFilters.blur48,
                          child: const SizedBox(),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: FloatingGlassTopBarContentFade(
              topBarHeight: kToolbarHeight,
              tailExtent: _welcomeTopBarFadeTail,
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
                                color: scheme.outlineVariant.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                            ),
                            child: Text(
                              'A LITTLE LIFE EXPERIMENT',
                              style: Theme.of(context).textTheme.labelSmall
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
                                    color: scheme.onPrimary.withValues(
                                      alpha: 0.75,
                                    ),
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
                                style: titleStyle.copyWith(
                                  color: welcomePrimary,
                                ),
                              ),
                            ],
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '给平淡生活加一点新鲜感，重新找回生命的感受力。',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(
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
                              color: scheme.outlineVariant.withValues(
                                alpha: 0.5,
                              ),
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
                        const SizedBox(height: 12),
                        _buildDeferButton(scheme, compact: true),
                        const SizedBox(height: 8),
                        Text(
                          '记录感受和照片，让这段改变真正留下来。',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
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
          ),
        ],
      ),
    );
  }

  Widget _buildCompactWelcomeQuoteCard({
    required ColorScheme scheme,
    required Color welcomePrimary,
    required Color welcomeSecondary,
  }) {
    return OptionalLiquidGlassCard(
      borderRadius: 18,
      highContrast: true,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      fallbackDecoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
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
    return OptionalLiquidGlassCard(
      borderRadius: 18,
      highContrast: true,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      fallbackDecoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.local_activity_rounded, color: scheme.secondary, size: 22),
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
}
