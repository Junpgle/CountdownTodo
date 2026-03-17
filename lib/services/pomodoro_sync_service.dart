import 'dart:async';
import 'dart:convert';
import 'dart:io'; // 🚀 新增：用于获取当前操作系统
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;

// ============================================================
// 跨端专注感知：连接阿里云 WebSocket 服务器
// ============================================================

/// 从 WebSocket 收到的跨端状态（扩充了版本更新字段）
class CrossDevicePomodoroState {
  final String action;      // 'START'|'STOP'|'SWITCH'|'SYNC_FOCUS'|'SYNC_TAGS'|'UPDATE_TAGS'|'HEARTBEAT' | 'UPDATE_AVAILABLE'
  final String? sessionUuid;
  final String? todoUuid;
  final String? todoTitle;
  final int? duration;
  final int? targetEndMs;
  final String? sourceDevice;
  final int? timestamp;
  final List<String> tags;
  final int? mode; // 🚀 新增：0=countdown, 1=countUp

  // 🚀 新增：版本更新专属字段
  final String? latestVersion;
  final String? downloadUrl;
  final String? releaseNotes;

  final Map<String, dynamic>? manifestData;

  const CrossDevicePomodoroState({
    required this.action,
    this.todoUuid,
    this.sessionUuid,
    this.todoTitle,
    this.duration,
    this.targetEndMs,
    this.sourceDevice,
    this.timestamp,
    this.tags = const [],
    this.mode,
    // 🚀 新增
    this.latestVersion,
    this.downloadUrl,
    this.releaseNotes,
    this.manifestData,
  });

  factory CrossDevicePomodoroState.fromJson(Map<String, dynamic> j) =>
      CrossDevicePomodoroState(
        action: j['action']?.toString().toUpperCase() ?? 'UNKNOWN',
        sessionUuid: j['session_uuid']?.toString() ?? j['sessionUuid']?.toString(),
        todoUuid: j['todo_uuid']?.toString(),
        todoTitle: j['todo_title']?.toString(),
        duration: _parseInt(j['duration']),
        targetEndMs: _parseInt(j['target_end_ms'] ?? j['targetEndMs']),
        sourceDevice: (j['sourceDevice'] ?? j['source_device'])?.toString(),
        timestamp: _parseInt(j['timestamp']),
        tags: _parseStringList(j['tags']),
        mode: _parseInt(j['mode']),
        // 🚀 新增解析
        latestVersion: j['latest_version']?.toString(),
        downloadUrl: j['download_url']?.toString(),
        releaseNotes: j['release_notes']?.toString(),
        manifestData: j['manifest'] as Map<String, dynamic>?,
      );

  static int? _parseInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  static List<String> _parseStringList(dynamic v) {
    if (v == null) return const [];
    if (v is List) return v.map((e) => e.toString()).toList();
    return const [];
  }

  Map<String, dynamic> toJson() => {
    'action': action,
    if (todoUuid != null) 'todo_uuid': todoUuid,
    if (sessionUuid != null) 'session_uuid': sessionUuid,
    if (todoTitle != null) 'todo_title': todoTitle,
    if (duration != null) 'duration': duration,
    if (targetEndMs != null) 'target_end_ms': targetEndMs,
    if (tags.isNotEmpty) 'tags': tags,
    if (mode != null) 'mode': mode,
    // 🚀 新增序列化
    if (latestVersion != null) 'latest_version': latestVersion,
    if (downloadUrl != null) 'download_url': downloadUrl,
    if (releaseNotes != null) 'release_notes': releaseNotes,
  };
}

enum SyncConnectionState { disconnected, connecting, connected, error }

class PomodoroSyncService {
  static const String _wsUrl = 'ws://101.200.13.100:8081';
  static const Duration _reconnectDelay = Duration(seconds: 5);
  static const Duration _heartbeatInterval = Duration(seconds: 30);

  // ── 单例 ─────────────────────────────────────────────────
  static final PomodoroSyncService instance = PomodoroSyncService._();
  factory PomodoroSyncService() => instance;
  PomodoroSyncService._();

  // ── 连接参数 ──────────────────────────────────────────────
  String? _userId;
  String? _deviceId;
  String? _appVersion; // 🚀 新增：保存当前 App 版本号

  // ── 内部状态 ──────────────────────────────────────────────
  WebSocketChannel? _channel;
  StreamSubscription? _wsSub;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  bool _connecting = false;

  // ── 公开广播流 ─────────────────────────────────────────────
  final _stateCtrl = StreamController<CrossDevicePomodoroState>.broadcast();
  final _connStateCtrl = StreamController<SyncConnectionState>.broadcast();

  Stream<CrossDevicePomodoroState> get onStateChanged => _stateCtrl.stream;
  Stream<SyncConnectionState> get onConnectionChanged => _connStateCtrl.stream;

  SyncConnectionState _connState = SyncConnectionState.disconnected;
  SyncConnectionState get connectionState => _connState;

  // ── 公开 API ─────────────────────────────────────────────

  /// 🚀 传入版本号（建议使用 package_info_plus 获取后传入）
  Future<void> ensureConnected(String userId, String deviceId, {String? appVersion}) async {
    if (appVersion != null) _appVersion = appVersion; // 记录版本号

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

  /// 🚀 强制重连时也可更新版本号
  Future<void> forceReconnect(String userId, String deviceId, {String? appVersion}) async {
    if (appVersion != null) _appVersion = appVersion;
    _userId = userId;
    _deviceId = deviceId;
    await _doConnect();
  }

  Future<void> reconnectIfNeeded() async {
    if (_userId == null || _deviceId == null) return;
    if (_connState == SyncConnectionState.connected || _connecting) return;
    await _doConnect();
  }

  Future<void> resumeSync() async {
    if (_userId == null || _deviceId == null) return;
    await _doConnect();
  }

  // ── 内部连接 ─────────────────────────────────────────────

  Future<void> _doConnect() async {
    if (_connecting) return;
    _connecting = true;

    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    await _wsSub?.cancel();
    _wsSub = null;
    try { await _channel?.sink.close(ws_status.normalClosure); } catch (_) {}
    _channel = null;

    _setConnState(SyncConnectionState.connecting);

    try {
      // 🚀 获取当前平台类型 (Android, iOS, Windows, macOS, etc.)
      final platform = kIsWeb ? 'web' : Platform.operatingSystem;
      final versionParam = _appVersion ?? 'unknown';

      // 🚀 核心改造：在握手 URL 中直接汇报平台和版本
      final uri = Uri.parse(
        '$_wsUrl/?userId=${Uri.encodeComponent(_userId!)}'
            '&deviceId=${Uri.encodeComponent(_deviceId!)}'
            '&platform=${Uri.encodeComponent(platform)}' // 传给云端方便下发对应安装包
            '&version=${Uri.encodeComponent(versionParam)}', // 传给云端用于统计和对比
      );

      _channel = WebSocketChannel.connect(uri);

      await _channel!.ready.timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('WebSocket 握手超时'),
      );

      _setConnState(SyncConnectionState.connected);
      debugPrint('[PomodoroSync] ✅ 已连接 (平台:$platform, 版本:$versionParam)');

      _wsSub = _channel!.stream.listen(
        _onMessage,
        onDone: () {
          _onDisconnected();
        },
        onError: (e) {
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

      // 🚀 如果收到更新推送，打印一下
      if (signal.action == 'UPDATE_AVAILABLE') {
        debugPrint('[PomodoroSync] 🎁 收到新版本推送: ${signal.latestVersion}');
      } else {
        debugPrint('[PomodoroSync] 📨 ${signal.action} from ${signal.sourceDevice}');
      }

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
        _doConnect();
      }
    });
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
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

  // ── 发送信号 (保持原有不变) ──────────────────────────────────
  void sendStartSignal({
    required String sessionUuid,
    required String? todoUuid,
    required String? todoTitle,
    required int durationSeconds,
    required int targetEndMs,
    required int? mode,
    List<String> tagNames = const [],
    int? customTimestamp,
  }) {
    _send({
      'action': 'START',
      'session_uuid': sessionUuid,
      if (todoUuid != null) 'todo_uuid': todoUuid,
      if (todoTitle != null) 'todo_title': todoTitle,
      'duration': durationSeconds,
      'target_end_ms': targetEndMs,
      'tags': tagNames,
      if (mode != null) 'mode': mode,
      'timestamp': customTimestamp ?? DateTime.now().millisecondsSinceEpoch,
    });
  }

  void sendReconnectSyncSignal({
    required String sessionUuid,
    required String? todoUuid,
    required String? todoTitle,
    required int durationSeconds,
    required int targetEndMs,
    required int? mode,
    List<String> tagNames = const [],
    int? customTimestamp,
  }) {
    _send({
      'action': 'RECONNECT_SYNC',
      'session_uuid': sessionUuid,
      if (todoUuid != null) 'todo_uuid': todoUuid,
      if (todoTitle != null) 'todo_title': todoTitle,
      'duration': durationSeconds,
      'target_end_ms': targetEndMs,
      'tags': tagNames,
      if (mode != null) 'mode': mode,
      'timestamp': customTimestamp ?? DateTime.now().millisecondsSinceEpoch,
    });
  }

  void sendStopSignal() => _send({'action': 'STOP'});

  void sendSwitchSignal({required String? todoUuid, required String? todoTitle, required String sessionUuid}) {
    _send({
      'action': 'SWITCH',
      'session_uuid': sessionUuid,
      if (todoUuid != null) 'todo_uuid': todoUuid,
      if (todoTitle != null) 'todo_title': todoTitle,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  void sendUpdateTagsSignal(List<String> tagNames) {
    _send({'action': 'UPDATE_TAGS', 'tags': tagNames});
  }

  void _send(Map<String, dynamic> payload) {
    if (_connState != SyncConnectionState.connected || _channel == null) return;
    try {
      _channel!.sink.add(jsonEncode(payload));
    } catch (_) {}
  }

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