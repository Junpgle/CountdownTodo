import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:countdown_todo/features/thirty_day_challenge/models/cloud_challenge.dart';
import 'package:countdown_todo/features/thirty_day_challenge/services/cloud_challenge_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('解析仓库根目录的云端挑战清单并生成本地草稿', () {
    final catalog = CloudChallengeCatalog.fromJson({
      'version': 1,
      'updated_at': '2026-08-03',
      'challenges': [
        {
          'id': 'focus-3',
          'title': '三次专注',
          'description': '把注意力收回来',
          'tags': ['专注'],
          'tasks': ['完成一次 25 分钟专注', '记录一次中断原因'],
        },
        {'id': 'broken', 'title': '缺少任务'},
      ],
    });

    expect(catalog.challenges, hasLength(1));
    expect(catalog.challenges.single.tags, ['专注']);
    expect(catalog.challenges.single.toDraft().taskTitles, [
      '完成一次 25 分钟专注',
      '记录一次中断原因',
    ]);
  });

  test('通过 HTTP 响应读取 JSON 清单', () async {
    final client = MockClient((_) async {
      return http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'version': 1,
            'challenges': [
              {
                'id': 'one',
                'title': '一项挑战',
                'tasks': ['完成一件事'],
              },
            ],
          }),
        ),
        200,
      );
    });
    final service = CloudChallengeService(client: client);

    final catalog = await service.fetchCatalog();

    expect(catalog.challenges.single.title, '一项挑战');
    service.dispose();
  });

  test('成功获取后会缓存清单，并能在一天内读取缓存', () async {
    final client = MockClient((_) async {
      return http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'version': 2,
            'updated_at': '2026-08-03',
            'challenges': [
              {
                'id': 'cached',
                'title': '缓存挑战',
                'tasks': ['完成一项任务'],
              },
            ],
          }),
        ),
        200,
      );
    });
    final service = CloudChallengeService(client: client);

    final catalog = await service.fetchCatalog();
    final cached = await service.readCachedCatalog();

    expect(catalog.version, 2);
    expect(cached, isNotNull);
    expect(cached!.catalog.challenges.single.title, '缓存挑战');
    expect(service.isCacheFresh(cached), isTrue);
    service.dispose();
  });

  test('超过一天的缓存会被视为需要刷新', () async {
    final client = MockClient((_) async {
      return http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'version': 1,
            'challenges': [
              {
                'id': 'old',
                'title': '旧挑战',
                'tasks': ['继续坚持'],
              },
            ],
          }),
        ),
        200,
      );
    });
    final service = CloudChallengeService(client: client);
    final cached = CachedCloudChallengeCatalog(
      catalog: await service.fetchCatalog(),
      cachedAt: DateTime.utc(2026, 8, 1),
    );

    expect(
      service.isCacheFresh(cached, now: DateTime.utc(2026, 8, 3)),
      isFalse,
    );
    service.dispose();
  });

  test('HTTP 错误不会被当成空挑战清单', () {
    final response = http.Response('not found', 404);

    expect(
      () => CloudChallengeCatalog.fromResponse(response),
      throwsA(isA<FormatException>()),
    );
  });
}
