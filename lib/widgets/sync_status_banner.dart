import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:ui';
import '../services/api_service.dart';
import '../services/pomodoro_sync_service.dart';

enum SyncPathStatus { online, connecting, offline, serverError, success }

class SyncStatusBanner extends StatefulWidget {
  final VoidCallback? onDiagnosticRequested;
  
  const SyncStatusBanner({super.key, this.onDiagnosticRequested});

  @override
  State<SyncStatusBanner> createState() => _SyncStatusBannerState();
}

class _SyncStatusBannerState extends State<SyncStatusBanner> {
  SyncPathStatus _status = SyncPathStatus.connecting;
  String _detailMessage = "正在确认同步链路...";
  bool _isExpanded = false;
  Timer? _heartbeatTimer;
  Timer? _autoHideTimer;

  // 监听 WS 连接状态变化
  StreamSubscription? _wsConnSub;

  @override
  void initState() {
    super.initState();
    // 订阅 WS 状态变化流，实时响应断线/重连
    _wsConnSub = PomodoroSyncService.instance.onConnectionChanged.listen(_onWsStateChanged);
    
    // 🚀 初始化时立即评估一次当前连接状态，防止错过已处于连接状态的情况
    _evaluateStatus(PomodoroSyncService.instance.connectionState);
    
    _startHeartbeat();
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    _autoHideTimer?.cancel();
    _wsConnSub?.cancel();
    super.dispose();
  }

  /// WS 状态变化时立即触发一次综合检查
  void _onWsStateChanged(dynamic wsState) {
    if (!mounted) return;
    // WS 状态一变化就立即重新评估，不等下次 heartbeat
    _evaluateStatus(wsState);
  }

  void _startHeartbeat() {
    // 立即执行一次
    _checkRealStatus();
    // 随后每 30 秒探测一次真实链路状况
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) => _checkRealStatus());
  }

  Future<void> _checkRealStatus() async {
    // 先取当前 WS 状态（同步读取，无需 await）
    final wsState = PomodoroSyncService.instance.connectionState;
    try {
      // 🚀 核心逻辑：发起一个轻量级的健康检查
      final isAlive = await ApiService.ping();
      if (!mounted) return;
      if (isAlive) {
        // HTTP 通了再看 WS 是否也连上了
        _evaluateStatus(wsState);
      } else {
        updateStatus(SyncPathStatus.serverError, message: "同步服务器响应异常");
      }
    } catch (e) {
      if (!mounted) return;
      updateStatus(SyncPathStatus.offline, message: "网络连接已断开，进入离线模式");
    }
  }

  /// 🚀 双维度评估：HTTP 可达 + WS 连接状态
  void _evaluateStatus(dynamic wsState) {
    switch (wsState) {
      case SyncConnectionState.connected:
        updateStatus(SyncPathStatus.online, message: "数据已实时同步");
        break;
      case SyncConnectionState.connecting:
        updateStatus(SyncPathStatus.connecting, message: "正在建立实时同步通道...");
        break;
      case SyncConnectionState.disconnected:
        updateStatus(SyncPathStatus.connecting, message: "实时通道已断开，正在重连...");
        break;
      case SyncConnectionState.error:
        updateStatus(SyncPathStatus.serverError, message: "实时同步通道连接失败");
        break;
    }
  }

  // 🚀 供外部手动触发快速更新
  void updateStatus(SyncPathStatus status, {String? message}) {
    if (!mounted) return;

    // 🚀 核心逻辑：如果从“非在线”切换到“在线”，先进入 success 状态展示 2 秒再消失
    if (status == SyncPathStatus.online && _status != SyncPathStatus.online && _status != SyncPathStatus.success) {
      setState(() {
        _status = SyncPathStatus.success;
        _detailMessage = "同步连接已恢复";
      });

      _autoHideTimer?.cancel();
      _autoHideTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _status = SyncPathStatus.online;
          });
        }
      });
      return;
    }

    // 如果是其它状态，取消自动隐藏计时器
    if (status != SyncPathStatus.online && status != SyncPathStatus.success) {
      _autoHideTimer?.cancel();
    }

    setState(() {
      _status = status;
      if (message != null) _detailMessage = message;
    });
  }

  Color _getStatusColor() {
    switch (_status) {
      case SyncPathStatus.online: return Colors.green[400]!;
      case SyncPathStatus.success: return Colors.teal[400]!;
      case SyncPathStatus.connecting: return Colors.orange[400]!;
      case SyncPathStatus.offline: return Colors.red[400]!;
      case SyncPathStatus.serverError: return Colors.purple[400]!;
    }
  }

  IconData _getStatusIcon() {
    switch (_status) {
      case SyncPathStatus.online: 
      case SyncPathStatus.success: return Icons.cloud_done_rounded;
      case SyncPathStatus.connecting: return Icons.sync_rounded;
      case SyncPathStatus.offline: return Icons.cloud_off_rounded;
      case SyncPathStatus.serverError: return Icons.dns_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 🚀 核心改动：仅在非在线状态（即：连接中、断线、错误、或正在展示成功的 success 状态）时显示横幅
    bool shouldShow = _status != SyncPathStatus.online;
    bool isUrgent = _status == SyncPathStatus.offline || _status == SyncPathStatus.serverError;
    bool isSuccess = _status == SyncPathStatus.success;
    
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      transitionBuilder: (Widget child, Animation<double> animation) {
        return SizeTransition(
          sizeFactor: animation,
          axisAlignment: -1.0,
          child: FadeTransition(opacity: animation, child: child),
        );
      },
      child: !shouldShow 
        ? const SizedBox.shrink()
        : RepaintBoundary(
            key: ValueKey(_status == SyncPathStatus.success ? 'success' : _status),
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: ClipRRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: _getStatusColor().withValues(alpha: 0.85),
                      border: Border(
                        bottom: BorderSide(
                          color: Colors.white.withValues(alpha: 0.12),
                          width: 0.5,
                        ),
                      ),
                    ),
                    child: InkWell(
                      onTap: () => setState(() => _isExpanded = !_isExpanded),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Icon(_getStatusIcon(), size: 16, color: Colors.white.withValues(alpha: 0.95)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _detailMessage + (ApiService.baseUrl.contains(':8084') ? ' 🚀[TEST]' : ''),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ),
                              if (!isSuccess && (isUrgent || _status == SyncPathStatus.connecting))
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    TextButton(
                                      onPressed: () {
                                        PomodoroSyncService.instance.manualReconnect();
                                        updateStatus(SyncPathStatus.connecting, message: "正在尝试手动重连...");
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('已触发手动同步重连...'), duration: Duration(seconds: 1)),
                                        );
                                      },
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 8),
                                        minimumSize: const Size(50, 24),
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      child: Text(
                                        "立即重连",
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white.withValues(alpha: 0.95),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    TextButton(
                                      onPressed: widget.onDiagnosticRequested,
                                      style: TextButton.styleFrom(
                                        padding: EdgeInsets.zero,
                                        minimumSize: const Size(50, 24),
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      child: Text(
                                        "链路诊断",
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white.withValues(alpha: 0.7),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                          if (_isExpanded && (isUrgent || _status == SyncPathStatus.connecting))
                            Padding(
                              padding: const EdgeInsets.only(top: 8, bottom: 4),
                              child: Text(
                                "Uni-Sync 正在检测您的实时同步通道。若长时间处于连接中，请尝试切换网络或检查服务器防火墙设置。",
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.white.withValues(alpha: 0.75),
                                  height: 1.4,
                                ),
                              ),
                            )
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
    );
  }
}
