import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../services/file_open_service.dart';
import '../../services/lan_sync_pairing.dart';
import '../../services/lan_sync_service.dart';
import 'lan_qr_scanner_screen.dart';
import '../../services/permission_request_coordinator.dart';
import '../../utils/app_platform.dart';
import '../../widgets/floating_glass_control.dart';
import '../../widgets/optional_liquid_glass_surface.dart';
import '../../utils/app_dialogs.dart';

class LanSyncScreen extends StatefulWidget {
  final bool isEmbedded;
  const LanSyncScreen({super.key, this.isEmbedded = false});

  @override
  State<LanSyncScreen> createState() => _LanSyncScreenState();
}

class _LanSyncScreenState extends State<LanSyncScreen>
    with WidgetsBindingObserver {
  final LanSyncService _service = LanSyncService.instance;
  late final PermissionRequestCoordinator _permissionCoordinator;
  List<LanDevice> _devices = [];
  String _status = '未启动';
  String _progress = '';
  double _progressValue = 0;
  bool _isLoading = false;
  bool _discoverAll = false;
  bool _isDaemonMode = false;
  bool _autoSyncEnabled = true;
  bool _syncSecretsEnabled = true;
  bool _syncSettingsEnabled = false;

  StreamSubscription<List<LanDevice>>? _devicesSubscription;
  StreamSubscription<String>? _statusSubscription;
  StreamSubscription<String>? _progressSubscription;
  StreamSubscription<double>? _progressValueSubscription;
  StreamSubscription<LanDevice>? _incomingRequestSubscription;
  StreamSubscription<Map<String, String>>? _fileReceivedSubscription;
  StreamSubscription<LanSyncResult>? _quickPairCompletedSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _permissionCoordinator = PermissionRequestCoordinator(context: context);
    _devicesSubscription = _service.onDevicesChanged.listen((devices) {
      if (mounted) setState(() => _devices = List.from(devices));
    });
    _statusSubscription = _service.onStatusChanged.listen((status) {
      if (mounted) setState(() => _status = status);
    });
    _progressSubscription = _service.onSyncProgress.listen((progress) {
      if (mounted) setState(() => _progress = progress);
    });
    _progressValueSubscription = _service.onProgressChanged.listen((value) {
      if (mounted) setState(() => _progressValue = value);
    });
    _incomingRequestSubscription = _service.onIncomingRequest.listen(
      _showIncomingRequestDialog,
    );
    _fileReceivedSubscription = _service.onFileReceived.listen(
      _showFileReceivedDialog,
    );
    _quickPairCompletedSubscription = _service.onQuickPairCompleted.listen((
      result,
    ) {
      if (!mounted) return;
      AppSnackBars.showSnackBar(
        context,
        SnackBar(
          content: Text(
            '面对面同步完成: 待办${result.todosSynced} 倒数日${result.countdownsSynced} 时间日志${result.timeLogsSynced} 番茄标签${result.pomodoroTagsSynced} 番茄记录${result.pomodoroRecordsSynced} 课程${result.coursesSynced}',
          ),
          backgroundColor: Colors.green,
        ),
      );
    });

    _devices = _service.devices;
    _status = _service.isRunning
        ? (_service.isDaemonMode ? '常驻服务运行中（mDNS）' : '运行中')
        : '已停止';
    _discoverAll = _service.discoverAllDevices;
    _isDaemonMode = _service.isDaemonMode;
    _autoSyncEnabled = _service.autoSyncEnabled;
    _syncSecretsEnabled = _service.syncSecretsEnabled;
    _syncSettingsEnabled = _service.syncSettingsEnabled;
    _service.daemonRunningNotifier.addListener(_onDaemonRunningChanged);
    if (AppPlatform.isAndroid) {
      unawaited(_stopIfLocalNetworkAccessWasRevoked());
    }
  }

  void _onDaemonRunningChanged() {
    if (!mounted) return;
    setState(() {
      _isDaemonMode = _service.isDaemonMode;
      _status = _service.isRunning
          ? (_service.isDaemonMode ? '常驻服务运行中（mDNS）' : '运行中')
          : '已停止';
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && AppPlatform.isAndroid) {
      unawaited(_stopIfLocalNetworkAccessWasRevoked());
    }
  }

  Future<void> _stopIfLocalNetworkAccessWasRevoked() async {
    if (!_service.isRunning) return;

    final status = await _permissionCoordinator.status(
      AppPermissionKind.localNetwork,
    );
    if (status.isGranted || !_service.isRunning) return;

    await _service.stop();
    if (!mounted) return;
    setState(() => _status = '已停止');
    AppSnackBars.showSnackBar(
      context,
      const SnackBar(content: Text('局域网访问权限已撤销，局域网同步已停止。')),
    );
  }

  void _showFileReceivedDialog(Map<String, String> data) {
    if (!mounted) return;
    final name = data['name'] ?? '';
    final path = data['path'] ?? '';
    final from = data['from'] ?? '未知设备';

    showAppDialog(
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
              FileOpenService.open(path);
            },
            child: const Text('查看'),
          ),
        ],
      ),
    );
  }

  void _showIncomingRequestDialog(LanDevice device) {
    if (!mounted) return;
    showAppDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('连接请求'),
        content: Text('${device.deviceName} (${device.ip}) 请求与您同步数据'),
        actions: [
          TextButton(
            onPressed: () {
              _service.rejectIncomingRequest(device);
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
    bool syncSecrets = _syncSecretsEnabled;
    bool syncSettings = _syncSettingsEnabled;

    showAppDialog(
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
                CheckboxListTile(
                  title: const Text('API Key 与大模型配置'),
                  subtitle: const Text('仅通过局域网加密通道传输'),
                  value: syncSecrets,
                  onChanged: (v) => setDialogState(() => syncSecrets = v!),
                ),
                CheckboxListTile(
                  title: const Text('偏好设置（通知 / 界面 / 提醒）'),
                  value: syncSettings,
                  onChanged: (v) => setDialogState(() => syncSettings = v!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                if (isAccept) {
                  _service.rejectIncomingRequest(device);
                }
                Navigator.pop(context);
              },
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
                  syncSecrets: syncSecrets,
                  syncSettings: syncSettings,
                );
                if (isAccept) {
                  _confirmSync(device, config);
                } else {
                  if (!_isSameAccountDevice(device)) {
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
      AppSnackBars.showSnackBar(
        context,
        SnackBar(
          content: Text(
            result.success
                ? '同步成功: 待办${result.todosSynced} 倒数日${result.countdownsSynced} 时间日志${result.timeLogsSynced} 番茄标签${result.pomodoroTagsSynced} 番茄记录${result.pomodoroRecordsSynced} 课程${result.coursesSynced}'
                : result.message,
          ),
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
      if (AppPlatform.isAndroid) {
        final permission = await _permissionCoordinator.request(
          AppPermissionKind.localNetwork,
        );
        if (!mounted) return;
        if (!permission.granted) {
          AppSnackBars.showSnackBar(
            context,
            const SnackBar(content: Text('未获得局域网访问权限，局域网同步未启动。')),
          );
          return;
        }
      }
      await _service.start();
    }
    if (mounted) {
      setState(() {
        _status = _service.isRunning ? '运行中' : '已停止';
      });
    }
  }

  bool _isSameAccountDevice(LanDevice device) =>
      LanDiscoveryIdentity.isSameUser(device.userId, _service.currentUserId);

  void _showCrossAccountWarning(LanDevice device, LanSyncConfig config) {
    showAppDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('账号不匹配'),
        content: const Text(
          '该设备登录的是其他账号，数据同步（加密）可能会失败。是否继续尝试？\n\n提示：\n1. 建议跨账号使用“发送文件”功能。\n2. 若要同步，请确保对方设备也将“搜索范围”设置为“所有设备”，否则连接会被拒绝。',
        ),
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
        AppSnackBars.showSnackBar(
          context,
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
    if (AppPlatform.isWeb) {
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('浏览器暂不支持局域网文件发送')),
      );
      return;
    }
    try {
      final pickedFile = await FilePicker.pickFile();
      if (pickedFile?.path != null) {
        setState(() => _isLoading = true);
        final syncResult = await _service.sendFilePath(
          device,
          pickedFile!.path!,
        );
        if (mounted) {
          setState(() {
            _isLoading = false;
            _progressValue = 0;
          });
          AppSnackBars.showSnackBar(
            context,
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
        AppSnackBars.showSnackBar(
          context,
          SnackBar(content: Text('选择文件失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showManualAddDialog() {
    final ipController = TextEditingController();
    final portController = TextEditingController(text: '54322');
    showAppDialog(
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

  Future<bool> _ensureLocalNetworkPermission() async {
    if (!AppPlatform.isAndroid) return true;
    final permission = await _permissionCoordinator.request(
      AppPermissionKind.localNetwork,
    );
    if (!mounted) return false;
    if (!permission.granted) {
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('未获得局域网访问权限，局域网同步未启动。')),
      );
      return false;
    }
    return true;
  }

  Future<void> _showQuickPairQrDialog() async {
    if (!await _ensureLocalNetworkPermission()) return;
    if (!mounted) return;
    setState(() => _isLoading = true);
    var payload = await _service.startQuickPairSession();
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _status = _service.isRunning ? '运行中' : _status;
    });

    if (payload == null) {
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(
          content: Text('无法获取本机局域网 IP 或启动临时服务'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    await showAppDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final currentPayload = payload!;
          final uriString = currentPayload.toUriString();
          return AlertDialog(
            title: const Text('面对面同步二维码'),
            content: SizedBox(
              width: 280,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: QrImageView(
                      data: uriString,
                      version: QrVersions.auto,
                      size: 200,
                      backgroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${currentPayload.ip}:${currentPayload.port}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '一次性令牌 5 分钟内有效，另一台设备扫码或粘贴配对码即可直接互同步。',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton.icon(
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('刷新'),
                onPressed: () async {
                  final next = await _service.startQuickPairSession();
                  if (next != null && context.mounted) {
                    setDialogState(() => payload = next);
                  }
                },
              ),
              TextButton.icon(
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('复制配对码'),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: uriString));
                  if (context.mounted) {
                    AppSnackBars.showSnackBar(
                      context,
                      const SnackBar(content: Text('已复制配对码')),
                    );
                  }
                },
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('关闭'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showEnterPairingCodeDialog() async {
    final codeController = TextEditingController();
    try {
      await showAppDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('连接面对面设备'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '粘贴或输入对方“面对面同步二维码”中的配对码（cdt-lan://...）：',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: codeController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'cdt-lan://sync?...',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.paste),
                    tooltip: '从剪贴板粘贴',
                    onPressed: () async {
                      final clip = await Clipboard.getData(
                        Clipboard.kTextPlain,
                      );
                      if (clip?.text != null) {
                        codeController.text = clip!.text!.trim();
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.sync, size: 18),
              label: const Text('立即互同步'),
              onPressed: () async {
                final raw = codeController.text.trim();
                if (raw.isEmpty) return;
                Navigator.pop(dialogContext);
                await _syncWithPairingCodeAndShowResult(raw);
              },
            ),
          ],
        ),
      );
    } finally {
      codeController.dispose();
    }
  }

  Future<void> _scanQrAndSync() async {
    final scanned = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const LanQrScannerScreen()),
    );
    if (!mounted || scanned == null || scanned.trim().isEmpty) return;
    await _syncWithPairingCodeAndShowResult(scanned.trim());
  }

  Future<void> _syncWithPairingCodeAndShowResult(String raw) async {
    setState(() => _isLoading = true);
    final result = await _service.syncWithPairingCode(raw);
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _progressValue = 0;
    });
    AppSnackBars.showSnackBar(
      context,
      SnackBar(
        content: Text(
          result.success
              ? '面对面同步成功: 待办${result.todosSynced} 倒数日${result.countdownsSynced} 时间日志${result.timeLogsSynced} 番茄标签${result.pomodoroTagsSynced} 番茄记录${result.pomodoroRecordsSynced} 课程${result.coursesSynced}'
              : result.message,
        ),
        backgroundColor: result.success ? Colors.green : Colors.red,
      ),
    );
  }

  Widget _buildQuickPairBar() {
    final colorScheme = Theme.of(context).colorScheme;
    final supportsCameraScan =
        AppPlatform.isAndroid || AppPlatform.isIOS || AppPlatform.isMacOS;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.tonalIcon(
              icon: const Icon(Icons.qr_code_2, size: 18),
              label: const Text('生成同步二维码'),
              onPressed: _isLoading ? null : _showQuickPairQrDialog,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              icon: Icon(
                Icons.qr_code_scanner,
                size: 18,
                color: colorScheme.primary,
              ),
              label: Text(supportsCameraScan ? '扫码互同步' : '输入配对码'),
              onPressed: _isLoading
                  ? null
                  : (supportsCameraScan
                        ? _scanQrAndSync
                        : _showEnterPairingCodeDialog),
            ),
          ),
          if (supportsCameraScan) ...[
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.keyboard_alt_outlined),
              tooltip: '手动输入配对码',
              onPressed: _isLoading ? null : _showEnterPairingCodeDialog,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDesktopAndAutoSyncCard() {
    if (AppPlatform.isWeb) return const SizedBox.shrink();
    final isDesktop =
        AppPlatform.isWindows || AppPlatform.isMacOS || AppPlatform.isLinux;
    final colorScheme = Theme.of(context).colorScheme;
    return OptionalLiquidGlassCard(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      borderRadius: 12,
      fallbackDecoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isDesktop)
            LiquidGlassSwitchListTile(
              dense: true,
              secondary: const Icon(Icons.dns_outlined, size: 20),
              title: const Text('桌面端常驻局域网服务'),
              subtitle: const Text('关闭页面或最小化到托盘后保持运行（mDNS）'),
              value: _isDaemonMode,
              onChanged: (value) async {
                setState(() => _isDaemonMode = value);
                await _service.setDesktopDaemonEnabled(value);
                if (mounted) {
                  setState(() {
                    _status = _service.isRunning ? '常驻服务运行中（mDNS）' : '已停止';
                  });
                }
              },
            ),
          LiquidGlassSwitchListTile(
            dense: true,
            secondary: const Icon(Icons.autorenew, size: 20),
            title: const Text('同账号自动无感同步'),
            subtitle: const Text('连上同一 Wi-Fi 发现同账号设备后静默合并数据'),
            value: _autoSyncEnabled,
            onChanged: (value) async {
              setState(() => _autoSyncEnabled = value);
              await _service.setAutoSyncEnabled(value);
            },
          ),
          LiquidGlassSwitchListTile(
            dense: true,
            secondary: const Icon(Icons.key_outlined, size: 20),
            title: const Text('同步 API Key 与大模型配置'),
            subtitle: const Text('仅通过局域网加密通道传输，补充缺失配置'),
            value: _syncSecretsEnabled,
            onChanged: (value) async {
              setState(() => _syncSecretsEnabled = value);
              await _service.setSyncSecretsEnabled(value);
            },
          ),
          LiquidGlassSwitchListTile(
            dense: true,
            secondary: const Icon(Icons.tune_outlined, size: 20),
            title: const Text('同步应用偏好设置'),
            subtitle: const Text('默认关闭，开启后仅补充本机尚未设置的通知与界面偏好'),
            value: _syncSettingsEnabled,
            onChanged: (value) async {
              setState(() => _syncSettingsEnabled = value);
              await _service.setSyncSettingsEnabled(value);
            },
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
      extendBodyBehindAppBar: !widget.isEmbedded,
      appBar: widget.isEmbedded
          ? null
          : FloatingGlassAppBar(
              flexibleSpace: const FloatingGlassTopBarBackground(),
              title: const Text('局域网同步'),
              actions: [
                if (_service.isRunning && _devices.isEmpty)
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: _showManualAddDialog,
                    tooltip: '手动添加设备',
                  ),
                IconButton(
                  icon: Icon(
                    _service.isRunning ? Icons.stop : Icons.play_arrow,
                  ),
                  onPressed: _toggleService,
                  tooltip: _service.isRunning ? '停止' : '启动',
                ),
              ],
            ),
      body: floatingGlassSettingsBody(
        context,
        standalone: !widget.isEmbedded,
        child: Padding(
          padding: EdgeInsets.only(
            top: widget.isEmbedded
                ? 0
                : floatingGlassSettingsContentTopInset(context),
          ),
          child: Column(
            children: [
              Expanded(
                child: MediaQuery.removePadding(
                  context: context,
                  removeTop: true,
                  child: CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildStatusCard(),
                            _buildQuickPairBar(),
                            _buildDesktopAndAutoSyncCard(),
                            _buildFilterBar(),
                            const Divider(height: 1),
                          ],
                        ),
                      ),
                      if (_devices.isEmpty)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              24,
                              32,
                              24,
                              MediaQuery.paddingOf(context).bottom + 24,
                            ),
                            child: Center(
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
                                        ? (_discoverAll
                                              ? '未发现任何设备'
                                              : '未发现同账号设备')
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
                            ),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(
                            0,
                            8,
                            0,
                            MediaQuery.paddingOf(context).bottom + 8,
                          ),
                          sliver: SliverList.builder(
                            findChildIndexCallback: (Key key) {
                              if (key is ValueKey<String>) {
                                final id = key.value;
                                final index = _devices.indexWhere(
                                  (d) => d.deviceId == id,
                                );
                                return index != -1 ? index : null;
                              }
                              return null;
                            },
                            itemCount: _devices.length,
                            itemBuilder: (context, index) {
                              final device = _devices[index];
                              return _buildDeviceTile(device);
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (_progress.isNotEmpty) _buildProgressBanner(),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _service.daemonRunningNotifier.removeListener(_onDaemonRunningChanged);
    // 桌面端常驻或同账号无感同步开启时，关闭页面后继续保持 HTTP + mDNS 监听。
    if (!_service.isDaemonMode && !_service.autoSyncEnabled) {
      unawaited(_service.stop());
    }
    unawaited(_devicesSubscription?.cancel());
    unawaited(_statusSubscription?.cancel());
    unawaited(_progressSubscription?.cancel());
    unawaited(_progressValueSubscription?.cancel());
    unawaited(_incomingRequestSubscription?.cancel());
    unawaited(_fileReceivedSubscription?.cancel());
    unawaited(_quickPairCompletedSubscription?.cancel());
    _permissionCoordinator.dispose();
    super.dispose();
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
              if (widget.isEmbedded && _service.isRunning && _devices.isEmpty)
                IconButton(
                  icon: const Icon(Icons.add, size: 20),
                  onPressed: _showManualAddDialog,
                  tooltip: '手动添加设备',
                ),
              if (widget.isEmbedded)
                IconButton(
                  icon: Icon(
                    _service.isRunning ? Icons.stop : Icons.play_arrow,
                    size: 20,
                  ),
                  onPressed: _toggleService,
                  tooltip: _service.isRunning ? '停止' : '启动',
                  color: _service.isRunning ? Colors.red : Colors.green,
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

    return RepaintBoundary(
      key: ValueKey<String>(device.deviceId),
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: CircleAvatar(
                backgroundColor: isOnline
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey,
                child: const Icon(Icons.devices, color: Colors.white),
              ),
              title: Row(
                children: [
                  Text(device.deviceName),
                  if (!_isSameAccountDevice(device)) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
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
                      onPressed: !isOnline
                          ? null
                          : () => _pickAndSendFile(device),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.primary,
                        side: BorderSide(
                          color: Theme.of(context).colorScheme.primary,
                        ),
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
                          : (!_isSameAccountDevice(device)
                                ? () => _showCrossAccountWarning(
                                    device,
                                    LanSyncConfig(),
                                  )
                                : () => _showSelectSyncTypeDialog(device)),
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

  Widget _buildProgressBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
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
                child: Text(_progress, style: const TextStyle(fontSize: 13)),
              ),
              Text(
                '${(_progressValue * 100).toInt()}%',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: _progressValue,
            backgroundColor: Colors.grey[300],
            valueColor: AlwaysStoppedAnimation<Color>(
              Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}
