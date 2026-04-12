import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
// Import for Android features.
import 'package:webview_flutter_android/webview_flutter_android.dart';
// Import for iOS features.
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
// Import for Windows features.
import 'package:webview_win_floating/webview_win_floating.dart';
import 'dart:io';
import '../../storage_service.dart';

class CourseWebViewScreen extends StatefulWidget {
  final String initialUrl;

  const CourseWebViewScreen({
    Key? key,
    this.initialUrl = 'https://www.bing.com', // Default to a search engine if none provided
  }) : super(key: key);

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

    if (controller.platform is AndroidWebViewController) {
      AndroidWebViewController.enableDebugging(true);
      (controller.platform as AndroidWebViewController)
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
      // 🚀 核心改进：深度扫描浏览器内存中的课表变量
      final String? jsData = await _controller?.runJavaScriptReturningResult('''
        (function() {
          try {
            // 定义探测函数
            function probe() {
              // 1. 尝试已知的合工大全局变量
              if (typeof lessons !== 'undefined' && typeof schedules !== 'undefined') {
                return { lessonList: lessons, scheduleList: schedules };
              }
              
              // 2. 深度扫描 window 对象中的所有可枚举属性
              for (var key in window) {
                try {
                  var obj = window[key];
                  if (obj && typeof obj === 'object') {
                    // 如果对象包含 result.lessonList (合工大 EAMS 特征)
                    if (obj.result && obj.result.lessonList && obj.result.scheduleList) {
                      return obj.result;
                    }
                    // 如果对象本身就是 lessonList
                    if (obj.lessonList && obj.scheduleList) {
                      return obj;
                    }
                  }
                } catch(e) {}
              }
              return null;
            }

            var result = probe();
            if (result) {
              console.log("JS Spy: Found data structure!");
              return JSON.stringify({ "result": result });
            }
          } catch (e) {}
          return "NOT_FOUND";
        })()
      ''') as String?;

      debugPrint('[WebViewCapture] JS Spy Result: ${jsData?.substring(0, (jsData?.length ?? 0) > 20 ? 20 : (jsData?.length ?? 0))}');

      // 如果 JS 抓取到了结构化数据，优先使用
      if (jsData != null && jsData != '"NOT_FOUND"' && jsData != '""' && jsData != 'null') {
        String cleanJson = jsData;
        if (cleanJson.startsWith('"') && cleanJson.endsWith('"')) {
          cleanJson = cleanJson.substring(1, cleanJson.length - 1).replaceAll(r'\"', '"');
        }
        debugPrint('[WebViewCapture] JS Spy SUCCESS! Length: ${cleanJson.length}');
        
        // 🚀 保存当前链接供下次快捷抓取
        final currentUrl = await _controller?.currentUrl();
        if (currentUrl != null) {
          await StorageService.saveLastCourseImportUrl(currentUrl);
        }
        
        Navigator.pop(context, cleanJson);
        return;
      }
      debugPrint('[WebViewCapture] JS Spy FAILED. Falling back to HTML capture...');

      // 兜底方案：抓取全页 HTML 源码
      final Object? htmlResult = await _controller?.runJavaScriptReturningResult(
        'document.documentElement.outerHTML'
      );
      
      if (htmlResult == null) return;
      String html = htmlResult.toString();
      
      // runJavaScriptReturningResult might return a string with quotes if it's a JSON string
      String processedHtml = html;
      if (processedHtml.startsWith('"') && processedHtml.endsWith('"')) {
        processedHtml = processedHtml.substring(1, processedHtml.length - 1);
        processedHtml = processedHtml.replaceAll('\\u003C', '<');
        processedHtml = processedHtml.replaceAll('\\u003E', '>');
        processedHtml = processedHtml.replaceAll('\\"', '"');
        processedHtml = processedHtml.replaceAll('\\\\', '\\');
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
            color: colorScheme.surfaceVariant.withOpacity(0.5),
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
              color: colorScheme.primaryContainer.withOpacity(0.5),
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
                        style: TextStyle(fontSize: 12, color: colorScheme.onPrimaryContainer.withOpacity(0.8)),
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
