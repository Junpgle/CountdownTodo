import 'package:countdown_todo/services/api_service.dart';
import 'package:countdown_todo/services/github_resource_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('GitHubResourceService', () {
    final originalBaseUrl = ApiService.baseUrl;

    setUp(() {
      ApiService.clearBaseUrlOverride();
      ApiService.baseUrl = ApiService.aliyunProdUrl;
    });

    tearDown(() {
      ApiService.clearBaseUrlOverride();
      ApiService.baseUrl = originalBaseUrl;
    });

    test('识别 GitHub 资源地址', () {
      expect(
        GitHubResourceService.isGitHubUri(
          Uri.parse(
            'https://raw.githubusercontent.com/Junpgle/CountdownTodo/master/file.json',
          ),
        ),
        isTrue,
      );
      expect(
        GitHubResourceService.isGitHubUri(
          Uri.parse('https://example.com/file.json'),
        ),
        isFalse,
      );
    });

    test('将 GitHub URL 改写为阿里云中转地址并保留原始 URL', () {
      final proxy = GitHubResourceService.proxyUri(
        Uri.parse(
          'https://raw.githubusercontent.com/Junpgle/CountdownTodo/master/file.json',
        ),
      );

      expect(
        proxy.toString(),
        startsWith('${ApiService.aliyunProdUrl}/api/github/resource?'),
      );
      expect(
        proxy.queryParameters['url'],
        'https://raw.githubusercontent.com/Junpgle/CountdownTodo/master/file.json',
      );
    });

    test('非 GitHub URL 不改写', () {
      final uri = Uri.parse('https://bing.biturl.top/?format=json');
      expect(GitHubResourceService.proxyUri(uri), uri);
    });

    test('中转只针对 JSON，图片保持直连', () {
      final jsonUri = Uri.parse(
        'https://raw.githubusercontent.com/Junpgle/CountdownTodo/master/file.json',
      );
      final imageUri = Uri.parse(
        'https://raw.githubusercontent.com/Junpgle/CountdownTodo/master/splash/qingming.jpg',
      );

      expect(GitHubResourceService.isJsonResourceUri(jsonUri), isTrue);
      expect(GitHubResourceService.isJsonResourceUri(imageUri), isFalse);
      expect(GitHubResourceService.proxyUri(imageUri), imageUri);
    });

    test('直连成功时不请求中转', () async {
      final requests = <Uri>[];
      final client = MockClient((request) async {
        requests.add(request.url);
        return http.Response('direct', 200);
      });
      final service = GitHubResourceService(client: client);

      final response = await service.get(
        Uri.parse(
          'https://raw.githubusercontent.com/Junpgle/CountdownTodo/master/file.json',
        ),
      );

      expect(response.statusCode, 200);
      expect(requests, [
        Uri.parse(
          'https://raw.githubusercontent.com/Junpgle/CountdownTodo/master/file.json',
        ),
      ]);
      service.dispose();
    });

    test('直连失败时再请求阿里云中转', () async {
      final requests = <Uri>[];
      final client = MockClient((request) async {
        requests.add(request.url);
        return http.Response('', requests.length == 1 ? 404 : 200);
      });
      final service = GitHubResourceService(client: client);

      final response = await service.get(
        Uri.parse(
          'https://raw.githubusercontent.com/Junpgle/CountdownTodo/master/file.json',
        ),
      );

      expect(response.statusCode, 200);
      expect(requests, hasLength(2));
      expect(requests.first.host, 'raw.githubusercontent.com');
      expect(requests.last.path, GitHubResourceService.resourcePath);
      service.dispose();
    });
  });
}
