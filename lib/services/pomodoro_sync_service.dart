import 'dart:async';
import 'dart:convert';
import 'dart:io'; // 🚀 新增：用于获取当前操作系统
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;
import 'api_service.dart';
import 'notification_service.dart';
import '../storage_service.dart';
import '../models.dart';

// ============================================================
// 跨端专注感知：连接阿里云 WebSocket 服务器
// ============================================================

/// 从 WebSocket 收到的跨端状态（扩充了版本更新字段）
class CrossDevicePomodoroState {
  final String
      action; // 'START'|'STOP'|'SWITCH'|'SYNC_FOCUS'|'SYNC_TAGS'|'UPDATE_TAGS'|'HEARTBEAT'|'UPDATE_AVAILABLE'|'FOCUS_DISCONNECTED'|'CLEAR_FOCUS'|'CONFLICT_ALERT'|'TEAM_UPDATE'
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

  // 🚀 新增：暂停状态字段
  final bool? isPaused;
  final int? pausedAtMs;
  final int? accumulatedMs;
  final int? pauseStartMs;
  final int? serverElapsedMs;

  // 🚀 团队协作扩展
  final List<ConflictInfo>? conflicts;
  final String? teamUuid;
  final dynamic delta;

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
    this.latestVersion,
    this.downloadUrl,
    this.releaseNotes,
    this.manifestData,
    this.isPaused,
    this.pausedAtMs,
    this.accumulatedMs,
    this.pauseStartMs,
    this.serverElapsedMs,
    this.conflicts,
    this.teamUuid,
    this.delta,
  });

  factory CrossDevicePomodoroState.fromJson(Map<String, dynamic> j) =>
      CrossDevicePomodoroState(
        action: j['action']?.toString().toUpperCase() ?? 'UNKNOWN',
        sessionUuid:
            j['session_uuid']?.toString() ?? j['sessionUuid']?.toString(),
        todoUuid: j['todo_uuid']?.toString(),
        todoTitle: j['todo_title']?.toString(),
        duration: _parseInt(j['duration']),
        targetEndMs: _parseInt(j['target_end_ms'] ?? j['targetEndMs']),
        sourceDevice: (j['sourceDevice'] ?? j['source_device'])?.toString(),
        timestamp: _parseInt(j['timestamp']),
        tags: _parseStringList(j['tags']),
        mode: _parseInt(j['mode']),
        latestVersion: j['latest_version']?.toString(),
        downloadUrl: j['download_url']?.toString(),
        releaseNotes: j['release_notes']?.toString(),
        manifestData: j['manifest'] as Map<String, dynamic>?,
        isPaused: j['isPaused'] as bool?,
        pausedAtMs: _parseInt(j['pausedAtMs']),
        accumulatedMs: _parseInt(j['accumulatedMs']),
        pauseStartMs: _parseInt(j['pauseStartMs']),
        serverElapsedMs: _parseInt(j['server_elapsed_ms'] ?? j['serverElapsedMs']),
        conflicts: j['conflicts'] != null 
          ? (j['conflicts'] as List).map((c) => ConflictInfo.fromJson(c)).toList() 
          : null,
        teamUuid: j['teamUuid']?.toString() ?? j['team_uuid']?.toString(),
        delta: j['delta'],
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
        if (latestVersion != null) 'latest_version': latestVersion,
        if (downloadUrl != null) 'download_url': downloadUrl,
        if (releaseNotes != null) 'release_notes': releaseNotes,
        if (isPaused != null) 'isPaused': isPaused,
        if (pausedAtMs != null) 'pausedAtMs': pausedAtMs,
        if (accumulatedMs != null) 'accumulatedMs': accumulatedMs,
        if (pauseStartMs != null) 'pauseStartMs': pauseStartMs,
      };
}

enum SyncConnectionState { disconnected, connecting, connected, error }

class PomodoroSyncService {
  static const Duration _reconnectDelay = Duration(seconds: 5);
  static const Duration _heartbeatInterval = Duration(seconds: 30);

  // ── 单例 ─────────────────────────────────────────────────
  static final PomodoroSyncService instance = PomodoroSyncService._();
  factory PomodoroSyncService() => instance;
  PomodoroSyncService._();

  // ── 连接参数 ──────────────────────────────────────────────
  String? _userId;
  String? _deviceId;
  String? _authToken; 
  String? _appVersion; 

  // ── 内部状态 ──────────────────────────────────────────────
  WebSocketChannel? _channel;
  StreamSubscription? _wsSub;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  bool _connecting = false;
  String? _focusSourceDevice;
  DateTime _lastMessageTime = DateTime.now(); // 🚀 新增：记录最后一次收到消息的时间

  // ── 公开广播流 ─────────────────────────────────────────────
  final _stateCtrl = StreamController<CrossDevicePomodoroState>.broadcast();
  final _connStateCtrl = StreamController<SyncConnectionState>.broadcast();

  Stream<CrossDevicePomodoroState> get onStateChanged => _stateCtrl.stream;
  Stream<SyncConnectionState> get onConnectionChanged => _connStateCtrl.stream;

  Function(CrossDevicePomodoroState state)? onStaleSyncFocus;

  void dispose() {
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    _wsSub?.cancel();
    _channel?.sink.close(ws_status.normalClosure);
    if (!_stateCtrl.isClosed) _stateCtrl.close();
    if (!_connStateCtrl.isClosed) _connStateCtrl.close();
  }

  SyncConnectionState _connState = SyncConnectionState.disconnected;
  SyncConnectionState get connectionState => _connState;

  String? get focusSourceDevice => _focusSourceDevice;
  bool get isFocusSource => _focusSourceDevice == _deviceId;

  Future<void> ensureConnected(String userId, String deviceId,
      {String? authToken, String? appVersion}) async {
    if (appVersion != null) _appVersion = appVersion;
    if (authToken != null) _authToken = authToken;

    if (_userId == userId &&
        _deviceId == deviceId &&
        _connState == SyncConnectionState.connected) {
      debugPrint('[PomodoroSync] 已连接，跳过重连');
      return;
    }
    _userId = userId;
    _deviceId = deviceId;
    _focusSourceDevice = null;
    await _doConnect();
  }

  Future<void> forceReconnect(String userId, String deviceId,
      {String? authToken, String? appVersion}) async {
    if (appVersion != null) _appVersion = appVersion;
    if (authToken != null) _authToken = authToken;
    _userId = userId;
    _deviceId = deviceId;
    _focusSourceDevice = null;
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

  Future<void> _doConnect() async {
    if (_connecting) return;
    _connecting = true;

    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    await _wsSub?.cancel();
    _wsSub = null;
    try {
      await _channel?.sink.close(ws_status.normalClosure);
    } catch (_) {}
    _channel = null;

    _setConnState(SyncConnectionState.connecting);

    try {
      final platform = kIsWeb ? 'web' : Platform.operatingSystem;
      final versionParam = _appVersion ?? 'unknown';

      // 🚀 核心修复：WebSocket 地址动态跟随 ApiService，消除 8082/8084 端口不匹配
      String apiBase = ApiService.baseUrl;
      String wsBase = apiBase.replaceFirst('https://', 'wss://').replaceFirst('http://', 'ws://');

      final uri = Uri.parse(
        '$wsBase/?token=${Uri.encodeComponent(_authToken ?? '')}'
        '&deviceId=${Uri.encodeComponent(_deviceId!)}'
        '&platform=${Uri.encodeComponent(platform)}'
        '&version=${Uri.encodeComponent(versionParam)}',
      );
      debugPrint('[PomodoroSync] 🔌 正在尝试连接至: $uri');

      _channel = WebSocketChannel.connect(uri);

      await _channel!.ready.timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('WebSocket 握手超时'),
      );

      _setConnState(SyncConnectionState.connected);
      _lastMessageTime = DateTime.now(); // 重置心跳计时

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
      _subscribeToTeams(); 
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
      debugPrint('📥 [WS接收] 原始数据: $raw');
      final data = jsonDecode(raw.toString()) as Map<String, dynamic>;
      final signal = CrossDevicePomodoroState.fromJson(data);

      if (signal.action == 'UPDATE_AVAILABLE') {
        debugPrint('[PomodoroSync] 🎁 收到新版本推送: ${signal.latestVersion}');
      }

      if (signal.action == 'TEAM_REMOVED' && signal.teamUuid != null) {
        debugPrint('[PomodoroSync] 🧹 收到踢出团队广播，清理本地数据: ${signal.teamUuid}');
        StorageService.clearTeamItems(signal.teamUuid!);
        // 🚀 核心修复：弹出横幅提醒
        NotificationService.showGenericNotification(
          title: "移除团队通知",
          body: "你已被移出团队: ${signal.teamUuid}",
        );
      }

      if (signal.action == 'START' || signal.action == 'RECONNECT_SYNC') {
        _focusSourceDevice = signal.sourceDevice;
      } else if (signal.action == 'STOP' ||
          signal.action == 'INTERRUPT' ||
          signal.action == 'FINISH' ||
          signal.action == 'FOCUS_DISCONNECTED') {
        _focusSourceDevice = null;
      }

      if (signal.action == 'SYNC_FOCUS' &&
          signal.sourceDevice == _deviceId &&
          onStaleSyncFocus != null) {
        debugPrint('[PomodoroSync] 🍅 检测ato服务端残留状态回推，触发本地状态校验');
        onStaleSyncFocus!(signal);
      }

      _lastMessageTime = DateTime.now(); // 🚀 每次收到有效消息都刷新时间
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
        // 🚀 核心逻辑：如果超过 2 个心跳周期（60s）没收到任何消息，判定为“僵尸活跃”，强制重连
        final silentDuration = DateTime.now().difference(_lastMessageTime);
        if (silentDuration > (_heartbeatInterval * 2.5)) {
           debugPrint('[PomodoroSync] ⚠️ 心跳超时 (已静默 ${silentDuration.inSeconds}s)，强制重新连接...');
           _onDisconnected();
           return;
        }
        _send({'action': 'HEARTBEAT'});
      }
    });
  }

  void _setConnState(SyncConnectionState s) {
    if (_connState == s) return;
    _connState = s;
    if (!_connStateCtrl.isClosed) _connStateCtrl.add(s);
  }

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

  void sendSwitchSignal(
      {required String? todoUuid,
      required String? todoTitle,
      required String sessionUuid}) {
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

  void sendPauseSignal({
    required String sessionUuid,
    required int pausedAtMs,
    required int accumulatedMs,
    required int pauseStartMs,
  }) {
    _send({
      'action': 'PAUSE',
      'session_uuid': sessionUuid,
      'pausedAtMs': pausedAtMs,
      'accumulatedMs': accumulatedMs,
      'pauseStartMs': pauseStartMs,
    });
  }

  void sendResumeSignal({
    required String sessionUuid,
    int? pausedAtMs,
    int? accumulatedMs,
    int? pauseStartMs,
    int? targetEndMs,
    int? mode,
    String? todoUuid,
    String? todoTitle,
  }) {
    _send({
      'action': 'RESUME',
      'session_uuid': sessionUuid,
      if (pausedAtMs != null) 'pausedAtMs': pausedAtMs,
      if (accumulatedMs != null) 'accumulatedMs': accumulatedMs,
      if (pauseStartMs != null) 'pauseStartMs': pauseStartMs,
      if (targetEndMs != null) 'target_end_ms': targetEndMs,
      if (mode != null) 'mode': mode,
      if (todoUuid != null) 'todo_uuid': todoUuid,
      if (todoTitle != null) 'todo_title': todoTitle,
    });
  }

  void sendClearFocusSignal() {
    _send({'action': 'CLEAR_FOCUS'});
  }

  void sendTeamUpdateSignal(String? teamUuid) {
    _send({
      'action': 'TEAM_UPDATE',
      'team_uuid': teamUuid,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  void _subscribeToTeams() async {
    if (_connState != SyncConnectionState.connected) return;
    try {
      final teamsData = await ApiService.fetchTeams();
      final teamUuids = teamsData.map((t) => t['uuid'].toString()).toList();
      if (teamUuids.isNotEmpty) {
        _send({
          'type': 'subscribe',
          'teamUuids': teamUuids,
        });
        debugPrint('[PomodoroSync] 👥 已发送团队房间订阅请求: $teamUuids');
      }
    } catch (e) {
      debugPrint('[PomodoroSync] 团队订阅失败: $e');
    }
  }

  void _send(Map<String, dynamic> payload) {
    if (_connState != SyncConnectionState.connected || _channel == null) return;
    try {
      _channel!.sink.add(jsonEncode(payload));
    } catch (e) {
      debugPrint('[PomodoroSync] ❌ WS发送失败: $e');
      _onDisconnected(); // 发送失败直接触发重连
    }
  }

  Future<void> forceDisconnect() async {
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    await _wsSub?.cancel();
    _wsSub = null;
    try {
      await _channel?.sink.close(ws_status.goingAway);
    } catch (_) {}
    _channel = null;
    _userId = null;
    _deviceId = null;
    _connecting = false;
    _setConnState(SyncConnectionState.disconnected);
  }
}
