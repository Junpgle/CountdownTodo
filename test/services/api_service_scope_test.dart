import 'package:countdown_todo/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late String originalBaseUrl;

  setUp(() {
    originalBaseUrl = ApiService.baseUrl;
    ApiService.clearBaseUrlOverride();
  });

  tearDown(() {
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

    expect(ApiService.normalizeServerChoice('unknown'),
        ApiService.serverChoiceAliyunDirect);
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
          (_) async => http.Response(
            '{"success":false,"teams":[]}',
            200,
          ),
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
}
