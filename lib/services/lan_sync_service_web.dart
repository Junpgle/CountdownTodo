import 'dart:async';

import 'package:flutter/foundation.dart';

import 'lan_sync_models.dart';
import 'lan_sync_pairing.dart';

export 'lan_sync_models.dart';

class LanSyncService {
  static final LanSyncService instance = LanSyncService._();
  factory LanSyncService() => instance;
  LanSyncService._();

  final _statusCtrl = StreamController<String>.broadcast();

  Stream<List<LanDevice>> get onDevicesChanged => const Stream.empty();
  Stream<String> get onStatusChanged => _statusCtrl.stream;
  Stream<String> get onSyncProgress => const Stream.empty();
  Stream<LanDevice> get onIncomingRequest => const Stream.empty();
  Stream<double> get onProgressChanged => const Stream.empty();
  Stream<Map<String, String>> get onFileReceived => const Stream.empty();
  Stream<LanSyncResult> get onQuickPairCompleted => const Stream.empty();
  Stream<LanSyncResult> get onSyncCompleted => const Stream.empty();

  final ValueNotifier<bool> daemonRunningNotifier = ValueNotifier<bool>(false);

  bool get isRunning => false;
  bool get isSyncing => false;
  bool get isDaemonMode => false;
  bool get autoSyncEnabled => false;
  int? get serverPort => null;
  bool discoverAllDevices = false;

  List<LanDevice> get devices => const [];
  String? get currentUserId => null;
  String? get currentDeviceId => null;
  String? get currentDeviceName => null;
  String? get localIp => null;

  void triggerDiscovery() {
    _statusCtrl.add('浏览器不支持局域网发现');
  }

  Future<void> initFromPreferences() async {}

  Future<void> onOfflineModeChanged(bool offlineEnabled) async {}

  bool get syncSecretsEnabled => true;

  bool get syncSettingsEnabled => false;

  Future<void> setDesktopDaemonEnabled(bool enabled) async {}

  Future<void> setAutoSyncEnabled(bool enabled) async {}

  Future<void> setSyncSecretsEnabled(bool enabled) async {}

  Future<void> setSyncSettingsEnabled(bool enabled) async {}

  Future<void> triggerBackgroundAutoSync({bool isStartup = false}) async {}

  Future<void> scanForPeersOnce() async {}

  Future<LanSyncResult> syncManualWithPeers({LanSyncConfig? config}) async =>
      LanSyncResult(message: '浏览器不支持局域网同步');

  Future<void> start({bool daemonMode = false}) async {
    _statusCtrl.add('浏览器不支持局域网同步');
  }

  Future<LanPairingPayload?> startQuickPairSession() async {
    _statusCtrl.add('浏览器不支持局域网面对面快传');
    return null;
  }

  void cancelQuickPairSession() {}

  Future<LanSyncResult> syncWithPairingCode(
    String rawCode, {
    LanSyncConfig? config,
  }) async => LanSyncResult(message: '浏览器不支持局域网同步');

  Future<void> stop() async {}

  Future<LanSyncResult> syncWithDevice(
    LanDevice device, {
    LanSyncConfig? config,
  }) async => LanSyncResult(message: '浏览器不支持局域网同步');

  Future<LanSyncResult> confirmAndSync(
    LanDevice device, {
    LanSyncConfig? config,
  }) async => LanSyncResult(message: '浏览器不支持局域网同步');

  void rejectIncomingRequest(LanDevice device) {}

  Future<LanSyncResult> sendFilePath(LanDevice device, String path) async =>
      LanSyncResult(message: '浏览器不支持局域网文件发送');

  void dispose() {
    _statusCtrl.close();
  }
}
