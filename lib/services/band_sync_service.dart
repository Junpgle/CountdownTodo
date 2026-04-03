import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';

/// 手环通信服务
/// 通过 Platform Channel 与小米穿戴 SDK 通信
class BandSyncService {
  static const MethodChannel _channel =
      MethodChannel('com.math_quiz_app/band_communication');

  // 状态
  static bool _isInitialized = false;
  static bool _isConnected = false;
  static String _nodeId = '';
  static String _deviceName = '';
  static DateTime? _lastSyncTime;
  static final List<String> _logs = [];
  static final List<Map<String, dynamic>> _receivedMessages = [];

  // 回调
  static Function(Map<String, dynamic>)? _onDeviceConnected;
  static Function()? _onDeviceDisconnected;
  static Function(Map<String, dynamic>)? _onMessageReceived;
  static Function(Map<String, dynamic>)? _onError;
  static Function(List<String>)? _onPermissionGranted;
  static Function(Map<String, dynamic>)? _onSyncRequestFromBand;

  /// 初始化服务
  static Future<bool> init({
    Function(Map<String, dynamic>)? onDeviceConnected,
    Function()? onDeviceDisconnected,
    Function(Map<String, dynamic>)? onMessageReceived,
    Function(Map<String, dynamic>)? onError,
    Function(List<String>)? onPermissionGranted,
    Function(Map<String, dynamic>)? onSyncRequestFromBand,
  }) async {
    _onDeviceConnected = onDeviceConnected;
    _onDeviceDisconnected = onDeviceDisconnected;
    _onMessageReceived = onMessageReceived;
    _onError = onError;
    _onPermissionGranted = onPermissionGranted;
    _onSyncRequestFromBand = onSyncRequestFromBand;

    // 设置方法调用处理器
    _channel.setMethodCallHandler(_handleMethodCall);

    try {
      await _channel.invokeMethod('init');
      _isInitialized = true;
      _addLog('SDK 初始化成功');
      return true;
    } catch (e) {
      _addLog('SDK 初始化失败: $e');
      return false;
    }
  }

  /// 处理来自 Android 的方法调用
  static Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onDeviceConnected':
        final args = Map<String, dynamic>.from(call.arguments as Map);
        _isConnected = true;
        _nodeId = args['nodeId'] ?? '';
        _deviceName = args['name'] ?? '小米手环';
        _addLog('设备已连接: $_deviceName');
        _onDeviceConnected?.call(args);
        break;

      case 'onDeviceDisconnected':
        _isConnected = false;
        _nodeId = '';
        _deviceName = '';
        _addLog('设备已断开');
        _onDeviceDisconnected?.call();
        break;

      case 'onMessageReceived':
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final data = args['data'] as String?;
        if (data != null) {
          _addLog('收到消息: $data');
          try {
            final jsonData = jsonDecode(data) as Map<String, dynamic>;
            _receivedMessages.add(jsonData);

            if (jsonData['action'] == 'request_sync') {
              _addLog('手环请求同步: ${jsonData['type']}');
              _onSyncRequestFromBand?.call(jsonData);
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
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final code = args['code'] ?? 0;
        final message = args['message'] ?? '未知错误';
        _addLog('错误: [$code] $message');
        _onError?.call(args);
        break;

      case 'onServiceDisconnected':
        _addLog('小米穿戴服务断开');
        _isConnected = false;
        _nodeId = '';
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
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final permissions = List<String>.from(args['permissions'] as List);
        _addLog('权限已授予: ${permissions.join(", ")}');
        _onPermissionGranted?.call(permissions);
        break;
    }
  }

  /// 获取已连接设备
  static Future<void> getConnectedDevice() async {
    if (!_isInitialized) {
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
    if (!_isConnected) {
      _addLog('设备未连接');
      return false;
    }

    try {
      final message = jsonEncode({
        'type': type,
        'data': data,
        'batchNum': batchNum,
        'totalBatches': totalBatches,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
      await _channel.invokeMethod('sendMessage', {'data': message});
      return true;
    } catch (e) {
      _addLog('发送数据失败: $e');
      return false;
    }
  }

  /// 同步待办事项
  static Future<bool> syncTodos(List<Map<String, dynamic>> todos) async {
    final success = await sendData('todo', todos);
    if (success) _updateLastSyncTime();
    return success;
  }

  /// 同步课程表
  static Future<bool> syncCourses(List<Map<String, dynamic>> courses) async {
    final success = await sendData('course', courses);
    if (success) _updateLastSyncTime();
    return success;
  }

  /// 同步倒计时
  static Future<bool> syncCountdowns(
      List<Map<String, dynamic>> countdowns) async {
    final success = await sendData('countdown', countdowns);
    if (success) _updateLastSyncTime();
    return success;
  }

  static void _updateLastSyncTime() {
    _lastSyncTime = DateTime.now();
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
    try {
      await _channel.invokeMethod('registerListener');
      _addLog('消息监听已注册');
    } catch (e) {
      _addLog('注册监听失败: $e');
    }
  }

  /// 取消消息监听器
  static Future<void> unregisterListener() async {
    try {
      await _channel.invokeMethod('unregisterListener');
      _addLog('消息监听已取消');
    } catch (e) {
      _addLog('取消监听失败: $e');
    }
  }

  /// 检查手环应用是否安装
  static Future<void> checkAppInstalled() async {
    try {
      await _channel.invokeMethod('isAppInstalled');
    } catch (e) {
      _addLog('检查应用失败: $e');
    }
  }

  /// 启动手环应用
  static Future<void> launchApp() async {
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
  static Future<void> requestPermission() async {
    try {
      await _channel.invokeMethod('requestPermission');
      _addLog('已发起权限申请');
    } catch (e) {
      _addLog('申请权限失败: $e');
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
  static List<String> get logs => List.unmodifiable(_logs);
  static List<Map<String, dynamic>> get receivedMessages =>
      List.unmodifiable(_receivedMessages);
}
