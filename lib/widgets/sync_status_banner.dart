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
  SyncPathStatus _status = SyncPathStatus.online;
  String _detailMessage = "数据已实时同步";
  bool _isExpanded = false;

  // 模拟心跳检测 (实际应对接 WebSocket 监听)
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
                      _detailMessage,
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
