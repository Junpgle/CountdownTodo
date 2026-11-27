import 'package:countdown_todo/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late String originalBaseUrl;

  setUp(() {
    originalBaseUrl = ApiService.baseUrl;
    ApiService.clearBaseUrlOverride();
    ApiService.resetCloudflareFallbackForTest();
  });

  tearDown(() {
    ApiService.resetCloudflareFallbackForTest();
    ApiService.clearBaseUrlOverride();
    ApiService.baseUrl = originalBaseUrl;
  });

  test('assigns stable namespaces to server environments', () {
    ApiService.baseUrl = ApiService.aliyunProdUrl;
    expect(ApiService.syncServerKey, 'aliyun');

    ApiService.baseUrl = ApiService.aliyunTestUrl;
    expect(ApiService.syncServerKey, 'aliyun_test');

    ApiService.baseUrl = ApiService.legacyCloudflareUrl;
    expect(ApiService.syncServerKey, 'cf');

    ApiService.baseUrl = ApiService.aliyunCloudflareUrl;
    expect(ApiService.syncServerKey, 'aliyun');
  });

  test('maps both persisted route choices to the current Aliyun endpoints', () {
    ApiService.setServerChoice(ApiService.serverChoiceAliyunDirect);
    expect(ApiService.effectiveBaseUrl, ApiService.aliyunProdUrl);

    ApiService.setServerChoice(ApiService.serverChoiceCloudflare);
    expect(ApiService.effectiveBaseUrl, ApiService.aliyunCloudflareUrl);

    expect(
      ApiService.normalizeServerChoice('unknown'),
      ApiService.serverChoiceAliyunDirect,
    );
  });

  test('isolates custom endpoints from known environments', () {
    ApiService.setBaseUrlOverride('http://127.0.0.1:8080');
    expect(ApiService.syncServerKey, startsWith('custom_'));
  });

  test('environment checks use the effective endpoint override', () {
    ApiService.baseUrl = ApiService.aliyunProdUrl;
    ApiService.setBaseUrlOverride(ApiService.aliyunTestUrl);

    expect(ApiService.isTestServer, isTrue);
  });

  test(
    'team fetch distinguishes a successful empty list from request failure',
    () async {
      final emptyResult = await ApiService.fetchTeamsWithStatus(
        client: MockClient((_) async => http.Response('{"teams":[]}', 200)),
      );
      final failedResult = await ApiService.fetchTeamsWithStatus(
        client: MockClient(
          (_) async => http.Response('{"error":"offline"}', 503),
        ),
      );
      final rejectedResult = await ApiService.fetchTeamsWithStatus(
        client: MockClient(
          (_) async => http.Response('{"success":false,"teams":[]}', 200),
        ),
      );
      final malformedResult = await ApiService.fetchTeamsWithStatus(
        client: MockClient((_) async => http.Response('{"teams":{}}', 200)),
      );

      expect(emptyResult.succeeded, isTrue);
      expect(emptyResult.teams, isEmpty);
      expect(failedResult.succeeded, isFalse);
      expect(failedResult.teams, isEmpty);
      expect(rejectedResult.succeeded, isFalse);
      expect(rejectedResult.teams, isEmpty);
      expect(malformedResult.succeeded, isFalse);
      expect(malformedResult.teams, isEmpty);
    },
  );

  test(
    'does not fall back from Cloudflare to direct before 2027-01-16',
    () async {
      ApiService.setServerChoice(ApiService.serverChoiceCloudflare);
      ApiService.clock = () => DateTime(2027, 1, 15, 23, 59, 59);

      final requestedHosts = <String>[];
      final result = await ApiService.fetchTeamsWithStatus(
        client: MockClient((request) async {
          requestedHosts.add(request.url.host);
          throw http.ClientException('DNS lookup failed', request.url);
        }),
      );

      expect(result.succeeded, isFalse);
      expect(requestedHosts, ['api-cdt.junpgle.me']);
      expect(ApiService.isCloudflareFallbackActive, isFalse);
      expect(ApiService.effectiveBaseUrl, ApiService.aliyunCloudflareUrl);
    },
  );

  test(
    'falls back from Cloudflare to direct Aliyun after 2027-01-15 and sticks for subsequent requests',
    () async {
      ApiService.setServerChoice(ApiService.serverChoiceCloudflare);
      ApiService.clock = () => DateTime(2027, 1, 16, 0, 0, 0);

      final requestedUrls = <String>[];
      final client = MockClient((request) async {
        requestedUrls.add(request.url.toString());
        if (request.url.host == 'api-cdt.junpgle.me') {
          throw http.ClientException('DNS lookup failed', request.url);
        }
        return http.Response('{"teams":[]}', 200);
      });

      final first = await ApiService.fetchTeamsWithStatus(client: client);
      expect(first.succeeded, isTrue);
      expect(ApiService.isCloudflareFallbackActive, isTrue);
      expect(ApiService.effectiveBaseUrl, ApiService.aliyunProdUrl);
      expect(ApiService.syncServerKey, 'aliyun');
      expect(requestedUrls, [
        'https://api-cdt.junpgle.me/api/teams',
        'http://101.200.13.100:8082/api/teams',
      ]);

      requestedUrls.clear();
      final second = await ApiService.fetchTeamsWithStatus(client: client);
      expect(second.succeeded, isTrue);
      expect(requestedUrls, ['http://101.200.13.100:8082/api/teams']);
    },
  );

  test(
    'does not latch Cloudflare fallback when direct endpoint is also offline',
    () async {
      ApiService.setServerChoice(ApiService.serverChoiceCloudflare);
      ApiService.clock = () => DateTime(2027, 2, 1);

      final requestedHosts = <String>[];
      final result = await ApiService.fetchTeamsWithStatus(
        client: MockClient((request) async {
          requestedHosts.add(request.url.host);
          throw http.ClientException('Device offline', request.url);
        }),
      );

      expect(result.succeeded, isFalse);
      expect(requestedHosts, ['api-cdt.junpgle.me', '101.200.13.100']);
      expect(ApiService.isCloudflareFallbackActive, isFalse);
      expect(ApiService.effectiveBaseUrl, ApiService.aliyunCloudflareUrl);
    },
  );
}
