import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';

import '../../../services/browser_file_service.dart';
import '../../../services/pomodoro_service.dart';
import '../../../storage_service.dart';
import '../../../utils/app_platform.dart';
import '../../../utils/base64_image_provider.dart';
import '../../../utils/app_image_filters.dart';
import '../../../../widgets/optional_liquid_glass_surface.dart';
import '../../../widgets/floating_glass_control.dart';
import '../../habits/services/habit_focus_launcher.dart';
import '../models/thirty_day_challenge.dart';
import '../repositories/thirty_day_challenge_repository.dart';
import '../services/challenge_share_codec.dart';
import '../services/clipboard_share_detector.dart';
import 'new_challenge_screen.dart';
import '../../../utils/app_color_utils.dart';
import '../../../utils/app_dialogs.dart';

part 'parts/thirty_day_challenge_actions.dart';
part 'parts/thirty_day_challenge_welcome_view.dart';
part 'parts/thirty_day_challenge_board_and_report.dart';
part 'parts/thirty_day_challenge_widgets.dart';

const double _welcomeTopBarFadeTail = 20.0;

String _safeFileName(String value) {
  final sanitized = value
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
      .replaceAll(RegExp(r'\s+'), '_')
      .trim();
  return sanitized.isEmpty ? '我的挑战' : sanitized;
}

String _safeHashTag(String value) {
  final sanitized = value.replaceAll(RegExp(r'\s+'), '');
  return sanitized.isEmpty ? '我的挑战' : sanitized;
}

class ThirtyDayChallengeScreen extends StatefulWidget {
  const ThirtyDayChallengeScreen({
    super.key,
    this.showBuiltInIntroduction = false,
  });

  /// Opens the original built-in challenge introduction without loading or
  /// displaying another challenge that may currently be in progress.
  final bool showBuiltInIntroduction;

  @override
  State<ThirtyDayChallengeScreen> createState() =>
      _ThirtyDayChallengeScreenState();
}

class _ThirtyDayChallengeScreenState extends State<ThirtyDayChallengeScreen>
    with SingleTickerProviderStateMixin {
  final _pageController = PageController(viewportFraction: 0.88);
  late final AnimationController _entranceController;
  late final Animation<double> _entranceAnimation;
  late final Animation<Offset> _entranceSlideAnimation;

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
      duration: Duration(milliseconds: AppPlatform.isAndroid ? 260 : 650),
    );
    _entranceAnimation = _entranceController.drive(
      CurveTween(curve: Curves.easeOutCubic),
    );
    _entranceSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.035),
      end: Offset.zero,
    ).animate(_entranceAnimation);
    _load();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  void _mutateState(VoidCallback fn) => setState(fn);

  @override
  Widget build(BuildContext context) {
    final state = _state;
    final scheme = Theme.of(context).colorScheme;
    final isCompactMobile = MediaQuery.sizeOf(context).width < 600;
    return Scaffold(
      // Keep the challenge cards in place while the keyboard opens or closes.
      // The card content already scrolls independently when the input is
      // focused, so resizing the whole page only makes the saved feeling jump
      // around and become difficult to read.
      resizeToAvoidBottomInset: false,
      extendBodyBehindAppBar: true,
      appBar: _showWelcome
          ? FloatingGlassAppBar(
              automaticallyImplyLeading: false,
              leading: IconButton(
                tooltip: '返回',
                onPressed: () => Navigator.of(context).maybePop(),
                style: floatingGlassPlainIconButtonStyle(),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              backgroundColor: Colors.transparent,
              foregroundColor: scheme.onSurface,
              elevation: 0,
              scrolledUnderElevation: 0,
              surfaceTintColor: Colors.transparent,
              shadowColor: Colors.transparent,
              forceMaterialTransparency: true,
              systemOverlayStyle: floatingGlassTopBarSystemOverlayStyle(
                context,
              ),
              flexibleSpace: const FloatingGlassTopBarBackground(),
            )
          : FloatingGlassAppBar(
              backgroundColor: Colors.transparent,
              foregroundColor: scheme.onSurface,
              elevation: 0,
              scrolledUnderElevation: 0,
              surfaceTintColor: Colors.transparent,
              shadowColor: Colors.transparent,
              forceMaterialTransparency: true,
              systemOverlayStyle: floatingGlassTopBarSystemOverlayStyle(
                context,
              ),
              flexibleSpace: const FloatingGlassTopBarBackground(),
              title: Text(
                state?.challengeTitle ?? ThirtyDayChallengeState.defaultTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: isCompactMobile
                    ? Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontSize: 18)
                    : null,
              ),
              actions: [
                IconButton(
                  tooltip: '新建挑战',
                  onPressed: _openNewChallenge,
                  style: floatingGlassPlainIconButtonStyle(),
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
      body: state == null
          ? const Center(child: CircularProgressIndicator())
          : AnimatedBuilder(
              animation: _entranceController,
              child: _showWelcome
                  ? _buildWelcomeBody()
                  : FloatingGlassTopBarContentFade(
                      topBarHeight: kToolbarHeight,
                      child: Padding(
                        padding: EdgeInsets.only(
                          top: floatingGlassTopBarHeight(context),
                        ),
                        child: _buildBody(state),
                      ),
                    ),
              builder: (context, child) {
                if (_entranceController.value >= 0.999) {
                  return child!;
                }
                return FadeTransition(
                  opacity: _entranceAnimation,
                  child: SlideTransition(
                    position: _entranceSlideAnimation,
                    child: child,
                  ),
                );
              },
            ),
    );
  }
}
