import 'package:flutter_test/flutter_test.dart';

import 'package:countdown_todo/models/plan_availability.dart';
import 'package:countdown_todo/utils/sync_error_formatter.dart';

void main() {
  group('formatPlanErrorMessage', () {
    test('returns PlanAvailabilityException and StateError messages', () {
      expect(
        formatPlanErrorMessage(
          const PlanAvailabilityException('暂无可用时段'),
          fallback: '默认提示',
        ),
        '暂无可用时段',
      );
      expect(
        formatPlanErrorMessage(StateError('日程已被占用'), fallback: '默认提示'),
        '日程已被占用',
      );
    });

    test('uses fallback when provided for other errors', () {
      expect(
        formatPlanErrorMessage(Exception('boom'), fallback: '读取失败，请重试'),
        '读取失败，请重试',
      );
      expect(formatPlanErrorMessage(Exception('boom')), 'Exception: boom');
    });
  });

  group('SyncErrorFormatter helpers', () {
    test('stripExceptionPrefix strips known prefixes and trims whitespace', () {
      expect(
        SyncErrorFormatter.stripExceptionPrefix(' Exception: 请求失败 '),
        '请求失败',
      );
      expect(
        SyncErrorFormatter.stripExceptionPrefix('Bad state: 状态异常'),
        '状态异常',
      );
      expect(
        SyncErrorFormatter.stripExceptionPrefix('FormatException: 解析错误'),
        '解析错误',
      );
    });

    test('extractMessage prefers StateError.message and strips prefixes', () {
      expect(SyncErrorFormatter.extractMessage(StateError('无权限')), '无权限');
      expect(SyncErrorFormatter.extractMessage(Exception('网络断开')), '网络断开');
    });
  });
}
