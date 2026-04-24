import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
// Import for Android features.
import 'package:webview_flutter_android/webview_flutter_android.dart' as wv_android;
// Import for iOS features.
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
// Import for Windows features.
import 'package:webview_win_floating/webview_win_floating.dart';
import 'dart:convert'; // 🚀 添加了 jsonDecode 必需的包
import '../../storage_service.dart';


class CourseWebViewScreen extends StatefulWidget {
  final String initialUrl;

  const CourseWebViewScreen({
    super.key,
    this.initialUrl = 'https://www.bing.com', // Default to a search engine if none provided
  });

  @override
  State<CourseWebViewScreen> createState() => _CourseWebViewScreenState();
}

class _CourseWebViewScreenState extends State<CourseWebViewScreen> {
  WebViewController? _controller;
  bool _isLoading = true;
  String _currentTitle = '教务系统登录';
  double _progress = 0;

  bool get _isSupported =>
      Theme.of(context).platform == TargetPlatform.android ||
          Theme.of(context).platform == TargetPlatform.iOS ||
          Theme.of(context).platform == TargetPlatform.windows;

  late TextEditingController _urlController;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.initialUrl);
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller == null && _isSupported) {
      _initController();
    }
  }

  void _initController() {
    // Automatically uses the registered platform implementation (Android/iOS/Windows).
    late final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
      );
    } else if (Theme.of(context).platform == TargetPlatform.windows) {
      params = const WindowsWebViewControllerCreationParams();
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    final WebViewController controller =
    WebViewController.fromPlatformCreationParams(params);

    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            setState(() {
              _progress = progress / 100;
            });
          },
          onPageStarted: (String url) {
            setState(() {
              _isLoading = true;
            });
          },
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false;
              _urlController.text = url; // 🚀 同步更新地址栏
            });
            _updateTitle();
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint('WebView error: ${error.description}');
          },
          onNavigationRequest: (NavigationRequest request) {
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.initialUrl));

    if (controller.platform is wv_android.AndroidWebViewController) {
      wv_android.AndroidWebViewController.enableDebugging(true);
      (controller.platform as wv_android.AndroidWebViewController)
          .setMediaPlaybackRequiresUserGesture(false);
    }

    setState(() {
      _controller = controller;
    });
  }


  Future<void> _updateTitle() async {
    final title = await _controller?.getTitle();
    if (mounted && title != null && title.isNotEmpty) {
      setState(() {
        _currentTitle = title;
      });
    }
  }

  Future<void> _captureHtml() async {
    if (_controller == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final currentUrl = await _controller?.currentUrl();
      debugPrint('[WebViewCapture] Current URL: $currentUrl');

      if (currentUrl != null && currentUrl.contains('hfut.edu.cn')) {
        debugPrint('[WebViewCapture] Detected HFUT, injecting JS to fetch datum API...');

        // 🚀 终极方案：在 WebView 内部直接构造 fetch 请求，利用自带身份验证，并传入必需参数！
        // 使用 async IIFE (立即调用的异步函数)，webview_flutter 会等待其 Promise 返回。
        final Object? jsResultObj = await _controller?.runJavaScriptReturningResult('''
          (async function() {
            try {
                // 1. 从当前页面的 HTML 源码中正则匹配出必需的请求参数
                let html = document.documentElement.outerHTML;
                let semMatch = html.match(/semesterId:\\s*(\\d+)/);
                let dataMatch = html.match(/dataId:\\s*(\\d+)/);
                
                // 提取 contextPath (例如 /eams5-student)
                let contextMatch = html.match(/window\\.CONTEXT_PATH\\s*=\\s*['"]([^'"]*)['"]/);
                let contextPath = contextMatch ? contextMatch[1] : '/eams5-student';

                // 如果找到了核心参数，则发起真实的 POST 请求
                if (semMatch && dataMatch) {
                    let response = await fetch(contextPath + "/ws/schedule-table/datum", {
                        method: 'POST',
                        headers: {
                            'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
                            'X-Requested-With': 'XMLHttpRequest'
                        },
                        // 🚀 这里就是之前 Dart http.post 缺失的关键 Payload！
                        body: 'bizTypeId=2&semesterId=' + semMatch[1] + '&dataId=' + dataMatch[1]
                    });
                    
                    let data = await response.json();
                    return JSON.stringify(data); // 完美拿到包含教师的 JSON
                } else {
                    return "ERROR: 找不到 semesterId 或 dataId";
                }
            } catch (e) {
                return "ERROR: " + e.toString();
            }
          })();
        ''');

        String? jsResult = jsResultObj?.toString();

        // 🚀 webview_flutter 在返回字符串时可能会加上额外的引号和转义符，这里进行安全脱壳
        if (jsResult != null && jsResult.startsWith('"') && jsResult.endsWith('"')) {
          // 修复点：使用局部非空变量暂存，避免在 try/catch 块中因为重赋值导致的空安全(Null-Safety)报错
          final String nonNullResult = jsResult;
          try {
            jsResult = jsonDecode(nonNullResult) as String;
          } catch (e) {
            jsResult = nonNullResult.substring(1, nonNullResult.length - 1).replaceAll(r'\"', '"');
          }
        }

        // 校验我们是否拿到了含有教师信息的真实 JSON 数据
        if (jsResult != null && jsResult.contains('lessonList')) {
          debugPrint('[WebViewCapture] Direct JS Fetch Success! Length: ${jsResult.length}');
          await StorageService.saveLastCourseImportUrl(currentUrl);

          if (mounted) {
            // 直接将这段纯正的 JSON 交给 hfut_parser 即可完美提取教师
            Navigator.pop(context, jsResult);
          }
          return; // 成功截获，退出函数，不走 HTML 降级
        } else {
          debugPrint('[WebViewCapture] JS Fetch failed or returned error: $jsResult');
        }
      }

      // --- 兜底方案：抓取全页 HTML 源码 ---
      debugPrint('[WebViewCapture] Falling back to HTML capture...');
      final Object? htmlResult = await _controller?.runJavaScriptReturningResult(
          'document.documentElement.outerHTML'
      );

      if (htmlResult == null) return;
      String html = htmlResult.toString();

      // runJavaScriptReturningResult might return a string with quotes if it's a JSON string
      String processedHtml = html;
      if (processedHtml.startsWith('"') && processedHtml.endsWith('"')) {
        try {
          processedHtml = jsonDecode(processedHtml) as String;
        } catch (e) {
          processedHtml = processedHtml.substring(1, processedHtml.length - 1);
          processedHtml = processedHtml.replaceAll('\\u003C', '<');
          processedHtml = processedHtml.replaceAll('\\u003E', '>');
          processedHtml = processedHtml.replaceAll('\\"', '"');
          processedHtml = processedHtml.replaceAll('\\\\', '\\');
        }
      }

      if (mounted) {
        // 🚀 保存当前链接供下次快捷抓取
        final currentUrl = await _controller?.currentUrl();
        if (currentUrl != null) {
          await StorageService.saveLastCourseImportUrl(currentUrl);
        }
        Navigator.pop(context, processedHtml);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('抓取失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Container(
          height: 40,
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(20),
          ),
          child: TextField(
            controller: _urlController, // 🚀 绑定 Controller
            onSubmitted: (value) {
              String url = value.trim();
              if (url.isNotEmpty) {
                if (!url.startsWith('http')) {
                  url = 'https://$url';
                }
                _controller?.loadRequest(Uri.parse(url));
              }
            },
            decoration: InputDecoration(
              hintText: '输入教务系统网址...',
              hintStyle: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
              prefixIcon: const Icon(Icons.language, size: 18),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
            style: const TextStyle(fontSize: 14),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _controller?.reload(),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: _progress < 1.0
              ? LinearProgressIndicator(value: _progress, minHeight: 2)
              : const SizedBox.shrink(),
        ),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.5),
              border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 20, color: colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '1. 请先登录并在浏览器中打开【我的课表】页面',
                        style: TextStyle(fontSize: 13, color: colorScheme.onPrimaryContainer, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '2. 待页面完全加载出网格或列表后，点击下方抓取',
                        style: TextStyle(fontSize: 12, color: colorScheme.onPrimaryContainer.withValues(alpha: 0.8)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isSupported
                ? (_controller != null
                ? WebViewWidget(controller: _controller!)
                : const Center(child: CircularProgressIndicator()))
                : const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 48, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('当前平台暂不支持内置浏览器'),
                  Text('此功能主要适配 Android 和 iOS ', style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isLoading ? null : _captureHtml,
        icon: _isLoading
            ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)
        )
            : const Icon(Icons.auto_fix_high),
        label: Text(_isLoading ? '正处理网页内容...' : '抓取当前页面的课程表'),
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        elevation: 8,
      ),
    );
  }
}