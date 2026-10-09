import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/chat_message.dart';

/// Shows the exact function, submitted arguments, and actual app response.
class AiToolCallTile extends StatelessWidget {
  const AiToolCallTile({super.key, required this.call});

  final ChatNativeToolCall call;

  Map<String, dynamic> get _arguments {
    try {
      final value = jsonDecode(call.arguments);
      return value is Map ? Map<String, dynamic>.from(value) : {};
    } catch (_) {
      return {};
    }
  }

  static DateTime? _date(Object? value) {
    if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      return null;
    }
    final parsed = DateTime.tryParse(value);
    return parsed != null && parsed.toIso8601String().startsWith(value)
        ? parsed
        : null;
  }

  static String _range(Map<String, dynamic> args, {bool months = false}) {
    final from = _date(args['start_date']);
    final exclusive = _date(args['end_date_exclusive']);
    if (from == null || exclusive == null || !exclusive.isAfter(from)) {
      return '';
    }
    final last = DateTime(exclusive.year, exclusive.month, exclusive.day - 1);
    final includeYear =
        from.year != last.year || from.year != DateTime.now().year;
    String label(DateTime date) =>
        '${includeYear ? '${date.year}.' : ''}${date.month}${months ? '' : '.${date.day}'}';
    final start = label(from);
    final end = label(last);
    return '${start == end ? start : '$start–$end'}${months ? '月' : ''}';
  }

  String get _title {
    final args = _arguments;
    if (!call.name.startsWith('query_')) {
      return switch (call.name) {
        'propose_cdt_actions' => '生成待办、日程操作草案',
        'propose_finance_drafts' => '生成记账草案',
        'propose_finance_actions' => '生成账单修改草案',
        _ => '工具调用',
      };
    }
    var target = switch (call.name) {
      'query_finance' => switch (args['view']) {
        'summary' => switch (args['type']) {
          'expense' => '支出汇总',
          'income' => '收入汇总',
          'refund' => '退款汇总',
          _ => '收支汇总',
        },
        'catalog' => '记账分类和付款方式',
        'budgets' => '预算',
        _ => switch (args['type']) {
          'expense' => '支出账单',
          'income' => '收入账单',
          'refund' => '退款账单',
          _ => '账单',
        },
      },
      'query_habits' => '习惯进度',
      _ => switch (args['domain']) {
        'todos' => switch (args['status']) {
          'pending' => '未完成待办',
          'completed' => '已完成待办',
          _ => '待办',
        },
        'todo_groups' => '待办分类',
        'courses' => '课程',
        'fixed_schedules' => '固定日程',
        'plan_blocks' => '规划块',
        'time_logs' => '时间日志',
        'pomodoro_records' => '专注记录',
        'pomodoro_tags' => '专注标签',
        'countdowns' => '倒计时',
        'teams' => '团队',
        'conflicts' => '冲突',
        _ => '业务数据',
      },
    };
    if (call.name == 'query_finance' && args['group_by'] == 'merchant') {
      target = '商户支出排行';
    }
    if (args['sort_by'] == 'amount_desc') target = '按金额降序的$target';
    if (args['record_status'] != null) {
      final status = switch (args['record_status']) {
        'completed' || 'finished' => '已完成',
        'interrupted' => '中断的',
        'switched' => '切换的',
        'planned' || 'scheduled' => '已安排的',
        'cancelled' => '已取消',
        'skipped' => '已跳过',
        'focusing' => '正在专注的',
        'delayed' => '已推迟',
        'missed' => '错过的',
        'reminded' => '已提醒',
        _ => '',
      };
      target = '$status$target';
    }
    if (args['date_status'] == 'unscheduled') target = '未安排日期的$target';
    if (args['group_id'] != null) target = '指定分类的$target';
    if (call.name == 'query_app_data' && args['view'] == 'summary') {
      target = '$target汇总';
    }
    final keyword = args['keyword']?.toString().trim() ?? '';
    if (keyword.isNotEmpty) target = '「$keyword」相关$target';
    if (args['id'] != null ||
        args['transaction_id'] != null ||
        args['habit_id'] != null) {
      target = '指定$target详情';
    }
    if (args['category_id'] != null) target = '指定分类的$target';
    if (args['payment_method_id'] != null) target = '指定付款方式的$target';
    final range = _range(
      args,
      months: call.name == 'query_finance' && args['view'] == 'budgets',
    );
    final items = call.result?['items'];
    var page = '';
    if (items is List && call.result?['ok'] == true) {
      final rawOffset = call.result?['offset'];
      final offset = rawOffset is num ? rawOffset.toInt() : 0;
      page = items.isEmpty
          ? '（0条）'
          : call.result?['has_more'] == true || offset > 0
          ? '（第${offset + 1}–${offset + items.length}条）'
          : '（${items.length}条）';
    } else if (args['limit'] is int &&
        (args['limit'] as int) > 0 &&
        (args['limit'] as int) <= 50 &&
        args['view'] != 'summary') {
      final offset = args['offset'] is int ? args['offset'] as int : 0;
      page = '（第${offset + 1}–${offset + (args['limit'] as int)}条）';
    }
    final verb = call.result?['ok'] == false
        ? '查询失败：'
        : call.result?['ok'] == true
        ? '查询了'
        : call.argumentsComplete
        ? '正在查询'
        : '准备查询';
    return '$verb${range.isEmpty ? '' : '$range的'}$target$page';
  }

  static String _pretty(String value) {
    try {
      return const JsonEncoder.withIndent('  ').convert(jsonDecode(value));
    } catch (_) {
      return value.isEmpty ? '（暂无参数）' : value;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    Widget dataBlock(String text, double maxHeight) => Container(
      width: double.infinity,
      constraints: BoxConstraints(maxHeight: maxHeight),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(
        child: SelectableText(
          text,
          style: TextStyle(
            fontSize: 11,
            fontFamily: 'monospace',
            color: colors.onSurface,
          ),
        ),
      ),
    );
    return ExpansionTile(
      key: ValueKey(call.id),
      initiallyExpanded: false,
      dense: true,
      visualDensity: VisualDensity.compact,
      tilePadding: const EdgeInsets.symmetric(horizontal: 10),
      childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      leading: Icon(
        call.argumentsComplete ? Icons.call_made_rounded : Icons.sync_rounded,
        size: 17,
        color: colors.primary,
      ),
      title: Text(
        _title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: colors.onSurface,
        ),
      ),
      subtitle: Text(
        call.resultSummary.isNotEmpty
            ? call.resultSummary
            : call.argumentsComplete
            ? '参数已接收，等待App返回结果…'
            : '正在接收工具名称和参数…',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
      ),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '函数：${call.name.isEmpty ? '接收中' : call.name}',
            style: TextStyle(fontSize: 10, color: colors.onSurfaceVariant),
          ),
        ),
        if (call.id.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '调用 ID：${call.id}',
              style: TextStyle(fontSize: 10, color: colors.onSurfaceVariant),
            ),
          ),
        const SizedBox(height: 6),
        const Align(alignment: Alignment.centerLeft, child: Text('模型提交的参数')),
        const SizedBox(height: 4),
        dataBlock(_pretty(call.arguments), 160),
        if (call.result != null) ...[
          const SizedBox(height: 8),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('App 返回的数据'),
          ),
          const SizedBox(height: 4),
          dataBlock(
            const JsonEncoder.withIndent('  ').convert(call.result),
            260,
          ),
        ] else if (call.resultSummary.isNotEmpty) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('App 处理结果：${call.resultSummary}'),
          ),
        ],
      ],
    );
  }
}
