import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../services/course_service.dart';
import '../services/pomodoro_service.dart';
import '../models.dart';
import '../storage_service.dart';
import '../utils/app_color_utils.dart';
import '../utils/app_dialogs.dart';
import '../utils/local_image_provider.dart';
import '../utils/page_transitions.dart';
import 'time_log_screen.dart';
import 'course_month_view.dart';
import '../widgets/app_detail_widgets.dart';
import '../utils/theme_color_tokens.dart';
import '../utils/todo_recurrence_calendar_index.dart';
import '../services/feature_tip_service.dart';
import '../widgets/coach_mark_overlay.dart';
import '../widgets/floating_glass_control.dart';

// --- 二级界面：按周查看课表 (全屏自适应压缩视图) ---

part 'course_screens_contract.dart';
part 'course_screens_lifecycle.dart';
part 'course_screens_navigation.dart';
part 'course_screens_grid.dart';
part 'course_screens_view.dart';
part 'course_detail_screens.dart';

class WeeklyCourseScreen extends StatefulWidget {
  final String username;
  const WeeklyCourseScreen({super.key, required this.username});

  @override
  State<WeeklyCourseScreen> createState() => _WeeklyCourseScreenState();
}

class _HiddenTimeRange {
  const _HiddenTimeRange(this.startMinute, this.endMinute);

  final double startMinute;
  final double endMinute;

  double get duration => endMinute - startMinute;

  bool contains(double minute) => minute > startMinute && minute < endMinute;

  double hiddenBefore(double minute) {
    if (minute <= startMinute) return 0.0;
    if (minute >= endMinute) return duration;
    return minute - startMinute;
  }
}

class _TimelineEvent {
  final double top;
  final double bottom;
  final Widget Function(double left, double width) builder;
  int columnIndex = 0;
  int maxColumns = 1;
  int colSpan = 1;

  _TimelineEvent({
    required this.top,
    required this.bottom,
    required this.builder,
  });
}

class _WeeklyCourseScreenState extends _WeeklyCourseScreenStateBase
    with
        _WeeklyCourseLifecycle,
        _WeeklyCourseNavigation,
        _WeeklyCourseGrid,
        _WeeklyCourseView {}
