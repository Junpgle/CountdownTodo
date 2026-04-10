import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models.dart';
import '../services/band_sync_service.dart';
import '../services/course_service.dart';
import '../services/pomodoro_service.dart';
import '../storage_service.dart';
import '../update_service.dart';

/// 手环同步界面
class BandSyncScreen extends StatefulWidget {
  const BandSyncScreen({Key? key}) : super(key: key);

  @override
  State<BandSyncScreen> createState() => _BandSyncScreenState();
}

class _BandSyncScreenState extends State<BandSyncScreen> {
  bool _isConnected = false;
  bool _hasPermission = false;
  String _deviceName = '';
  bool _isSyncing = false;
  final List<String> _logs = [];

  @override
  void initState() {
    super.initState();
    _initBandService();
  }

  Future<void> _initBandService() async {
    if (BandSyncService.isInitialized) {
      _logs.add('手环服务已全局初始化');
      final status = await BandSyncService.getConnectionStatus();
      if (status['isConnected'] == true) {
        setState(() {
          _isConnected = true;
          _deviceName = status['name'] ?? '小米手环';
          _hasPermission = status['hasPermission'] == true;
        });
        _logs.add('当前设备: $_deviceName');
        if (BandSyncService.bandVersion.isNotEmpty) {
          setState(() {});
          _logs.add('手环版本: ${BandSyncService.bandVersion}');
        } else {
          _logs.add('手环版本: 等待手环发送...');
        }
        if (!_hasPermission) {
          _logs.add('缺少权限，自动申请...');
          await BandSyncService.requestPermission();
        } else {
          await BandSyncService.registerListener();
        }
      }
      return;
    }

    final success = await BandSyncService.init(
      onDeviceConnected: (info) {
        setState(() {
          _isConnected = true;
          _deviceName = info['name'] ?? '小米手环';
        });
        _autoRequestPermission();
      },
      onDeviceDisconnected: () {
        setState(() {
          _isConnected = false;
          _deviceName = '';
          _hasPermission = false;
        });
      },
      onMessageReceived: (data) {
        setState(() {
          _logs.add('收到: ${data.toString()}');
        });
        _handleBandMessage(data);
      },
      onError: (error) {
        setState(() {
          _logs.add('错误: ${error['message']}');
        });
      },
      onPermissionGranted: (permissions) {
        setState(() {
          _hasPermission = true;
        });
        _logs.add('权限已授予: ${permissions.join(", ")}，自动注册监听...');
        BandSyncService.registerListener();
      },
      onPermissionChecked: (granted) {
        _logs.add('权限检查结果: granted=$granted');
      },
    );

    if (success) {
      await BandSyncService.getConnectedDevice();
    }
  }

  Future<void> _handleSyncRequest(String type) async {
    _logs.add('开始处理同步请求: $type');
    try {
      switch (type) {
        case 'todo':
          await _syncTodos();
          break;
        case 'course':
          await _syncCourses();
          break;
        case 'countdown':
          await _syncCountdowns();
          break;
        case 'pomodoro':
          await _syncPomodoro();
          break;
        default:
          _logs.add('未知同步请求: $type');
      }
    } catch (e) {
      _logs.add('同步异常: $e');
    }
  }

  Future<void> _autoRequestPermission() async {
    // 等待一下让设备连接完成
    await Future.delayed(const Duration(milliseconds: 500));

    final status = await BandSyncService.getConnectionStatus();
    if (status['hasPermission'] == true) {
      setState(() => _hasPermission = true);
      _logs.add('已有权限，自动注册监听...');
      await BandSyncService.registerListener();
    } else {
      _logs.add('缺少权限，自动申请...');
      await BandSyncService.requestPermission();
    }
  }

  @override
  void dispose() {
    BandSyncService.unregisterListener();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('手环同步'),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildConnectionCard(),
            const SizedBox(height: 16),
            _buildBandVersionCard(),
            const SizedBox(height: 16),
            _buildLastSyncCard(),
            const SizedBox(height: 16),
            _buildPermissionCard(),
            const SizedBox(height: 16),
            _buildSyncButtons(),
            const SizedBox(height: 16),
            _buildLogArea(),
            const SizedBox(height: 16),
            _buildReceivedMessages(),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _isConnected ? Icons.watch : Icons.watch_off,
                  color: _isConnected ? Colors.green : Colors.grey,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '连接状态',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _isConnected ? '● 已连接' : '○ 未连接',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: _isConnected ? Colors.green : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () async {
                    await BandSyncService.getConnectedDevice();
                  },
                ),
              ],
            ),
            if (_isConnected && _deviceName.isNotEmpty) ...[
              const Divider(height: 24),
              Row(
                children: [
                  const Icon(Icons.devices, color: Colors.blue),
                  const SizedBox(width: 8),
                  Text(
                    '设备: $_deviceName',
                    style: const TextStyle(fontSize: 16),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBandVersionCard() {
    return ValueListenableBuilder<String>(
      valueListenable: BandSyncService.bandVersionNotifier,
      builder: (context, version, _) {
        return Card(
          elevation: 2,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.purple, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '手环版本',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        version.isNotEmpty ? version : '等待连接...',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.purple,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLastSyncCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.access_time, color: Colors.teal, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '上次同步',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    BandSyncService.lastSyncTimeStr,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _hasPermission ? Icons.verified : Icons.security,
                  color: _hasPermission ? Colors.green : Colors.orange,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '权限状态',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _hasPermission
                            ? '● DEVICE_MANAGER 已授权'
                            : '○ 缺少 DEVICE_MANAGER 权限',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _hasPermission ? Colors.green : Colors.orange,
                        ),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.lock_open, size: 18),
                  label: const Text('申请权限'),
                  onPressed: _isConnected && !_hasPermission
                      ? () async {
                          _logs.add('手动申请权限...');
                          await BandSyncService.requestPermission();
                          // 等待更长时间让权限对话框出现
                          await Future.delayed(const Duration(seconds: 3));
                          // 刷新状态
                          final status =
                              await BandSyncService.getConnectionStatus();
                          final granted = status['hasPermission'] == true;
                          setState(() {
                            _hasPermission = granted;
                          });
                          if (granted) {
                            _logs.add('权限申请成功！');
                            await BandSyncService.registerListener();
                          } else {
                            _logs.add('权限申请无响应，请检查小米穿戴App授权状态');
                          }
                        }
                      : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSyncButtons() {
    final canSync = _isConnected && _hasPermission && !_isSyncing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '数据同步',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildSyncButton(
                icon: Icons.checklist,
                label: '同步待办',
                color: Colors.blue,
                onPressed: canSync ? _syncTodos : null,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildSyncButton(
                icon: Icons.calendar_today,
                label: '同步课程',
                color: Colors.orange,
                onPressed: canSync ? _syncCourses : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildSyncButton(
                icon: Icons.local_fire_department,
                label: '同步番茄钟',
                color: Colors.red,
                onPressed: canSync ? _syncPomodoro : null,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildSyncButton(
                icon: Icons.sync,
                label: '全部同步',
                color: Colors.green,
                onPressed: canSync ? _syncAll : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.open_in_new),
                label: const Text('启动手环应用'),
                onPressed:
                    _isConnected ? () => BandSyncService.launchApp() : null,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.info_outline),
                label: const Text('检查应用安装'),
                onPressed: _isConnected
                    ? () => BandSyncService.checkAppInstalled()
                    : null,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSyncButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onPressed,
  }) {
    return ElevatedButton.icon(
      icon: Icon(icon, size: 20),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: onPressed != null ? color : Colors.grey[300],
        foregroundColor: onPressed != null ? Colors.white : Colors.grey[600],
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      onPressed: onPressed,
    );
  }

  Widget _buildLogArea() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final logBgColor = isDark ? Colors.grey[900] : Colors.grey[100];
    final logTextColor = isDark ? Colors.grey[300] : Colors.grey[800];
    final emptyTextColor = isDark ? Colors.grey[600] : Colors.grey;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '同步日志',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: () {
                        final allLogs = _logs.join('\n');
                        if (allLogs.isNotEmpty) {
                          _copyToClipboard(allLogs, '同步日志');
                        }
                      },
                      child: const Text('复制全部'),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _logs.clear();
                        });
                      },
                      child: const Text('清除'),
                    ),
                  ],
                ),
              ],
            ),
            const Divider(),
            Container(
              height: 150,
              decoration: BoxDecoration(
                color: logBgColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: _logs.isEmpty
                  ? Center(
                      child: Text(
                        '暂无日志',
                        style: TextStyle(color: emptyTextColor),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: _logs.length,
                      itemBuilder: (context, index) {
                        return GestureDetector(
                          onTap: () {
                            _copyToClipboard(_logs[index], '日志');
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text(
                              _logs[index],
                              style: TextStyle(
                                fontSize: 12,
                                fontFamily: 'monospace',
                                color: logTextColor,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReceivedMessages() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final msgBgColor = isDark ? Colors.grey[900] : Colors.grey[100];
    final msgTextColor = isDark ? Colors.grey[300] : Colors.grey[800];
    final emptyTextColor = isDark ? Colors.grey[600] : Colors.grey;
    final cardColor = isDark ? Colors.grey[850] : null;
    final messages = BandSyncService.receivedMessages;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '收到手环消息',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: () {
                        final allMsgs =
                            messages.map((m) => m.toString()).join('\n');
                        if (allMsgs.isNotEmpty) {
                          _copyToClipboard(allMsgs, '手环消息');
                        }
                      },
                      child: const Text('复制全部'),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          BandSyncService.clearReceivedMessages();
                        });
                      },
                      child: const Text('清除'),
                    ),
                  ],
                ),
              ],
            ),
            const Divider(),
            Container(
              height: 150,
              decoration: BoxDecoration(
                color: msgBgColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: messages.isEmpty
                  ? Center(
                      child: Text(
                        '暂无消息',
                        style: TextStyle(color: emptyTextColor),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final msg = messages[index];
                        final msgStr = msg.toString();
                        return GestureDetector(
                          onTap: () {
                            _copyToClipboard(msgStr, '手环消息');
                          },
                          child: Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            color: cardColor,
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text(
                                msgStr,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                  color: msgTextColor,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已复制$label到剪贴板'),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<String?> _getUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(StorageService.KEY_CURRENT_USER);
  }

  /// 处理手环发回的消息（todo状态变更等）
  Future<void> _handleBandMessage(Map<String, dynamic> data) async {
    final type = data['type'] as String?;

    if (type == 'band_info') {
      final version = data['version'] as String? ?? '未知';
      final versionCode = data['version_code'] as int? ?? 0;
      _logs.add('手环版本: $version (v$versionCode)');
      setState(() {});
      return;
    }

    final bandData = data['data'];

    if (type == null || bandData == null) {
      _logs.add('消息格式无效: 缺少 type 或 data');
      return;
    }

    final username = await _getUsername();
    if (username == null || username.isEmpty) {
      _logs.add('未登录，无法处理手环消息');
      return;
    }

    if (type == 'todo') {
      await _handleBandTodoUpdate(bandData, username);
    } else if (type == 'pomodoro') {
      final action = bandData['action'] as String?;
      if (action == 'finish' || action == 'abandon') {
        _logs.add('手环${action == 'finish' ? '提前完成' : '放弃'}番茄钟');
      } else {
        _logs.add('收到番茄钟消息（无操作指令）');
      }
    } else if (type == 'debug') {
      final message = bandData['message'] as String? ?? '';
      setState(() {
        _logs.add('[手环] $message');
      });
    } else if (type == 'countdown') {
      _logs.add('收到倒计时同步（暂未处理）');
    } else if (type == 'course') {
      _logs.add('收到课程同步（暂未处理）');
    } else {
      _logs.add('未知消息类型: $type');
    }
  }

  /// 处理手环发回的待办状态更新
  Future<void> _handleBandTodoUpdate(dynamic bandData, String username) async {
    List<dynamic> items;
    if (bandData is List) {
      items = bandData;
    } else if (bandData is Map) {
      items = [bandData];
    } else {
      _logs.add('待办数据格式无效');
      return;
    }

    int updatedCount = 0;
    for (final item in items) {
      if (item is! Map) continue;

      final id = item['id'] as String?;
      if (id == null) continue;

      // 读取手环发回的状态
      String? bandStatus = item['status'] as String?;
      int? bandIsCompleted = item['is_completed'] as int?;
      bool? bandIsCompletedBool = item['is_completed'] as bool?;

      bool newIsDone = false;
      if (bandStatus == 'done') {
        newIsDone = true;
      } else if (bandStatus == 'undone') {
        newIsDone = false;
      } else if (bandIsCompleted != null) {
        newIsDone = bandIsCompleted == 1;
      } else if (bandIsCompletedBool != null) {
        newIsDone = bandIsCompletedBool;
      } else {
        continue; // 没有状态信息，跳过
      }

      // 从数据库读取该待办
      final todos = await StorageService.getTodos(username);
      final todo = todos.firstWhere((t) => t.id == id,
          orElse: () => TodoItem(title: ''));
      if (todo.title.isEmpty) {
        _logs.add('未找到待办: $id');
        continue;
      }

      // 检查状态是否变化
      if (todo.isDone != newIsDone) {
        todo.isDone = newIsDone;
        todo.markAsChanged();
        // 保存时读取全部待办，更新后写回
        final allTodos = await StorageService.getTodos(username);
        final idx = allTodos.indexWhere((t) => t.id == id);
        if (idx != -1) {
          allTodos[idx] = todo;
        } else {
          allTodos.add(todo);
        }
        await StorageService.saveTodos(username, allTodos);
        updatedCount++;
        _logs.add('更新待办状态: ${todo.title} -> ${newIsDone ? "已完成" : "未完成"}');
      }
    }

    if (updatedCount == 0) {
      _logs.add('待办状态无需更新');
    } else {
      _logs.add('已更新 $updatedCount 条待办状态');
      // 刷新页面数据（如果有 todo 列表页面在显示的话）
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _syncTodos() async {
    setState(() => _isSyncing = true);
    _logs.add('开始同步待办...');

    final username = await _getUsername();
    if (username == null || username.isEmpty) {
      _logs.add('未登录，无法同步待办');
      setState(() => _isSyncing = false);
      return;
    }

    final todos = await StorageService.getTodos(username);

    // 只发送未完成的待办
    final todoMaps = todos
        .where((t) => !t.isDeleted && !t.isDone)
        .map((t) => {
              'id': t.id,
              'title': t.title,
              'content': t.title,
              'is_completed': t.isDone ? 1 : 0,
              'status': t.isDone ? 'done' : 'undone',
              'updated_at': t.updatedAt,
              'created_at': t.createdAt,
              'created_date': t.createdDate,
              'due_date': t.dueDate?.millisecondsSinceEpoch,
              'remark': t.remark ?? '',
              'priority': 'normal',
            })
        .toList();
    _logs.add('筛选后 ${todoMaps.length} 条待办数据');

    final success = await _sendInChunks('todo', todoMaps, 10);
    setState(() {
      _isSyncing = false;
      _logs.add(success ? '待办同步成功 (${todoMaps.length}条)' : '待办同步失败');
    });
  }

  Future<void> _syncCourses() async {
    setState(() => _isSyncing = true);
    _logs.add('开始同步课程...');

    final courses = await CourseService.getAllCourses();
    final now = DateTime.now();
    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    // 只发送今天及未来两周的课程，按日期精确匹配
    final twoWeeksLater = now.add(const Duration(days: 14));
    final courseMaps = courses.where((c) {
      try {
        final courseDate = DateTime.parse(c.date);
        return c.date.compareTo(todayStr) >= 0 &&
            courseDate.isBefore(twoWeeksLater);
      } catch (e) {
        return false;
      }
    }).map((c) {
      final startH = c.startTime ~/ 100;
      final startM = c.startTime % 100;
      final endH = c.endTime ~/ 100;
      final endM = c.endTime % 100;
      return {
        'id': '${c.courseName}_${c.date}_${startH}${startM}',
        'name': c.courseName,
        'courseName': c.courseName,
        'teacher': c.teacherName,
        'teacherName': c.teacherName,
        'location': c.roomName,
        'roomName': c.roomName,
        'weekday': c.weekday,
        'weekIndex': c.weekIndex,
        'date': c.date,
        'startTime':
            '${startH.toString().padLeft(2, '0')}:${startM.toString().padLeft(2, '0')}',
        'endTime':
            '${endH.toString().padLeft(2, '0')}:${endM.toString().padLeft(2, '0')}',
      };
    }).toList();
    _logs.add('筛选后 ${courseMaps.length} 条课程数据');

    final success = await _sendInChunks('course', courseMaps, 15);
    setState(() {
      _isSyncing = false;
      _logs.add(success ? '课程同步成功 (${courseMaps.length}条)' : '课程同步失败');
    });
  }

  Future<void> _syncCountdowns() async {
    setState(() => _isSyncing = true);
    _logs.add('开始同步倒计时...');

    final username = await _getUsername();
    if (username == null || username.isEmpty) {
      _logs.add('未登录，无法同步倒计时');
      setState(() => _isSyncing = false);
      return;
    }

    final countdowns = await StorageService.getCountdowns(username);
    final now = DateTime.now().millisecondsSinceEpoch;

    // 只发送未过期的倒计时
    final countdownMaps = countdowns
        .where(
            (c) => !c.isDeleted && c.targetDate.millisecondsSinceEpoch >= now)
        .map((c) => {
              'id': c.id,
              'title': c.title,
              'targetDate': c.targetDate.millisecondsSinceEpoch,
              'target_time': c.targetDate.millisecondsSinceEpoch,
              'updated_at': c.updatedAt,
            })
        .toList();
    _logs.add('筛选后 ${countdownMaps.length} 条倒计时数据');

    final success = await BandSyncService.syncCountdowns(countdownMaps);
    setState(() {
      _isSyncing = false;
      _logs.add(success ? '倒计时同步成功 (${countdownMaps.length}条)' : '倒计时同步失败');
    });
  }

  Future<void> _syncPomodoro() async {
    setState(() => _isSyncing = true);
    _logs.add('开始同步番茄钟...');

    try {
      final runState = await PomodoroService.loadRunState();
      if (runState == null || runState.phase == PomodoroPhase.idle) {
        _logs.add('当前无运行中的番茄钟');
        await BandSyncService.syncPomodoro([]);
        setState(() => _isSyncing = false);
        return;
      }

      final tags = await PomodoroService.getTags();
      final tagNames = tags
          .where((t) => runState.tagUuids.contains(t.uuid))
          .map((t) => {
                'name': t.name,
                'color': t.color,
              })
          .toList();

      final pomodoroData = [
        {
          'sessionUuid': runState.sessionUuid,
          'phase': runState.phase.index,
          'targetEndMs': runState.targetEndMs,
          'currentCycle': runState.currentCycle,
          'totalCycles': runState.totalCycles,
          'focusSeconds': runState.focusSeconds,
          'breakSeconds': runState.breakSeconds,
          'todoUuid': runState.todoUuid,
          'todoTitle': runState.todoTitle,
          'tagUuids': runState.tagUuids,
          'tagNames': tagNames,
          'sessionStartMs': runState.sessionStartMs,
          'plannedFocusSeconds': runState.plannedFocusSeconds,
          'isCountUp': runState.mode == TimerMode.countUp,
          'mode': runState.mode.index,
        }
      ];

      _logs.add('同步运行中的番茄钟: ${runState.todoTitle ?? "自由专注"}');
      final success = await BandSyncService.syncPomodoro(pomodoroData);
      setState(() {
        _isSyncing = false;
        _logs.add(success ? '番茄钟同步成功' : '番茄钟同步失败');
      });
    } catch (e) {
      _logs.add('番茄钟同步异常: $e');
      setState(() => _isSyncing = false);
    }
  }

  // 分批发送大数据，避免超过 MessageApi 限制
  Future<bool> _sendInChunks(
      String type, List<Map<String, dynamic>> items, int chunkSize) async {
    if (items.isEmpty) {
      return await BandSyncService.sendData(type, [],
          batchNum: 1, totalBatches: 1);
    }

    // 计算总批次数
    final totalBatches = (items.length / chunkSize).ceil();

    bool allSuccess = true;
    for (int i = 0; i < items.length; i += chunkSize) {
      final end = (i + chunkSize < items.length) ? i + chunkSize : items.length;
      final chunk = items.sublist(i, end);
      final batchNum = i ~/ chunkSize + 1;
      final jsonStr = jsonEncode(chunk);
      final sizeKb = (jsonStr.length / 1024).toStringAsFixed(1);
      _logs.add(
          '发送 ${type} 第 $batchNum/$totalBatches 批 (${chunk.length}条, ${sizeKb}KB)...');

      bool success = false;
      int retries = 2;
      while (retries >= 0 && !success) {
        success = await BandSyncService.sendData(type, chunk,
            batchNum: batchNum, totalBatches: totalBatches);
        if (!success && retries > 0) {
          _logs.add('第 $batchNum 批发送失败，重试...');
          await Future.delayed(const Duration(seconds: 1));
        }
        retries--;
      }

      if (!success) {
        allSuccess = false;
        _logs.add('第 $batchNum 批发送失败');
      }
      // 批次间间隔，避免 SDK 处理不过来
      await Future.delayed(const Duration(seconds: 1));
    }
    return allSuccess;
  }

  Future<void> _syncAll() async {
    setState(() => _isSyncing = true);
    _logs.add('开始全部同步...');
    await _syncTodos();
    await _syncCourses();
    await _syncCountdowns();
    await _syncPomodoro();
    setState(() {
      _isSyncing = false;
      _logs.add('全部同步完成');
    });
  }
}
