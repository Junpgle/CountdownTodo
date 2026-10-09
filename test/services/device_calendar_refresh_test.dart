import 'dart:async';

import 'package:countdown_todo/services/device_calendar_read_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('countdown_todo/device_calendar_read');
  final start = DateTime(2026, 10, 8);
  final end = DateTime(2026, 10, 9);
  Map<String, Object> event(
    String id,
    DateTime from,
    DateTime to, {
    bool allDay = false,
  }) => {
    'id': id,
    'calendarId': 'synthetic',
    'title': '合成事件',
    'startMs': from.millisecondsSinceEpoch,
    'endMs': to.millisecondsSinceEpoch,
    'allDay': allDay,
  };
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'device_calendar_read_enabled': true,
    });
    DeviceCalendarReadService.debugIsSupportedOverride = true;
    DeviceCalendarReadService.clearSessionReadCacheForTesting();
  });
  tearDown(() {
    DeviceCalendarReadService.debugIsSupportedOverride = null;
    DeviceCalendarReadService.clearSessionReadCacheForTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  test('默认复用缓存，保存复查强制读取新占用', () async {
    var reads = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'checkPermission') return true;
          reads++;
          return reads == 1
              ? []
              : [
                  event(
                    'new',
                    start.add(const Duration(hours: 8)),
                    start.add(const Duration(hours: 9)),
                  ),
                ];
        });
    expect(
      await DeviceCalendarReadService.readEvents(start: start, end: end),
      isEmpty,
    );
    expect(
      await DeviceCalendarReadService.readEvents(start: start, end: end),
      isEmpty,
    );
    expect(reads, 1);
    expect(
      (await DeviceCalendarReadService.readEvents(
        start: start,
        end: end,
        forceRefresh: true,
      )).single.id,
      'new',
    );
    expect(reads, 2);
  });
  test('旧查询晚返回不能污染强制刷新后的缓存', () async {
    final old = Completer<List<dynamic>>(), fresh = Completer<List<dynamic>>();
    var reads = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'checkPermission') return true;
          return ++reads == 1 ? old.future : fresh.future;
        });
    final first = DeviceCalendarReadService.readEvents(start: start, end: end);
    await Future<void>.delayed(Duration.zero);
    final second = DeviceCalendarReadService.readEvents(
      start: start,
      end: end,
      forceRefresh: true,
    );
    await Future<void>.delayed(Duration.zero);
    fresh.complete([event('fresh', start, end)]);
    expect((await second).single.id, 'fresh');
    old.complete([event('old', start, end)]);
    await first;
    expect(
      (await DeviceCalendarReadService.readEvents(
        start: start,
        end: end,
      )).single.id,
      'fresh',
    );
    expect(reads, 2);
  });
  test('跨午夜、全天及瞬时事件适配；边界外事件被过滤', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'checkPermission') return true;
          return [
            event(
              'cross',
              start.subtract(const Duration(hours: 1)),
              start.add(const Duration(hours: 9)),
            ),
            event('all-day', start, end, allDay: true),
            event(
              'instant',
              start.add(const Duration(hours: 10)),
              start.add(const Duration(hours: 10)),
            ),
            event('outside', end, end.add(const Duration(hours: 1))),
          ];
        });
    final events = await DeviceCalendarReadService.readEvents(
      start: start,
      end: end,
    );
    expect(events.map((e) => e.id), ['cross', 'all-day', 'instant']);
    expect(events[1].allDay, isTrue);
    expect(
      events[2].end.difference(events[2].start),
      const Duration(minutes: 1),
    );
  });
  test('不支持平台不调用桥接、不请求权限', () async {
    DeviceCalendarReadService.debugIsSupportedOverride = false;
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          calls++;
          return true;
        });
    expect(
      await DeviceCalendarReadService.readEvents(
        start: start,
        end: end,
        forceRefresh: true,
      ),
      isEmpty,
    );
    expect(calls, 0);
  });
}
