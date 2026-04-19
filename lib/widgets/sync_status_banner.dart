import 'package:flutter/material.dart';
import 'dart:async';
import '../services/api_service.dart';

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

  @override
  void initState() {
    super.initState();
    _startHeartbeat();
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    super.dispose();
  }

  void _startHeartbeat() {
    // 立即执行一次
    _checkRealStatus();
    // 随后每 30 秒探测一次真实链路状况
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) => _checkRealStatus());
  }

  Future<void> _checkRealStatus() async {
    try {
      // 🚀 核心逻辑：发起一个轻量级的健康检查
      final isAlive = await ApiService.ping(); 
      if (isAlive) {
        updateStatus(SyncPathStatus.online, message: "数据已实时同步");
      } else {
        updateStatus(SyncPathStatus.serverError, message: "同步服务器响应异常");
      }
    } catch (e) {
      updateStatus(SyncPathStatus.offline, message: "网络连接已断开，进入离线模式");
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
    bool isUrgent = _status != SyncPathStatus.online;
    
    return RepaintBoundary(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        curve: Curves.fastOutSlowIn,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: _getStatusColor().withOpacity(0.15),
          border: Border(bottom: BorderSide(color: _getStatusColor().withOpacity(0.3), width: 0.5)),
        ),
        child: InkWell(
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(_getStatusIcon(), size: 16, color: _getStatusColor()),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _detailMessage + (ApiService.baseUrl.contains(':8084') ? ' 🚀[TEST:8084]' : ''),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _getStatusColor().withOpacity(0.9),
                      ),
                    ),
                  ),
                  if (isUrgent)
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
              if (_isExpanded && isUrgent)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    "Uni-Sync 正在通过 Cloudflare Tunnel 尝试连接您的私有服务器。若长时间失败，请检查 Zero Trust 客户端状态。",
                    style: TextStyle(fontSize: 10, color: _getStatusColor().withOpacity(0.7)),
                  ),
                )
            ],
          ),
        ),
      ),
    );
  }
}
