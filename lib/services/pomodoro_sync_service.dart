import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;

// ============================================================
// 跨端专注感知：连接阿里云 WebSocket 服务器
//
// 设计原则：
//   - 单例，生命周期与 App 相同，不随页面销毁而断开
//   - 页面 dispose 时只取消 UI 订阅，不调用 disconnect()
//   - 页面 initState/resume 时调用 ensureConnected() 保证在线
// ============================================================

/// 从 WebSocket 收到的跨端专注状态
class CrossDevicePomodoroState {
  final String action;      // 'START' | 'STOP' | 'SWITCH' | 'HEARTBEAT'
  final String? todoUuid;
  final String? todoTitle;
  final int? duration;      // 本次专注计划时长（秒）
  final int? targetEndMs;   // 专注结束时间戳（UTC ms）
  final String? sourceDevice;
  final int? timestamp;

  const CrossDevicePomodoroState({
    required this.action,
    this.todoUuid,
    this.todoTitle,
    this.duration,
    this.targetEndMs,
    this.sourceDevice,
    this.timestamp,
  });

  factory CrossDevicePomodoroState.fromJson(Map<String, dynamic> j) =>
      CrossDevicePomodoroState(
        action: j['action']?.toString().toUpperCase() ?? 'UNKNOWN',
        todoUuid: j['todo_uuid']?.toString(),
        todoTitle: j['todo_title']?.toString(),
        duration: j['duration'] as int?,
        targetEndMs: j['target_end_ms'] as int?,
        sourceDevice: j['sourceDevice']?.toString(),
        timestamp: j['timestamp'] as int?,
      );

  Map<String, dynamic> toJson() => {
        'action': action,
        if (todoUuid != null) 'todo_uuid': todoUuid,
        if (todoTitle != null) 'todo_title': todoTitle,
        if (duration != null) 'duration': duration,
        if (targetEndMs != null) 'target_end_ms': targetEndMs,
      };
}

enum SyncConnectionState { disconnected, connecting, connected, error }

class PomodoroSyncService {
  static const String _wsUrl = 'ws://101.200.13.100:8081';
  static const Duration _reconnectDelay = Duration(seconds: 5);
  static const Duration _heartbeatInterval = Duration(seconds: 30);

  // ── 单例 ─────────────────────────────────────────────────
  static final PomodoroSyncService instance = PomodoroSyncService._();
  // 保留无参工厂构造，方便旧代码 PomodoroSyncService() 继续使用
  factory PomodoroSyncService() => instance;
  PomodoroSyncService._();

  // ── 连接参数 ──────────────────────────────────────────────
  String? _userId;
  String? _deviceId;

  // ── 内部状态 ──────────────────────────────────────────────
  WebSocketChannel? _channel;
  StreamSubscription? _wsSub;   // WebSocket stream 订阅（内部，非 UI）
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  bool _connecting = false;     // 防止并发 connect

  // ── 公开广播流（UI 层 listen/cancel，不影响连接） ────────
  final _stateCtrl =
      StreamController<CrossDevicePomodoroState>.broadcast();
  final _connStateCtrl =
      StreamController<SyncConnectionState>.broadcast();

  Stream<CrossDevicePomodoroState> get onStateChanged => _stateCtrl.stream;
  Stream<SyncConnectionState> get onConnectionChanged => _connStateCtrl.stream;

  SyncConnectionState _connState = SyncConnectionState.disconnected;
  SyncConnectionState get connectionState => _connState;

  // ── 公开 API ─────────────────────────────────────────────

  /// 页面初始化时调用：传入 userId + deviceId，如果已连接且参数相同则幂等跳过。
  Future<void> ensureConnected(String userId, String deviceId) async {
    // 参数未变且已连接 → 无需重连
    if (_userId == userId &&
        _deviceId == deviceId &&
        _connState == SyncConnectionState.connected) {
      debugPrint('[PomodoroSync] 已连接，跳过重连');
      return;
    }
    _userId = userId;
    _deviceId = deviceId;
    await _doConnect();
  }

  /// 页面 resume 时调用：如果当前已断开则触发重连（参数已知）
  Future<void> reconnectIfNeeded() async {
    if (_userId == null || _deviceId == null) return;
    if (_connState == SyncConnectionState.connected || _connecting) return;
    await _doConnect();
  }

  // ── 内部连接 ─────────────────────────────────────────────

  Future<void> _doConnect() async {
    if (_connecting) return;
    _connecting = true;

    // 先干净地关掉旧连接（不触发重连 timer）
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    await _wsSub?.cancel();
    _wsSub = null;
    try { await _channel?.sink.close(ws_status.normalClosure); } catch (_) {}
    _channel = null;

    _setConnState(SyncConnectionState.connecting);

    try {
      final uri = Uri.parse(
        '$_wsUrl/?userId=${Uri.encodeComponent(_userId!)}'
        '&deviceId=${Uri.encodeComponent(_deviceId!)}',
      );
      _channel = WebSocketChannel.connect(uri);

      // 等待握手，超时 10 秒
      await _channel!.ready.timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('WebSocket 握手超时'),
      );

      _setConnState(SyncConnectionState.connected);
      debugPrint(
          '[PomodoroSync] ✅ 已连接 (userId=$_userId, device=$_deviceId)');

      _wsSub = _channel!.stream.listen(
        _onMessage,
        onDone: () {
          debugPrint('[PomodoroSync] 🔌 连接关闭（onDone）');
          _onDisconnected();
        },
        onError: (e) {
          debugPrint('[PomodoroSync] ⚠️ 连接错误: $e');
          _onDisconnected();
        },
        cancelOnError: true,
      );

      _startHeartbeat();
    } catch (e) {
      debugPrint('[PomodoroSync] ❌ 连接失败: $e');
      _setConnState(SyncConnectionState.error);
      _scheduleReconnect();
    } finally {
      _connecting = false;
    }
  }

  void _onMessage(dynamic raw) {
    try {
      final data = jsonDecode(raw.toString()) as Map<String, dynamic>;
      final signal = CrossDevicePomodoroState.fromJson(data);
      debugPrint(
          '[PomodoroSync] 📨 ${signal.action} from ${signal.sourceDevice}');
      if (!_stateCtrl.isClosed) _stateCtrl.add(signal);
    } catch (e) {
      debugPrint('[PomodoroSync] 消息解析失败: $e');
    }
  }

  void _onDisconnected() {
    _setConnState(SyncConnectionState.disconnected);
    _heartbeatTimer?.cancel();
    _connecting = false;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_reconnectDelay, () {
      if (_userId != null) {
        debugPrint('[PomodoroSync] 🔄 自动重连...');
        _doConnect();
      }
    });
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer =
        Timer.periodic(_heartbeatInterval, (_) {
      if (_connState == SyncConnectionState.connected) {
        _send({'action': 'HEARTBEAT'});
      }
    });
  }

  void _setConnState(SyncConnectionState s) {
    if (_connState == s) return;
    _connState = s;
    if (!_connStateCtrl.isClosed) _connStateCtrl.add(s);
  }

  // ── 发送信号 ──────────────────────────────────────────────

  void sendStartSignal({
    required String? todoUuid,
    required String? todoTitle,
    required int durationSeconds,
    required int targetEndMs,
  }) {
    _send({
      'action': 'START',
      if (todoUuid != null) 'todo_uuid': todoUuid,
      if (todoTitle != null) 'todo_title': todoTitle,
      'duration': durationSeconds,
      'target_end_ms': targetEndMs,
    });
  }

  void sendStopSignal() => _send({'action': 'STOP'});

  void sendSwitchSignal({
    required String? todoUuid,
    required String? todoTitle,
  }) {
    _send({
      'action': 'SWITCH',
      if (todoUuid != null) 'todo_uuid': todoUuid,
      if (todoTitle != null) 'todo_title': todoTitle,
    });
  }

  void _send(Map<String, dynamic> payload) {
    if (_connState != SyncConnectionState.connected || _channel == null) {
      debugPrint('[PomodoroSync] 未连接，忽略: ${payload['action']}');
      return;
    }
    try {
      _channel!.sink.add(jsonEncode(payload));
      debugPrint('[PomodoroSync] 📤 ${payload['action']}');
    } catch (e) {
      debugPrint('[PomodoroSync] 发送失败: $e');
    }
  }

  // ── 仅供 App 完全退出时调用（不要在页面 dispose 里调）────
  Future<void> forceDisconnect() async {
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    await _wsSub?.cancel();
    _wsSub = null;
    try { await _channel?.sink.close(ws_status.goingAway); } catch (_) {}
    _channel = null;
    _userId = null;
    _deviceId = null;
    _connecting = false;
    _setConnState(SyncConnectionState.disconnected);
  }
}

