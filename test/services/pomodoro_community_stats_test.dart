import 'package:countdown_todo/services/pomodoro_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    PomodoroService.clearCommunityStatsCacheForTest();
  });

  test('PomodoroCommunityStats.tryParse returns null when has_data is false or values invalid', () {
    expect(
      PomodoroCommunityStats.tryParse({
        'has_data': false,
        'avg_seconds': 0,
        'total_seconds': 0,
        'active_users': 0,
      }),
      isNull,
    );

    expect(
      PomodoroCommunityStats.tryParse({
        'has_data': true,
        'avg_seconds': 0,
        'total_seconds': 0,
        'active_users': 2,
      }),
      isNull,
    );

    expect(
      PomodoroCommunityStats.tryParse({
        'has_data': true,
        'avg_seconds': 1500,
        'total_seconds': 1500,
        'active_users': 0,
      }),
      isNull,
    );
  });

  test('PomodoroCommunityStats.tryParse parses valid numeric and string payloads', () {
    final parsed = PomodoroCommunityStats.tryParse({
      'has_data': true,
      'avg_seconds': 2700,
      'total_seconds': 5400.4,
      'active_users': '2',
    });

    expect(parsed, isNotNull);
    expect(parsed!.avgSeconds, 2700);
    expect(parsed.totalSeconds, 5400);
    expect(parsed.activeUsers, 2);
  });

  test('getTodayCommunityStats caches within 60s and refreshes on forceRefresh or day change', () async {
    var calls = 0;
    Future<Map<String, dynamic>?> fakeFetcher(int fromMs, int toMs) async {
      calls++;
      return {
        'has_data': true,
        'avg_seconds': 1500 * calls,
        'total_seconds': 3000 * calls,
        'active_users': 2,
      };
    }

    final t0 = DateTime(2026, 11, 19, 10, 0);
    final first = await PomodoroService.getTodayCommunityStats(
      now: t0,
      fetcher: fakeFetcher,
    );
    final second = await PomodoroService.getTodayCommunityStats(
      now: t0.add(const Duration(seconds: 30)),
      fetcher: fakeFetcher,
    );

    expect(calls, 1);
    expect(first?.avgSeconds, 1500);
    expect(second?.avgSeconds, 1500);

    final forced = await PomodoroService.getTodayCommunityStats(
      now: t0.add(const Duration(seconds: 35)),
      forceRefresh: true,
      fetcher: fakeFetcher,
    );
    expect(calls, 2);
    expect(forced?.avgSeconds, 3000);
  });

  test('getTodayCommunityStats returns null gracefully when fetcher returns null', () async {
    final res = await PomodoroService.getTodayCommunityStats(
      now: DateTime(2026, 11, 19, 10, 0),
      fetcher: (_, _) async => null,
    );
    expect(res, isNull);
  });
}
