import 'package:flutter/material.dart';
import 'dart:async';
import '../services/api_service.dart';
import '../services/pomodoro_sync_service.dart';

enum SyncPathStatus { online, connecting, offline, serverError }

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

  // 监听 WS 连接状态变化
  StreamSubscription<SyncConnectionState>? _wsConnSub;

  @override
  void initState() {
    super.initState();
    // 订阅 WS 状态变化流，实时响应断线/重连
    _wsConnSub = PomodoroSyncService.instance.onConnectionChanged.listen(_onWsStateChanged);
    _startHeartbeat();
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    _wsConnSub?.cancel();
    super.dispose();
  }

  /// WS 状态变化时立即触发一次综合检查
  void _onWsStateChanged(SyncConnectionState wsState) {
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
  void _evaluateStatus(SyncConnectionState wsState) {
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
    setState(() {
      _status = status;
      if (message != null) _detailMessage = message;
    });
  }

  Color _getStatusColor() {
    switch (_status) {
      case SyncPathStatus.online: return Colors.green[400]!;
      case SyncPathStatus.connecting: return Colors.orange[400]!;
      case SyncPathStatus.offline: return Colors.red[400]!;
      case SyncPathStatus.serverError: return Colors.purple[400]!;
    }
  }

  IconData _getStatusIcon() {
    switch (_status) {
      case SyncPathStatus.online: return Icons.cloud_done_rounded;
      case SyncPathStatus.connecting: return Icons.sync_rounded;
      case SyncPathStatus.offline: return Icons.cloud_off_rounded;
      case SyncPathStatus.serverError: return Icons.dns_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 🚀 核心改动：仅在非在线状态（即：连接中、断线、错误）时显示横幅
    bool shouldShow = _status != SyncPathStatus.online;
    bool isUrgent = _status == SyncPathStatus.offline || _status == SyncPathStatus.serverError;
    
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
            key: ValueKey(_status), // 状态变化时触发连贯动画
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: _getStatusColor().withOpacity(0.15),
                border: Border(bottom: BorderSide(color: _getStatusColor().withOpacity(0.3), width: 0.5)),
              ),
              child: InkWell(
                onTap: () => setState(() => _isExpanded = !_isExpanded),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(_getStatusIcon(), size: 16, color: _getStatusColor()),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _detailMessage + (ApiService.baseUrl.contains(':8084') ? ' 🚀[TEST]' : ''),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _getStatusColor().withOpacity(0.9),
                            ),
                          ),
                        ),
                        if (isUrgent || _status == SyncPathStatus.connecting)
                          TextButton(
                            onPressed: widget.onDiagnosticRequested,
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(50, 24),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text("链路诊断", style: TextStyle(fontSize: 11, color: _getStatusColor())),
                          ),
                      ],
                    ),
                    if (_isExpanded && (isUrgent || _status == SyncPathStatus.connecting))
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          "Uni-Sync 正在检测您的实时同步通道。若长时间处于连接中，请尝试切换网络或检查服务器防火墙设置。",
                          style: TextStyle(fontSize: 10, color: _getStatusColor().withOpacity(0.7)),
                        ),
                      )
                  ],
                ),
              ),
            ),
          ),
    );
  }
}
