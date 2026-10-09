import 'dart:convert';
import 'dart:io';

import 'package:countdown_todo/features/thirty_day_challenge/models/cloud_challenge.dart';
import 'package:countdown_todo/features/thirty_day_challenge/services/cloud_challenge_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _cacheKey = 'thirty_day_cloud_challenge_catalog_v1';

Map<String, dynamic> _catalog(String title) => {
  'format': 'countdowntodo.challenge_catalog',
  'version': 1,
  'updated_at': '2026-10-09T00:00:00Z',
  'challenges': [
    {
      'id': 'sample',
      'title': title,
      'description': 'sample description',
      'tags': <String>[],
      'tasks': ['task'],
    },
  ],
};

String _cachedEnvelope(DateTime cachedAt, String title) => jsonEncode({
  'cached_at': cachedAt.toUtc().toIso8601String(),
  'catalog': _catalog(title),
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Cloud challenge search catalog cache', () {
    test('uses a fresh cache without a network request', () async {
      SharedPreferences.setMockInitialValues({
        _cacheKey: _cachedEnvelope(DateTime.now(), 'cached title'),
      });
      var requests = 0;
      final service = CloudChallengeService(
        client: MockClient((_) async {
          requests++;
          throw const SocketException('unexpected network request');
        }),
      );

      final catalog = await service.loadCatalogForSearch();

      expect(catalog.challenges.single.title, 'cached title');
      expect(requests, 0);
      service.dispose();
    });

    test(
      'refreshes an expired cache before returning search results',
      () async {
        SharedPreferences.setMockInitialValues({
          _cacheKey: _cachedEnvelope(
            DateTime.now().subtract(const Duration(days: 2)),
            'expired title',
          ),
        });
        var requests = 0;
        final service = CloudChallengeService(
          client: MockClient((request) async {
            requests++;
            expect(request.url, Uri.parse(CloudChallengeService.catalogUrl));
            return http.Response(jsonEncode(_catalog('refreshed title')), 200);
          }),
        );

        final catalog = await service.loadCatalogForSearch();

        expect(catalog.challenges.single.title, 'refreshed title');
        expect(requests, 1);
        service.dispose();
      },
    );

    test('keeps expired cached results available when refresh fails', () async {
      SharedPreferences.setMockInitialValues({
        _cacheKey: _cachedEnvelope(
          DateTime.now().subtract(const Duration(days: 2)),
          'stale but usable',
        ),
      });
      final service = CloudChallengeService(
        client: MockClient((_) async => throw const SocketException('offline')),
      );

      final catalog = await service.loadCatalogForSearch();

      expect(catalog.challenges.single.title, 'stale but usable');
      service.dispose();
    });

    test('treats a future-dated cache as stale', () {
      final catalog = CloudChallengeService(
        client: MockClient((_) async => http.Response('', 500)),
      );
      final cached = CachedCloudChallengeCatalog(
        catalog: CloudChallengeCatalog.fromJson(_catalog('future title')),
        cachedAt: DateTime.now().toUtc().add(const Duration(days: 2)),
      );

      expect(catalog.isCacheFresh(cached), isFalse);
      catalog.dispose();
    });
  });
}
