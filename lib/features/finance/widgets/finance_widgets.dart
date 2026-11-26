import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../../utils/app_platform.dart';
import '../../../widgets/floating_bottom_bar.dart';
import '../../../utils/page_transitions.dart';
import '../models/finance_models.dart';
import '../services/finance_repository.dart';
import '../screens/finance_category_detail_screen.dart';
import 'finance_calendar_panel.dart';
import 'finance_glass_segment_selector.dart';

import '../../../utils/app_dialogs.dart';
import '../../../utils/calendar_date_math.dart';

part 'parts/finance_overview_panel.dart';
part 'parts/finance_overview_charts.dart';
part 'parts/finance_overview_cards.dart';
part 'parts/finance_unified_category_card.dart';
part 'parts/finance_ledger_panel.dart';
part 'parts/finance_ledger_actions_and_sections.dart';
part 'parts/finance_ledger_dialogs.dart';
part 'parts/finance_chart_models_and_painters.dart';
part 'parts/finance_category_donut_chart.dart';

/// Leaves enough scrollable room for the shared navigation bar and its bottom
/// margin, so the final finance card can clear the bar completely.
double financeBottomContentPaddingFor(BuildContext context) {
  return floatingBottomNavigationContentPaddingFor(context);
}

enum _FinanceOverviewView { month, week, day }

enum _FinanceOverviewMode { report, calendar }

typedef _FinanceOverviewPeriodCacheKey = ({
  List<FinanceTransaction> transactions,
  FinanceSummary summary,
  Map<String, FinanceCategory> categories,
  DateTime from,
  DateTime to,
  _FinanceOverviewView view,
  DateTime Function() clock,
  bool includesNow,
  bool isPlanned,
  bool selectedMonthIsCurrent,
  bool focusedDateIsToday,
});

typedef FinanceCategorySelectionCallback = Future<void> Function(
  String categoryUuid,
  GlobalKey sourceKey,
  List<FinanceTransaction> periodTransactions,
);

typedef FinanceCategoryRangeSelectionCallback = Future<void> Function(
  String categoryUuid,
  GlobalKey sourceKey,
  List<FinanceTransaction> periodTransactions,
  DateTimeRange periodRange,
);

typedef FinanceMonthLedgerCallback = Future<void> Function(
  DateTime month,
  GlobalKey sourceKey,
);
