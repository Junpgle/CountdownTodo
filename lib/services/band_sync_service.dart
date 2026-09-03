import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'storage/app_settings_storage.dart';

class BandSyncService {
  static const MethodChannel _channel =
      MethodChannel('com.math_quiz_app/band_communication');
  static const int _maxPlatformMessageBytes = 64 * 1024;
  static const int _maxSyncStringLength = 512;
  static const Set<String> _excludedSyncKeys = {
    'imagePath',
    'image_path',
    'originalText',
    'original_text',
    'analysisImagePath',
    'conflict_data',
    'serverVersionData',
  };

  static bool _isInitialized = false;
  static bool _nativeServiceStarted = false;
  static bool _channelHandlerBound = false;
  static Future<void> _lifecycleTail = Future<void>.value();
  static Future<void> _settingsTail = Future<void>.value();
  static int _serviceRequestGeneration = 0;
  static bool _isConnected = false;
  static String _nodeId = '';
  static String _deviceName = '';
  static String _bandVersion = '';
  static final ValueNotifier<String> bandVersionNotifier =
      ValueNotifier<String>('');
  static final ValueNotifier<bool> serviceEnabledNotifier =
      ValueNotifier<bool>(false);
  static DateTime? _lastSyncTime;
  static final List<String> _logs = [];
  static final List<Map<String, dynamic>> _receivedMessages = [];
  static Completer<bool>? _permissionRequestCompleter;

  static final _pomodoroActionCtrl =
      StreamController<Map<String, dynamic>>.broadcast();
  static Stream<Map<String, dynamic>> get onBandPomodoroAction =>
      _pomodoroActionCtrl.stream;

  static void dispose() {
    _serviceRequestGeneration++;
    _isInitialized = false;
    serviceEnabledNotifier.value = false;
    _cancelPermissionRequest();
    unawaited(_shutdownNativeService());
    _resetConnectionState(notify: false);
    if (!_pomodoroActionCtrl.isClosed) _pomodoroActionCtrl.close();
    _logs.clear();
    _receivedMessages.clear();
  }

  static Function(Map<String, dynamic>)? _onDeviceConnected;
  static Function()? _onDeviceDisconnected;
  static Function(Map<String, dynamic>)? _onMessageReceived;
  static Function(Map<String, dynamic>)? _onError;
  static Function(List<String>)? _onPermissionGranted;
  static Function(bool)? _onPermissionChecked;

  // 同步数据提供者（由外部设置，默认从本地存储读取）
  static Future<List<Map<String, dynamic>>> Function(String type)?
      _syncDataProvider;

  static void setSyncDataProvider(
      Future<List<Map<String, dynamic>>> Function(String type) provider) {
    _syncDataProvider = provider;
  }

  static Future<bool> init({
    Function(Map<String, dynamic>)? onDeviceConnected,
    Function()? onDeviceDisconnected,
    Function(Map<String, dynamic>)? onMessageReceived,
    Function(Map<String, dynamic>)? onError,
    Function(List<String>)? onPermissionGranted,
    Function(bool)? onPermissionChecked,
  }) async {
    _onDeviceConnected = onDeviceConnected;
    _onDeviceDisconnected = onDeviceDisconnected;
    _onMessageReceived = onMessageReceived;
    _onError = onError;
    _onPermissionGranted = onPermissionGranted;
    _onPermissionChecked = onPermissionChecked;

    _bindChannelHandler();

    final requestGeneration = _serviceRequestGeneration;
    await _settingsTail;
    final storedEnabled = await isServiceEnabled();
    final enabled = requestGeneration == _serviceRequestGeneration
        ? storedEnabled
        : serviceEnabledNotifier.value;
    if (requestGeneration == _serviceRequestGeneration) {
      serviceEnabledNotifier.value = enabled;
    }

    // 只初始化 Dart bridge，不在关闭状态下触碰小米穿戴 SDK。
    _isInitialized = true;
    if (!enabled) {
      _addLog('手环服务已关闭，跳过 SDK 初始化');
      return true;
    }

    return _startNativeService();
  }

  static void _bindChannelHandler() {
    if (_channelHandlerBound) return;
    _channel.setMethodCallHandler(_handleMethodCall);
    _channelHandlerBound = true;
  }

  /// 读取并同步开关状态。设置页在全局初始化完成前打开时也能使用。
  static Future<bool> loadServiceEnabled() async {
    final requestGeneration = _serviceRequestGeneration;
    await _settingsTail;
    final enabled = await isServiceEnabled();
    if (requestGeneration == _serviceRequestGeneration) {
      serviceEnabledNotifier.value = enabled;
      return enabled;
    }
    return serviceEnabledNotifier.value;
  }

  static Future<bool> isServiceEnabled() {
    return AppSettingsStorage.isBandServiceEnabled();
  }

  /// 手动开启手环后台服务。
  static Future<bool> setServiceEnabled(bool enabled) async {
    final requestGeneration = ++_serviceRequestGeneration;
    serviceEnabledNotifier.value = enabled;
    if (!enabled) _cancelPermissionRequest();

    await _persistServiceEnabled(enabled);
    if (requestGeneration != _serviceRequestGeneration) {
      // A newer toggle superseded this request. Its preference write is still
      // kept in order, but it must not start or stop the native service.
      return true;
    }

    if (enabled) {
      _bindChannelHandler();
      _isInitialized = true;
      return _startNativeService();
    }

    _cancelPermissionRequest();
    await _shutdownNativeService();
    _resetConnectionState();
    _addLog('手环服务已关闭');
    return true;
  }

  static Future<bool> _startNativeService() {
    return _runLifecycle<bool>(() async {
      if (_nativeServiceStarted) return true;
      return _doStartNativeService();
    });
  }

  /// Serialize start/stop calls so a quick toggle cannot let an older
  /// shutdown overwrite a newer start (or vice versa).
  static Future<T> _runLifecycle<T>(Future<T> Function() operation) async {
    final previous = _lifecycleTail;
    final current = Completer<void>();
    _lifecycleTail = current.future;
    await previous;
    try {
      return await operation();
    } finally {
      current.complete();
    }
  }

  static Future<void> _persistServiceEnabled(bool enabled) {
    final previous = _settingsTail;
    final current = Completer<void>();
    _settingsTail = current.future;
    return () async {
      await previous;
      try {
        await AppSettingsStorage.setBandServiceEnabled(enabled);
      } finally {
        current.complete();
      }
    }();
  }

  static Future<bool> _doStartNativeService() async {
    try {
      if (!serviceEnabledNotifier.value) return false;
      final initialized = await _channel.invokeMethod('init');
      if (initialized == false) {
        _addLog('SDK 初始化失败');
        return false;
      }
      // The switch may have been turned off while the native init call was in
      // flight. Tear down that late start immediately instead of leaving a
      // service binding behind.
      if (!serviceEnabledNotifier.value) {
        try {
          await _channel.invokeMethod('shutdown');
        } catch (_) {}
        return false;
      }
      _nativeServiceStarted = true;
      _isInitialized = true;
      _addLog('SDK 初始化成功');
      return true;
    } catch (e) {
      _addLog('SDK 初始化失败: $e');
      return false;
    }
  }

  static Future<void> _shutdownNativeService() {
    return _runLifecycle<void>(() async {
      if (!_nativeServiceStarted) return;

      try {
        await _channel.invokeMethod('shutdown');
      } catch (e) {
        _addLog('停止手环服务失败: $e');
      } finally {
        _nativeServiceStarted = false;
      }
    });
  }

  static void _resetConnectionState({bool notify = true}) {
    final wasConnected = _isConnected;
    _isConnected = false;
    _nodeId = '';
    _deviceName = '';
    if (notify && wasConnected) _onDeviceDisconnected?.call();
  }

  static void _cancelPermissionRequest() {
    final completer = _permissionRequestCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete(false);
    }
  }

  static Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onDeviceConnected':
        if (!serviceEnabledNotifier.value) break;
        final args = Map<String, dynamic>.from(call.arguments as Map);
        _isConnected = true;
        _nodeId = args['nodeId'] ?? '';
        _deviceName = args['name'] ?? '小米手环';
        _addLog('设备已连接: $_deviceName');
        _onDeviceConnected?.call(args);
        break;

      case 'onDeviceDisconnected':
        if (!serviceEnabledNotifier.value) break;
        _isConnected = false;
        _nodeId = '';
        _deviceName = '';
        _addLog('设备已断开');
        _onDeviceDisconnected?.call();
        break;

      case 'onMessageReceived':
        if (!serviceEnabledNotifier.value) break;
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final data = args['data'] as String?;
        if (data != null) {
          _isConnected = true;
          _addLog('收到消息: $data');
          try {
            final jsonData = jsonDecode(data) as Map<String, dynamic>;
            _receivedMessages.add(jsonData);

            if (jsonData['type'] == 'pomodoro' &&
                (jsonData['action'] == 'finish' ||
                    jsonData['action'] == 'abandon')) {
              _addLog('手环番茄钟操作: ${jsonData['action']}');
//               debugPrint(
//                   '[BandSyncService] Emitting pomodoro action: ${jsonData['action']}');
              if (!_pomodoroActionCtrl.isClosed) {
                _pomodoroActionCtrl.add(jsonData);
              }
            }

            if (jsonData['type'] == 'band_info') {
              final version = jsonData['version'] as String? ?? '未知';
              final versionCode = jsonData['version_code'] as int? ?? 0;
              _bandVersion = '$version (v$versionCode)';
              bandVersionNotifier.value = _bandVersion;
              _addLog('手环版本: $_bandVersion');
            }

            if (jsonData['action'] == 'request_sync') {
              final type = jsonData['type'] as String? ?? '';
              _addLog('手环请求同步: $type');
              // 内部直接处理同步请求，不依赖外部回调
              await _handleSyncRequest(type);
            } else {
              _onMessageReceived?.call(jsonData);
            }
          } catch (e) {
            _receivedMessages.add({'raw': data});
            _onMessageReceived?.call({'raw': data});
          }
        }
        break;

      case 'onMessageSent':
        _addLog('消息发送成功');
        break;

      case 'onError':
        if (!serviceEnabledNotifier.value) break;
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final code = args['code'] ?? 0;
        final message = args['message'] ?? '未知错误';
        _addLog('错误: [$code] $message');
        final permissionCompleter = _permissionRequestCompleter;
        if (permissionCompleter != null && !permissionCompleter.isCompleted) {
          permissionCompleter.complete(false);
        }
        _onError?.call(args);
        break;

      case 'onServiceDisconnected':
        _addLog('小米穿戴服务断开');
        _resetConnectionState();
        break;

      case 'onAppInstallResult':
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final installed = args['installed'] as bool? ?? false;
        _addLog('手环应用安装状态: ${installed ? '已安装' : '未安装'}');
        break;

      case 'onAppLaunched':
        _addLog('手环应用已启动');
        break;

      case 'onPermissionGranted':
        if (!serviceEnabledNotifier.value) break;
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final permissions = List<String>.from(args['permissions'] as List);
        _addLog('权限已授予: ${permissions.join(", ")}');
        final permissionCompleter = _permissionRequestCompleter;
        if (permissionCompleter != null && !permissionCompleter.isCompleted) {
          permissionCompleter.complete(true);
        }
        _onPermissionGranted?.call(permissions);
        break;

      case 'onPermissionChecked':
        if (!serviceEnabledNotifier.value) break;
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final granted = args['granted'] as bool? ?? false;
        _addLog('权限检查结果: granted=$granted');
        _onPermissionChecked?.call(granted);
        break;
    }
  }

  // 内部处理同步请求
  static Future<void> _handleSyncRequest(String type) async {
    if (!serviceEnabledNotifier.value ||
        !_nativeServiceStarted ||
        !_isConnected) {
      _addLog('同步请求被忽略: 设备未连接');
      return;
    }
    final provider = _syncDataProvider;
    if (provider == null) {
      _addLog('同步请求被忽略: 未设置数据提供者');
      return;
    }
    try {
      final dataList = await provider(type);
      if (dataList.isEmpty) {
        _addLog('同步 $type: 无数据');
        await sendData(type, dataList);
        return;
      }

      // 自动分批发送，避免消息体过大
      const maxBatchSize = 5;
      final totalBatches = (dataList.length / maxBatchSize).ceil();
      _addLog('同步 $type: 共 ${dataList.length} 条，分 $totalBatches 批');

      for (int i = 0; i < totalBatches; i++) {
        final start = i * maxBatchSize;
        final end = (start + maxBatchSize < dataList.length)
            ? start + maxBatchSize
            : dataList.length;
        final batch = dataList.sublist(start, end);
        final success = await sendData(type, batch,
            batchNum: i + 1, totalBatches: totalBatches);
        if (!success) {
          _addLog('同步 $type: 第 ${i + 1} 批发送失败');
          break;
        }
        // 每批之间间隔，避免 SDK 限流
        await Future.delayed(const Duration(milliseconds: 200));
      }
      _addLog('已同步 $type: ${dataList.length} 条');
    } catch (e) {
      _addLog('同步 $type 异常: $e');
    }
  }

  /// 获取已连接设备
  static Future<void> getConnectedDevice() async {
    if (!_isInitialized ||
        !_nativeServiceStarted ||
        !serviceEnabledNotifier.value) {
      _addLog('服务未初始化');
      return;
    }
    try {
      await _channel.invokeMethod('getConnectedDevice');
    } catch (e) {
      _addLog('获取设备失败: $e');
    }
  }

  /// 发送数据到手环（带批次信息）
  static Future<bool> sendData(String type, dynamic data,
      {int batchNum = 1, int totalBatches = 1}) async {
    if (!_nativeServiceStarted || !serviceEnabledNotifier.value) {
      _addLog('手环服务未开启');
      return false;
    }
    if (!_isConnected) {
      _addLog('设备未连接');
      return false;
    }

    try {
      final sanitizedData = _sanitizeForBand(data);
      final payload = {
        'type': type,
        'data': sanitizedData,
        'batchNum': batchNum,
        'totalBatches': totalBatches,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      // 🚀 核心优化：对于较大数据量，使用 Isolate 处理 JSON 编码，避免主线程卡顿
      String message;
      if (sanitizedData is List && sanitizedData.length > 5) {
        message = await compute(jsonEncode, payload);
      } else {
        message = jsonEncode(payload);
      }

      final messageBytes = utf8.encode(message).length;
      if (messageBytes > _maxPlatformMessageBytes) {
        _addLog(
            '发送数据失败: $type 第 $batchNum/$totalBatches 批过大 (${(messageBytes / 1024).toStringAsFixed(1)}KB)');
        return false;
      }

      await _channel.invokeMethod('sendMessage', {'data': message});
      return true;
    } catch (e) {
      _addLog('发送数据失败: $e');
      return false;
    }
  }

  /// 同步待办事项
  static Future<bool> syncTodos(List<Map<String, dynamic>> todos) async {
    final success = await _sendListData('todo', todos);
    if (success) _updateLastSyncTime();
    return success;
  }

  /// 同步课程表
  static Future<bool> syncCourses(List<Map<String, dynamic>> courses) async {
    final success = await _sendListData('course', courses);
    if (success) _updateLastSyncTime();
    return success;
  }

  /// 同步倒计时
  static Future<bool> syncCountdowns(
      List<Map<String, dynamic>> countdowns) async {
    final success = await _sendListData('countdown', countdowns);
    if (success) _updateLastSyncTime();
    return success;
  }

  /// 同步番茄钟运行状态
  static Future<bool> syncPomodoro(
      List<Map<String, dynamic>> pomodoroData) async {
    final success = await _sendListData('pomodoro', pomodoroData);
    if (success) _updateLastSyncTime();
    return success;
  }

  /// 发送版本更新信息到手环
  static Future<bool> sendVersionUpdate(Map<String, dynamic> updateInfo) async {
    return await sendData('version_update', updateInfo);
  }

  static void _updateLastSyncTime() {
    _lastSyncTime = DateTime.now();
  }

  static dynamic _sanitizeForBand(dynamic value) {
    if (value is Map) {
      final sanitized = <String, dynamic>{};
      value.forEach((key, mapValue) {
        final stringKey = key.toString();
        if (_excludedSyncKeys.contains(stringKey)) return;
        sanitized[stringKey] = _sanitizeForBand(mapValue);
      });
      return sanitized;
    }
    if (value is List) {
      return value.map(_sanitizeForBand).toList();
    }
    if (value is String && value.length > _maxSyncStringLength) {
      return value.substring(0, _maxSyncStringLength);
    }
    return value;
  }

  static Future<bool> _sendListData(
      String type, List<Map<String, dynamic>> items) async {
    if (items.isEmpty) {
      return sendData(type, const [], batchNum: 1, totalBatches: 1);
    }

    final chunks = <List<Map<String, dynamic>>>[];
    var current = <Map<String, dynamic>>[];

    for (final item in items) {
      final sanitizedItem =
          Map<String, dynamic>.from(_sanitizeForBand(item) as Map);
      final candidate = [...current, sanitizedItem];
      if (_estimatePayloadBytes(type, candidate) > _maxPlatformMessageBytes) {
        if (current.isEmpty) {
          _addLog('同步 $type 失败: 单条数据过大，已跳过');
          continue;
        }
        chunks.add(current);
        if (_estimatePayloadBytes(type, [sanitizedItem]) >
            _maxPlatformMessageBytes) {
          _addLog('同步 $type 失败: 单条数据过大，已跳过');
          current = [];
        } else {
          current = [sanitizedItem];
        }
      } else {
        current = candidate;
      }
    }
    if (current.isNotEmpty) chunks.add(current);

    if (chunks.isEmpty) return false;

    var allSuccess = true;
    for (var i = 0; i < chunks.length; i++) {
      final success = await sendData(type, chunks[i],
          batchNum: i + 1, totalBatches: chunks.length);
      if (!success) allSuccess = false;
      await Future.delayed(const Duration(milliseconds: 200));
    }
    return allSuccess;
  }

  static int _estimatePayloadBytes(
      String type, List<Map<String, dynamic>> data) {
    final payload = {
      'type': type,
      'data': data,
      'batchNum': 1,
      'totalBatches': 1,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    return utf8.encode(jsonEncode(payload)).length;
  }

  static DateTime? get lastSyncTime => _lastSyncTime;

  static String get lastSyncTimeStr {
    if (_lastSyncTime == null) return '尚未同步';
    final now = DateTime.now();
    final diff = now.difference(_lastSyncTime!);
    if (diff.inSeconds < 60) return '刚刚同步';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    final d = _lastSyncTime!;
    return '${d.month}月${d.day}日 ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  /// 注册消息监听器
  static Future<void> registerListener() async {
    if (!_nativeServiceStarted || !serviceEnabledNotifier.value) {
      _addLog('手环服务未开启，跳过注册监听');
      return;
    }
    try {
      await _channel.invokeMethod('registerListener');
      _addLog('消息监听已注册');
    } catch (e) {
      _addLog('注册监听失败: $e');
    }
  }

  /// 取消消息监听器
  static Future<void> unregisterListener() async {
    if (!_nativeServiceStarted) return;
    try {
      await _channel.invokeMethod('unregisterListener');
      _addLog('消息监听已取消');
    } catch (e) {
      _addLog('取消监听失败: $e');
    }
  }

  /// 检查手环应用是否安装
  static Future<void> checkAppInstalled() async {
    if (!_nativeServiceStarted || !serviceEnabledNotifier.value) return;
    try {
      await _channel.invokeMethod('isAppInstalled');
    } catch (e) {
      _addLog('检查应用失败: $e');
    }
  }

  /// 启动手环应用
  static Future<void> launchApp() async {
    if (!_nativeServiceStarted || !serviceEnabledNotifier.value) return;
    try {
      await _channel.invokeMethod('launchApp');
    } catch (e) {
      _addLog('启动应用失败: $e');
    }
  }

  /// 获取连接状态
  static Future<Map<String, dynamic>> getConnectionStatus() async {
    try {
      final result = await _channel.invokeMethod('getConnectionStatus');
      return Map<String, dynamic>.from(result as Map);
    } catch (e) {
      return {'isConnected': false, 'nodeId': '', 'name': ''};
    }
  }

  /// 申请设备管理权限
  static Future<bool> requestPermission() async {
    if (!_nativeServiceStarted || !serviceEnabledNotifier.value) {
      _addLog('手环服务未开启，无法申请权限');
      return false;
    }
    final pending = _permissionRequestCompleter;
    if (pending != null && !pending.isCompleted) return pending.future;

    final completer = Completer<bool>();
    _permissionRequestCompleter = completer;
    try {
      _addLog('发起权限申请请求...');
      final result = await _channel.invokeMethod('requestPermission');
      _addLog('invokeMethod 返回: $result');
      return await completer.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () async {
          final status = await getConnectionStatus();
          final granted = status['hasPermission'] == true;
          _addLog('权限申请超时后状态: hasPermission=$granted');
          return granted;
        },
      );
    } catch (e) {
      _addLog('申请权限异常: $e');
      return false;
    } finally {
      if (identical(_permissionRequestCompleter, completer)) {
        _permissionRequestCompleter = null;
      }
    }
  }

  /// 添加日志
  static void _addLog(String message) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    _logs.add('[$timestamp] $message');
    if (_logs.length > 100) {
      _logs.removeAt(0);
    }
  }

  /// 清除日志
  static void clearLogs() {
    _logs.clear();
  }

  /// 清除接收的消息
  static void clearReceivedMessages() {
    _receivedMessages.clear();
  }

  // Getters
  static bool get isInitialized => _isInitialized;
  static bool get isConnected => _isConnected;
  static String get nodeId => _nodeId;
  static String get deviceName => _deviceName;
  static String get bandVersion => _bandVersion;
  static List<String> get logs => List.unmodifiable(_logs);
  static List<Map<String, dynamic>> get receivedMessages =>
      List.unmodifiable(_receivedMessages);
}
