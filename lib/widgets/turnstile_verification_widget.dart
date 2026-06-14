import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart'
    as wv_android;
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import '../services/environment_service.dart';

/// Cloudflare Turnstile 人机验证组件
///
/// 超时策略：
/// - 加载超时（15s）仅覆盖 WebView 页面加载 + Turnstile 脚本加载 + 组件渲染
/// - 一旦收到 rendered 事件，立即取消加载超时
/// - 用户交互时间（点击验证框）不计入超时
class TurnstileVerificationWidget extends StatefulWidget {
  /// 验证成功回调，返回 turnstile token
  final ValueChanged<String> onVerified;

  /// 验证过期回调
  final VoidCallback? onExpired;

  /// 验证失败回调
  final ValueChanged<String>? onError;

  /// 是否禁用验证（例如登录/注册进行中）
  final bool disabled;

  /// 是否深色模式
  final bool isDarkMode;

  /// Turnstile action（login / register），用于后端校验
  final String action;

  /// 组件高度（登录页 ~130，注册页 ~150）
  final double height;

  const TurnstileVerificationWidget({
    super.key,
    required this.onVerified,
    this.onExpired,
    this.onError,
    this.disabled = false,
    this.isDarkMode = false,
    this.action = 'verify',
    this.height = 130,
  });

  @override
  State<TurnstileVerificationWidget> createState() =>
      _TurnstileVerificationWidgetState();
}

class _TurnstileVerificationWidgetState
    extends State<TurnstileVerificationWidget> {
  WebViewController? _webViewController;

  /// 是否正在加载页面（WebView 页面 + Turnstile 脚本 + 渲染）
  bool _isLoadingPage = true;

  /// Turnstile 组件是否已渲染完成
  bool _isRendered = false;

  /// 是否已验证成功
  bool _isVerified = false;

  /// 是否有错误
  bool _hasError = false;

  String? _errorMessage;

  /// 加载超时定时器（仅用于页面/脚本/渲染失败）
  Timer? _loadTimeoutTimer;

  /// 验证页面完整 URL
  String get _verifyPageUrl => EnvironmentService.turnstileVerifyPageUrl;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _initWebView();
    }
    _startLoadTimeout();
  }

  @override
  void dispose() {
    _loadTimeoutTimer?.cancel();
    _webViewController = null;
    super.dispose();
  }

  /// 启动加载超时（15 秒）
  /// 仅用于：WebView 页面加载失败、Turnstile 脚本加载失败、渲染失败
  void _startLoadTimeout() {
    _loadTimeoutTimer?.cancel();
    _loadTimeoutTimer = Timer(const Duration(seconds: 15), () {
      if (mounted && !_isRendered && !_isVerified && !_hasError) {
        debugPrint('[Turnstile] ⏰ 加载超时（页面/脚本/渲染未完成）');
        setState(() {
          _hasError = true;
          _errorMessage = '验证加载超时，请检查网络后重试';
          _isLoadingPage = false;
        });
        widget.onError?.call('验证加载超时');
      }
    });
  }

  /// 取消加载超时（页面加载完成 或 Turnstile 渲染完成时调用）
  void _cancelLoadTimeout() {
    _loadTimeoutTimer?.cancel();
  }

  @override
  void didUpdateWidget(covariant TurnstileVerificationWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isDarkMode != widget.isDarkMode) {
      _updateTheme();
    }
  }

  /// 重置验证状态（外部调用）
  void reset() {
    debugPrint('[Turnstile] 🔄 重置验证组件');
    setState(() {
      _isVerified = false;
      _hasError = false;
      _isRendered = false;
      _isLoadingPage = true;
      _errorMessage = null;
    });
    if (!kIsWeb && _webViewController != null) {
      _webViewController!.reload();
    }
    _startLoadTimeout();
  }

  // ── WebView 初始化 ──────────────────────────

  void _initWebView() {
    late final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    final controller = WebViewController.fromPlatformCreationParams(params);

    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(
          widget.isDarkMode ? const Color(0xFF13131F) : const Color(0xFFF8F8FF))
      ..addJavaScriptChannel(
        'TurnstileChannel',
        onMessageReceived: _onJavaScriptMessage,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            debugPrint('[Turnstile] 📄 onPageStarted: $url');
            if (mounted) {
              setState(() {
                _isLoadingPage = true;
                _hasError = false;
              });
            }
          },
          onPageFinished: (String url) {
            debugPrint('[Turnstile] 📄 onPageFinished: $url');
            if (mounted) {
              // 检测是否加载到了 JSON 而非 HTML
              _webViewController
                  ?.runJavaScriptReturningResult(
                'document.body ? document.body.innerText.substring(0, 2) : ""',
              )
                  .then((result) {
                final content = result.toString().replaceAll('"', '');
                final isJson =
                    content.startsWith('{') || content.startsWith('[');
                if (mounted) {
                  if (isJson) {
                    debugPrint('[Turnstile] ❌ 检测到 JSON 响应，非 HTML 页面');
                    _cancelLoadTimeout();
                    setState(() {
                      _hasError = true;
                      _errorMessage = '人机验证页面配置错误，请检查 TURNSTILE_VERIFY_PAGE_URL';
                      _isLoadingPage = false;
                    });
                    widget.onError?.call('验证页面返回了 JSON 而非 HTML');
                  }
                  // 不在这里设置 _isLoadingPage = false
                  // 等 rendered 事件到达后再设置
                }
              }).catchError((e) {
                debugPrint('[Turnstile] 内容检测失败: $e');
                // 检测失败不一定是错误，继续等待 rendered 事件
              });
            }
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint('[Turnstile] ❌ WebView error: ${error.description}');
            _cancelLoadTimeout();
            if (mounted && !_isVerified) {
              setState(() {
                _hasError = true;
                _errorMessage = '人机验证加载失败，请检查网络后重试';
                _isLoadingPage = false;
              });
              widget.onError?.call('验证加载失败: ${error.description}');
            }
          },
        ),
      );

    // 加载验证页面
    final theme = widget.isDarkMode ? 'dark' : 'light';
    final url = '$_verifyPageUrl?theme=$theme&action=${widget.action}';
    debugPrint('[Turnstile] 🌐 Loading URL: $url');
    controller.loadRequest(Uri.parse(url));

    // Android 特殊配置
    if (controller.platform is wv_android.AndroidWebViewController) {
      (controller.platform as wv_android.AndroidWebViewController)
          .setMediaPlaybackRequiresUserGesture(false);
    }

    setState(() {
      _webViewController = controller;
    });
  }

  // ── 主题切换 ────────────────────────────────

  void _updateTheme() {
    if (_webViewController == null) return;
    final theme = widget.isDarkMode ? 'dark' : 'light';
    _webViewController!.runJavaScript('''
      document.body.className = '$theme';
      var w = document.getElementById('turnstile-widget');
      if (w) w.setAttribute('data-theme', '$theme');
    ''');
  }

  // ── JS 消息处理 ─────────────────────────────

  void _onJavaScriptMessage(JavaScriptMessage message) {
    try {
      final data = jsonDecode(message.message) as Map<String, dynamic>;
      final type = data['type'] as String?;
      debugPrint('[Turnstile] 📨 JS event: $type');

      switch (type) {
        // 页面 HTML 加载完成（Turnstile 脚本尚未加载）
        case 'pageLoaded':
          debugPrint('[Turnstile] 📄 pageLoaded');
          // 不取消超时，继续等待 rendered
          break;

        // Turnstile 组件渲染完成，用户可以开始交互
        case 'rendered':
          debugPrint('[Turnstile] ✅ rendered — 取消加载超时');
          _cancelLoadTimeout();
          if (mounted) {
            setState(() {
              _isRendered = true;
              _isLoadingPage = false;
              _hasError = false;
            });
          }
          break;

        // 用户验证成功
        case 'success':
          final token = data['token'] as String?;
          if (token != null && token.isNotEmpty) {
            debugPrint(
                '[Turnstile] ✅ success (token=${token.substring(0, 8)}...)');
            _cancelLoadTimeout();
            if (mounted) {
              setState(() {
                _isVerified = true;
                _isLoadingPage = false;
                _hasError = false;
              });
            }
            widget.onVerified(token);
          }
          break;

        // token 过期
        case 'expired':
          debugPrint('[Turnstile] ⏰ expired');
          if (mounted) {
            setState(() {
              _isVerified = false;
              _isRendered = true; // 组件仍在，只是 token 过期
            });
          }
          widget.onExpired?.call();
          break;

        // Turnstile 内部错误
        case 'error':
          final msg = data['message'] as String? ?? '验证失败';
          debugPrint('[Turnstile] ❌ error: $msg');
          _cancelLoadTimeout();
          if (mounted) {
            setState(() {
              _hasError = true;
              _errorMessage = msg;
              _isLoadingPage = false;
            });
          }
          widget.onError?.call(msg);
          break;
      }
    } catch (e) {
      debugPrint('[Turnstile] ❌ Failed to parse JS message: $e');
    }
  }

  // ── Build ───────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return _buildWebTurnstile();
    }
    return _buildNativeTurnstile();
  }

  /// Flutter Web 平台
  Widget _buildWebTurnstile() {
    return Container(
      width: double.infinity,
      height: widget.height,
      decoration: _boxDecoration(),
      child: _buildStatusContent(),
    );
  }

  /// 原生平台：WebView
  Widget _buildNativeTurnstile() {
    return Container(
      width: double.infinity,
      height: widget.height,
      decoration: _boxDecoration(),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // WebView 层
          if (_webViewController != null && !_hasError)
            WebViewWidget(controller: _webViewController!),
          // 加载指示器（仅在页面/脚本加载阶段显示）
          if (_isLoadingPage && !_hasError && !_isRendered)
            _buildLoadingOverlay(),
          // 错误状态
          if (_hasError) _buildErrorState(),
          // 验证成功
          if (_isVerified) _buildVerifiedOverlay(),
        ],
      ),
    );
  }

  BoxDecoration _boxDecoration() {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(12),
      color: widget.isDarkMode
          ? const Color(0x0DFFFFFF)
          : const Color(0xFFF8F8FF),
      border: Border.all(
        color: _isVerified
            ? const Color(0xFF4CAF50)
            : _hasError
                ? const Color(0xFFE53E3E)
                : widget.isDarkMode
                    ? const Color(0x1AFFFFFF)
                    : const Color(0xFFDDDDEE),
        width: 1,
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    return Container(
      color: widget.isDarkMode
          ? const Color(0xFF13131F)
          : const Color(0xFFF8F8FF),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF6C63FF),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '正在加载验证...',
              style: TextStyle(
                fontSize: 12,
                color: widget.isDarkMode
                    ? const Color(0x99FFFFFF)
                    : const Color(0xFF5A5A7A),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVerifiedOverlay() {
    return Container(
      color: widget.isDarkMode
          ? const Color(0xFF13131F)
          : const Color(0xFFF8F8FF),
      child: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.check_circle_outline,
              color: Color(0xFF4CAF50),
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              '验证已通过',
              style: TextStyle(
                fontSize: 13,
                color: widget.isDarkMode
                    ? const Color(0xFF66BB6A)
                    : const Color(0xFF4CAF50),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusContent() {
    if (_isVerified) return _buildVerifiedOverlay();
    if (_hasError) return _buildErrorState();
    return _buildLoadingOverlay();
  }

  Widget _buildErrorState() {
    return Container(
      color: widget.isDarkMode
          ? const Color(0xFF13131F)
          : const Color(0xFFF8F8FF),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                color: widget.isDarkMode
                    ? const Color(0xFFEF5350)
                    : const Color(0xFFE53E3E),
                size: 20,
              ),
              const SizedBox(height: 6),
              Text(
                _errorMessage ?? '验证加载失败',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: widget.isDarkMode
                      ? const Color(0xFFEF5350)
                      : const Color(0xFFE53E3E),
                ),
              ),
              const SizedBox(height: 6),
              GestureDetector(
                onTap: widget.disabled ? null : reset,
                child: Text(
                  '点击重试',
                  style: TextStyle(
                    fontSize: 12,
                    color: widget.isDarkMode
                        ? const Color(0xFF9C97FF)
                        : const Color(0xFF6C63FF),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
