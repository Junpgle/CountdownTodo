import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import 'api_service.dart';

/// 访问 GitHub 公开资源的统一入口。
///
/// GitHub 资源默认先直连；直连失败后再通过阿里云服务端中转。
/// 服务端负责白名单校验、热缓存、GitHub 重定向和大文件流式转发。
class GitHubResourceService {
  GitHubResourceService({http.Client? client})
      : _client = client ?? http.Client();

  static const String resourcePath = '/api/github/resource';

  static const Set<String> _githubHosts = {
    'api.github.com',
    'raw.githubusercontent.com',
  };

  final http.Client _client;

  /// 判断一个地址是否应该走 GitHub 中转。
  static bool isGitHubUri(Uri uri) {
    return uri.scheme == 'https' &&
        _githubHosts.contains(uri.host.toLowerCase());
  }

  /// 服务端中转只接受小型 JSON。图片、Markdown 和安装包保持直连。
  static bool isJsonResourceUri(Uri uri) {
    if (!isGitHubUri(uri)) return false;
    if (uri.host.toLowerCase() == 'api.github.com') return true;
    return uri.path.toLowerCase().endsWith('.json');
  }

  /// 把 GitHub 地址转换为当前环境对应的阿里云接口地址。
  /// 非 GitHub 地址原样返回，便于调用方统一使用此方法。
  static Uri proxyUri(Uri uri) {
    if (!isJsonResourceUri(uri)) return uri;

    // Web 端必须使用 HTTPS 的 Zero Trust 域名；原生端统一访问正式服 8082。
    // debug 服务器不运行 GitHub 资源中转，避免和正式服重复预热、抢占资源。
    final resourceBaseUrl = kIsWeb
        ? ApiService.webAliyunProxyUrl
        : ApiService.aliyunProdUrl;
    final base = Uri.parse(resourceBaseUrl);
    final basePath = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    return base.replace(
      path: '$basePath$resourcePath',
      queryParameters: {'url': uri.toString()},
    );
  }

  /// 显式生成中转 URL。需要“直连优先”的图片或下载请使用
  /// [GitHubResourceImage] 或 [get]/[sendGet]。
  static String proxyUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    return proxyUri(uri).toString();
  }

  /// 统一 GET。小型 JSON 直连失败后改走阿里云；图片和其他资源保持直连。
  Future<http.Response> get(
    Uri uri, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final requestHeaders = <String, String>{
      'Accept': 'application/json, text/plain, */*',
      ...?headers,
    };
    if (!isJsonResourceUri(uri)) {
      return _client.get(uri, headers: requestHeaders).timeout(timeout);
    }

    try {
      final response = await _client.get(uri, headers: requestHeaders).timeout(
            _directTimeout(timeout),
          );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return response;
      }
    } catch (_) {
      // 直连失败后进入阿里云中转。
    }

    return _client.get(proxyUri(uri), headers: requestHeaders).timeout(timeout);
  }

  /// 流式 GET，供 Gitee 安装包等大文件使用；GitHub 大文件不会中转。
  Future<http.StreamedResponse> sendGet(
    Uri uri, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final requestHeaders = <String, String>{
      'Accept': 'application/octet-stream, */*',
      ...?headers,
    };

    if (!isJsonResourceUri(uri)) {
      return _send(uri, requestHeaders, timeout);
    }

    try {
      final response =
          await _send(uri, requestHeaders, _directTimeout(timeout));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return response;
      }
      await response.stream.drain<void>();
    } catch (_) {
      // 直连失败后进入阿里云中转。
    }

    return _send(proxyUri(uri), requestHeaders, timeout);
  }

  Future<http.StreamedResponse> _send(
    Uri uri,
    Map<String, String> headers,
    Duration timeout,
  ) {
    final request = http.Request('GET', uri)..headers.addAll(headers);
    return _client.send(request).timeout(timeout);
  }

  static Duration _directTimeout(Duration timeout) {
    const maxDirectWait = Duration(seconds: 6);
    return timeout < maxDirectWait ? timeout : maxDirectWait;
  }

  Future<http.Response> getUrl(
    String url, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 12),
  }) {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return Future.error(FormatException('无效 URL: $url'));
    }
    return get(uri, headers: headers, timeout: timeout);
  }

  void dispose() => _client.close();
}

/// 需要“直连失败后再中转”的图片组件。
class GitHubResourceImage extends StatefulWidget {
  const GitHubResourceImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit,
    this.errorBuilder,
  });

  final String url;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final ImageErrorWidgetBuilder? errorBuilder;

  @override
  State<GitHubResourceImage> createState() => _GitHubResourceImageState();
}

class _GitHubResourceImageState extends State<GitHubResourceImage> {
  late GitHubResourceService _resourceService;
  late Future<Uint8List> _imageFuture;

  @override
  void initState() {
    super.initState();
    _resourceService = GitHubResourceService();
    _imageFuture = _load();
  }

  @override
  void didUpdateWidget(covariant GitHubResourceImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _imageFuture = _load();
    }
  }

  @override
  void dispose() {
    _resourceService.dispose();
    super.dispose();
  }

  Future<Uint8List> _load() async {
    final response = await _resourceService.get(Uri.parse(widget.url));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('图片请求失败: HTTP ${response.statusCode}');
    }
    return response.bodyBytes;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _imageFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return widget.errorBuilder?.call(
                context,
                snapshot.error!,
                snapshot.stackTrace ?? StackTrace.current,
              ) ??
              const SizedBox.shrink();
        }
        if (!snapshot.hasData) {
          return SizedBox(width: widget.width, height: widget.height);
        }
        return Image.memory(
          snapshot.data!,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          errorBuilder: widget.errorBuilder,
        );
      },
    );
  }
}
