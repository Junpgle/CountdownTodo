import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_file/open_file.dart';
import '../../services/lan_sync_service.dart';

class LanSyncScreen extends StatefulWidget {
  const LanSyncScreen({super.key});

  @override
  State<LanSyncScreen> createState() => _LanSyncScreenState();
}

class _LanSyncScreenState extends State<LanSyncScreen> {
  final LanSyncService _service = LanSyncService.instance;
  List<LanDevice> _devices = [];
  String _status = '未启动';
  String _progress = '';
  double _progressValue = 0;
  bool _isLoading = false;
  bool _discoverAll = false;

  @override
  void initState() {
    super.initState();
    _service.onDevicesChanged.listen((devices) {
      if (mounted) setState(() => _devices = List.from(devices));
    });
    _service.onStatusChanged.listen((status) {
      if (mounted) setState(() => _status = status);
    });
    _service.onSyncProgress.listen((progress) {
      if (mounted) setState(() => _progress = progress);
    });
    _service.onProgressChanged.listen((value) {
      if (mounted) setState(() => _progressValue = value);
    });
    _service.onIncomingRequest.listen(_showIncomingRequestDialog);
    _service.onFileReceived.listen(_showFileReceivedDialog);

    _devices = _service.devices;
    _status = _service.isRunning ? '运行中' : '已停止';
    _discoverAll = _service.discoverAllDevices;
  }

  void _showFileReceivedDialog(Map<String, String> data) {
    if (!mounted) return;
    final name = data['name'] ?? '';
    final path = data['path'] ?? '';
    final from = data['from'] ?? '未知设备';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('收到文件'),
        content: Text('来自 $from 的文件: $name\n是否立即查看？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('稍后'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              OpenFile.open(path);
            },
            child: const Text('查看'),
          ),
        ],
      ),
    );
  }

  void _showIncomingRequestDialog(LanDevice device) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('连接请求'),
        content: Text('${device.deviceName} (${device.ip}) 请求与您同步数据'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text('拒绝'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showSelectSyncTypeDialog(device, isAccept: true);
            },
            child: const Text('接受'),
          ),
        ],
      ),
    );
  }

  void _showSelectSyncTypeDialog(LanDevice device, {bool isAccept = false}) {
    bool syncTodos = true;
    bool syncCountdowns = true;
    bool syncTimeLogs = true;
    bool syncPomodoroTags = true;
    bool syncPomodoroRecords = true;
    bool syncCourses = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(isAccept ? '选择接收数据类型' : '选择同步数据类型'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CheckboxListTile(
                  title: const Text('待办'),
                  value: syncTodos,
                  onChanged: (v) => setDialogState(() => syncTodos = v!),
                ),
                CheckboxListTile(
                  title: const Text('倒数日'),
                  value: syncCountdowns,
                  onChanged: (v) => setDialogState(() => syncCountdowns = v!),
                ),
                CheckboxListTile(
                  title: const Text('时间日志'),
                  value: syncTimeLogs,
                  onChanged: (v) => setDialogState(() => syncTimeLogs = v!),
                ),
                CheckboxListTile(
                  title: const Text('番茄标签'),
                  value: syncPomodoroTags,
                  onChanged: (v) => setDialogState(() => syncPomodoroTags = v!),
                ),
                CheckboxListTile(
                  title: const Text('番茄记录'),
                  value: syncPomodoroRecords,
                  onChanged: (v) =>
                      setDialogState(() => syncPomodoroRecords = v!),
                ),
                CheckboxListTile(
                  title: const Text('课程'),
                  value: syncCourses,
                  onChanged: (v) => setDialogState(() => syncCourses = v!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                final config = LanSyncConfig(
                  syncTodos: syncTodos,
                  syncCountdowns: syncCountdowns,
                  syncTimeLogs: syncTimeLogs,
                  syncPomodoroTags: syncPomodoroTags,
                  syncPomodoroRecords: syncPomodoroRecords,
                  syncCourses: syncCourses,
                );
                if (isAccept) {
                  _confirmSync(device, config);
                } else {
                  if (device.userId != _service.currentUserId) {
                    _showCrossAccountWarning(device, config);
                  } else {
                    _requestSync(device, config);
                  }
                }
              },
              child: const Text('确认'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmSync(LanDevice device, LanSyncConfig config) async {
    setState(() => _isLoading = true);
    final result = await _service.confirmAndSync(device, config: config);
    if (mounted) {
      setState(() {
        _isLoading = false;
        _progressValue = 0;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.success
              ? '同步成功: 待办${result.todosSynced} 倒数日${result.countdownsSynced} 时间日志${result.timeLogsSynced} 番茄标签${result.pomodoroTagsSynced} 番茄记录${result.pomodoroRecordsSynced} 课程${result.coursesSynced}'
              : result.message),
          backgroundColor: result.success ? Colors.green : Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _toggleService() async {
    if (_service.isRunning) {
      await _service.stop();
    } else {
      await _service.start();
    }
    if (mounted) {
      setState(() {
        _status = _service.isRunning ? '运行中' : '已停止';
      });
    }
  }

  void _showCrossAccountWarning(LanDevice device, LanSyncConfig config) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('账号不匹配'),
        content: const Text('该设备登录的是其他账号，数据同步（加密）可能会失败。是否继续尝试？\n\n提示：\n1. 建议跨账号使用“发送文件”功能。\n2. 若要同步，请确保对方设备也将“搜索范围”设置为“所有设备”，否则连接会被拒绝。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _requestSync(device, config);
            },
            child: const Text('继续'),
          ),
        ],
      ),
    );
  }

  Future<void> _requestSync(LanDevice device, LanSyncConfig config) async {
    setState(() => _isLoading = true);
    final result = await _service.syncWithDevice(device, config: config);
    if (mounted) {
      setState(() => _isLoading = false);
      if (!result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _pickAndSendFile(LanDevice device) async {
    try {
      final result = await FilePicker.platform.pickFiles();
      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        setState(() => _isLoading = true);
        final syncResult = await _service.sendFile(device, file);
        if (mounted) {
          setState(() {
            _isLoading = false;
            _progressValue = 0;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(syncResult.message),
              backgroundColor: syncResult.success ? Colors.green : Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('选择文件失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showManualAddDialog() {
    final ipController = TextEditingController();
    final portController = TextEditingController(text: '54322');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('手动添加设备'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ipController,
              decoration: const InputDecoration(
                labelText: 'IP地址',
                hintText: '192.168.1.100',
              ),
            ),
            TextField(
              controller: portController,
              decoration: const InputDecoration(
                labelText: '端口',
                hintText: '54322',
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              final ip = ipController.text.trim();
              final port = int.tryParse(portController.text) ?? 54322;
              if (ip.isNotEmpty) {
                final device = LanDevice(
                  deviceId: 'manual_$ip',
                  userId: _service.devices.isNotEmpty
                      ? _service.devices.first.userId
                      : '',
                  deviceName: '手动添加',
                  ip: ip,
                  port: port,
                  lastSeen: DateTime.now().millisecondsSinceEpoch,
                );
                Navigator.pop(context);
                _showSelectSyncTypeDialog(device);
              }
            },
            child: const Text('请求连接'),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    if (!_service.isRunning) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Text('搜索范围:', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 12),
          ChoiceChip(
            label: const Text('仅同账号'),
            selected: !_discoverAll,
            onSelected: (selected) {
              if (selected) {
                setState(() => _discoverAll = false);
                _service.discoverAllDevices = false;
              }
            },
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text('所有设备'),
            selected: _discoverAll,
            onSelected: (selected) {
              if (selected) {
                setState(() => _discoverAll = true);
                _service.discoverAllDevices = true;
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('局域网同步'),
        actions: [
          if (_service.isRunning && _devices.isEmpty)
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: _showManualAddDialog,
              tooltip: '手动添加设备',
            ),
          IconButton(
            icon: Icon(_service.isRunning ? Icons.stop : Icons.play_arrow),
            onPressed: _toggleService,
            tooltip: _service.isRunning ? '停止' : '启动',
          ),
        ],
      ),
      body: Column(
        children: [
          _buildStatusCard(),
          _buildFilterBar(),
          const Divider(height: 1),
          Expanded(
            child: _devices.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.devices_other,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _service.isRunning
                              ? (_discoverAll ? '未发现任何设备' : '未发现同账号设备')
                              : '请先启动服务',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 16,
                          ),
                        ),
                        if (_service.isRunning) ...[
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.add),
                            label: const Text('手动添加设备'),
                            onPressed: _showManualAddDialog,
                          ),
                        ],
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _devices.length,
                    itemBuilder: (context, index) {
                      final device = _devices[index];
                      return _buildDeviceTile(device);
                    },
                  ),
          ),
          if (_progress.isNotEmpty) _buildProgressBanner(),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _service.isRunning
            ? Colors.green.withValues(alpha: 0.1)
            : Colors.grey.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _service.isRunning ? Colors.green : Colors.grey,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _service.isRunning ? Icons.wifi_tethering : Icons.wifi_off,
                color: _service.isRunning ? Colors.green : Colors.grey,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _status,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    if (_service.localIp != null)
                      Text(
                        '本机IP: ${_service.localIp}',
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                  ],
                ),
              ),
              if (_service.isRunning)
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: _service.isSyncing
                      ? null
                      : () => _service.triggerDiscovery(),
                  tooltip: '重新扫描',
                ),
              if (_service.isSyncing)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '设备: ${_devices.length} 台',
            style: TextStyle(color: Colors.grey[700]),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceTile(LanDevice device) {
    final lastSeen = DateTime.now().millisecondsSinceEpoch - device.lastSeen;
    final isOnline = lastSeen < 15000;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor: isOnline ? Colors.blue : Colors.grey,
              child: const Icon(Icons.devices, color: Colors.white),
            ),
            title: Row(
              children: [
                Text(device.deviceName),
                if (device.userId != _service.currentUserId) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.orange, width: 0.5),
                    ),
                    child: const Text(
                      '其他账号',
                      style: TextStyle(color: Colors.orange, fontSize: 10),
                    ),
                  ),
                ],
              ],
            ),
            subtitle: Text(
              '${device.ip}:${device.port} • ${isOnline ? "在线" : "可能已离线"}',
              style: TextStyle(
                color: isOnline ? null : Colors.grey,
                fontSize: 12,
              ),
            ),
            trailing: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
          ),
          Padding(
            padding: const EdgeInsets.only(left: 72, right: 16, bottom: 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.file_upload, size: 18),
                    label: const Text('发送文件'),
                    onPressed:
                        !isOnline ? null : () => _pickAndSendFile(device),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blue,
                      side: const BorderSide(color: Colors.blue),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.sync, size: 18),
                    label: const Text('同步数据'),
                    onPressed: !isOnline
                        ? null
                        : (device.userId != _service.currentUserId
                            ? () =>
                                _showCrossAccountWarning(device, LanSyncConfig())
                            : () => _showSelectSyncTypeDialog(device)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: Colors.blue.withValues(alpha: 0.1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _progress,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              Text(
                '${(_progressValue * 100).toInt()}%',
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: _progressValue,
            backgroundColor: Colors.grey[300],
            valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
          ),
        ],
      ),
    );
  }
}
