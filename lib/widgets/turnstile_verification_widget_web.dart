import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../services/environment_service.dart';

class TurnstileVerificationWidget extends StatefulWidget {
  final ValueChanged<String> onVerified;
  final VoidCallback? onExpired;
  final ValueChanged<String>? onError;
  final bool disabled;
  final bool isDarkMode;
  final String action;
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
  late final String _containerId;
  late final web.HTMLDivElement _container;
  String? _widgetId;
  Timer? _scriptPollTimer;
  Timer? _loadTimeoutTimer;
  bool _isLoading = true;
  bool _isVerified = false;
  bool _hasError = false;
  String? _errorMessage;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _containerId = 'turnstile-cnt-${DateTime.now().microsecondsSinceEpoch}';
    _container = web.HTMLDivElement()
      ..id = _containerId
      ..style.width = '100%'
      ..style.height = '${widget.height.round()}px';

    _startLoadTimeout();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadScriptAndRender();
    });
  }

  @override
  void didUpdateWidget(covariant TurnstileVerificationWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isDarkMode != widget.isDarkMode ||
        oldWidget.action != widget.action) {
      reset();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _scriptPollTimer?.cancel();
    _loadTimeoutTimer?.cancel();
    _removeWidget();
    _container.remove();
    super.dispose();
  }

  void _removeWidget() {
    final id = _widgetId;
    if (id != null && _hasTurnstile) {
      try {
        _turnstileCall('remove', [id.toJS]);
      } catch (_) {}
    }
    _widgetId = null;
  }

  void reset() {
    _loadTimeoutTimer?.cancel();
    _scriptPollTimer?.cancel();
    setState(() {
      _isLoading = true;
      _isVerified = false;
      _hasError = false;
      _errorMessage = null;
    });
    final id = _widgetId;
    if (id != null && _hasTurnstile) {
      try {
        _turnstileCall('reset', [id.toJS]);
        setState(() => _isLoading = false);
        return;
      } catch (_) {}
    }
    _removeWidget();
    _container.textContent = '';
    _startLoadTimeout();
    _loadScriptAndRender();
  }

  void _startLoadTimeout() {
    _loadTimeoutTimer?.cancel();
    _loadTimeoutTimer = Timer(const Duration(seconds: 15), () {
      if (_disposed || _isVerified || _hasError) return;
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = '验证加载超时，请检查网络后重试';
      });
      widget.onError?.call(_errorMessage!);
    });
  }

  bool get _hasTurnstile => globalContext.has('turnstile');

  JSObject? get _turnstileObject =>
      _hasTurnstile ? globalContext['turnstile'] as JSObject? : null;

  JSAny? _turnstileCall(String method, List<JSAny?> args) {
    final api = _turnstileObject;
    if (api == null) return null;
    return api.callMethodVarArgs<JSAny?>(method.toJS, args);
  }

  void _loadScriptAndRender() {
    if (_hasTurnstile) {
      _renderWidget();
      return;
    }

    final existing = web.document.querySelector(
      'script[src="https://challenges.cloudflare.com/turnstile/v0/api.js"]',
    );

    if (existing == null) {
      final script = web.HTMLScriptElement()
        ..src = 'https://challenges.cloudflare.com/turnstile/v0/api.js'
        ..async = true
        ..defer = true;
      script.addEventListener(
        'load',
        ((web.Event _) => _renderWidget()).toJS,
      );
      script.addEventListener(
        'error',
        ((web.Event _) => _fail('无法加载验证服务')).toJS,
      );
      web.document.head?.appendChild(script);
    }

    _scriptPollTimer?.cancel();
    _scriptPollTimer =
        Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (_hasTurnstile) {
        timer.cancel();
        _renderWidget();
      }
    });
  }

  void _renderWidget() {
    if (_disposed || widget.disabled) return;
    if (!_hasTurnstile) return;

    if (_widgetId != null) {
      if (!_container.isConnected) {
        _removeWidget();
      } else {
        return;
      }
    }

    if (!_container.isConnected) {
      web.document.body?.appendChild(_container);
    }

    if (!_container.isConnected) {
      Future.delayed(const Duration(milliseconds: 50), () {
        if (!_disposed && _widgetId == null) _renderWidget();
      });
      return;
    }

    try {
      final options = JSObject()
        ..['sitekey'] = EnvironmentService.turnstileSiteKey.toJS
        ..['action'] = widget.action.toJS
        ..['theme'] = (widget.isDarkMode ? 'dark' : 'light').toJS
        ..['size'] = 'normal'.toJS
        ..['callback'] = ((JSString token) {
          final tokenText = token.toDart;
          _loadTimeoutTimer?.cancel();
          if (_disposed) return;
          setState(() {
            _isVerified = true;
            _isLoading = false;
            _hasError = false;
          });
          widget.onVerified(tokenText);
        }).toJS
        ..['expired-callback'] = (() {
          if (_disposed) return;
          setState(() {
            _isVerified = false;
            _isLoading = false;
          });
          widget.onExpired?.call();
        }).toJS
        ..['error-callback'] = ((JSAny? errorCode) {
          final code = errorCode?.dartify()?.toString();
          _fail(_formatTurnstileError(code));
        }).toJS;

      final id = _turnstileCall('render', [_container, options]);
      if (id == null) {
        _fail('验证组件渲染失败');
        return;
      }
      _widgetId = id.dartify()?.toString();
      _loadTimeoutTimer?.cancel();
      if (!_disposed) {
        setState(() {
          _isLoading = false;
          _hasError = false;
        });
      }
    } catch (e) {
      _fail('验证渲染失败: $e');
    }
  }

  void _fail(String message) {
    _loadTimeoutTimer?.cancel();
    if (_disposed) return;
    setState(() {
      _isLoading = false;
      _hasError = true;
      _errorMessage = message;
    });
    widget.onError?.call(message);
  }

  String _formatTurnstileError(String? code) {
    if (code == null || code.isEmpty) {
      return '验证加载失败，点击重试';
    }
    if (code == '110200') {
      return '域名未授权，请检查 Turnstile 配置（110200）';
    }
    return '验证加载失败（$code）';
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: widget.height,
      child: DecoratedBox(
        decoration: BoxDecoration(
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
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            children: [
              if (_isLoading && !_hasError) _buildLoadingOverlay(),
              if (_hasError) _buildErrorState(),
              if (_isVerified) _buildVerifiedOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    return Positioned.fill(
      child: ColoredBox(
        color: widget.isDarkMode
            ? const Color(0xFF13131F)
            : const Color(0xFFF8F8FF),
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
    );
  }

  Widget _buildVerifiedOverlay() {
    return Positioned.fill(
      child: ColoredBox(
        color: widget.isDarkMode
            ? const Color(0xFF13131F)
            : const Color(0xFFF8F8FF),
        child: const Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle_outline,
                  color: Color(0xFF4CAF50), size: 20),
              SizedBox(width: 8),
              Text('验证已通过'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Positioned.fill(
      child: ColoredBox(
        color: widget.isDarkMode
            ? const Color(0xFF13131F)
            : const Color(0xFFF8F8FF),
        child: Center(
          child: TextButton.icon(
            onPressed: widget.disabled ? null : reset,
            icon: const Icon(Icons.error_outline),
            label: Text(_errorMessage ?? '验证加载失败，点击重试'),
          ),
        ),
      ),
    );
  }
}
