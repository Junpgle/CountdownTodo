import 'dart:async';

import 'package:flutter/material.dart';

import '../../../services/api_service.dart';
import '../../../services/storage/user_session_storage.dart';
import '../../../utils/app_dialogs.dart';
import '../../../widgets/app_state_views.dart';
import '../../../widgets/floating_glass_control.dart';
import '../../../widgets/optional_liquid_glass_surface.dart';

class AccountDevicesPage extends StatefulWidget {
  final bool isEmbedded;
  final Future<void> Function()? syncCurrentDevice;
  final Future<Map<String, dynamic>> Function()? fetchDevices;
  final Future<Map<String, dynamic>> Function(String deviceId)? sendKickCode;
  final Future<Map<String, dynamic>> Function(String deviceId, String code)?
  kickDevice;

  const AccountDevicesPage({
    super.key,
    this.isEmbedded = false,
    this.syncCurrentDevice,
    this.fetchDevices,
    this.sendKickCode,
    this.kickDevice,
  });

  @override
  State<AccountDevicesPage> createState() => _AccountDevicesPageState();
}

class _AccountDevicesPageState extends State<AccountDevicesPage> {
  bool _loading = true;
  String? _error;
  String _maskedEmail = '';
  List<Map<String, dynamic>> _devices = const [];

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    await (widget.syncCurrentDevice ??
        UserSessionStorage.syncCurrentDeviceRegistration)();
    final res = await (widget.fetchDevices ?? ApiService.fetchLoginDevices)();
    if (!mounted) return;

    if (res['success'] == true) {
      setState(() {
        _maskedEmail = (res['masked_email'] ?? '').toString();
        _devices = List<Map<String, dynamic>>.from(
          res['devices'] as List? ?? const [],
        );
        _loading = false;
      });
    } else {
      setState(() {
        _error = (res['message'] ?? '加载登录设备失败').toString();
        _loading = false;
      });
    }
  }

  Future<void> _onKickPressed(Map<String, dynamic> device) async {
    final deviceId = (device['device_id'] ?? '').toString();
    if (deviceId.isEmpty) return;

    final deviceName = _resolveDeviceTitle(device);
    final kicked = await showAppDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _KickDeviceVerificationDialog(
        deviceId: deviceId,
        deviceName: deviceName,
        maskedEmail: _maskedEmail,
        sendKickCode: widget.sendKickCode ?? ApiService.sendKickDeviceCode,
        kickDevice: widget.kickDevice ?? ApiService.kickDevice,
      ),
    );

    if (kicked == true && mounted) {
      AppSnackBars.showSnackBar(
        context,
        SnackBar(content: Text('已将「$deviceName」踢出登录')),
      );
      await _loadDevices();
    }
  }

  String _resolveDeviceTitle(Map<String, dynamic> device) {
    final name = (device['device_name'] ?? '').toString().trim();
    if (name.isNotEmpty) return name;
    final platform = (device['platform'] ?? '').toString().toLowerCase();
    return switch (platform) {
      'android' => 'Android 设备',
      'ios' => 'iOS 设备',
      'macos' => 'macOS 设备',
      'windows' => 'Windows 设备',
      'linux' => 'Linux 设备',
      'web' => 'Web 浏览器',
      _ => '未知设备',
    };
  }

  IconData _resolvePlatformIcon(String platform) {
    return switch (platform.toLowerCase()) {
      'android' => Icons.phone_android_rounded,
      'ios' => Icons.phone_iphone_rounded,
      'macos' => Icons.laptop_mac_rounded,
      'windows' => Icons.desktop_windows_rounded,
      'linux' => Icons.computer_rounded,
      'web' => Icons.language_rounded,
      _ => Icons.devices_other_rounded,
    };
  }

  String _formatLastSeen(dynamic rawMs) {
    final ms = rawMs is int ? rawMs : int.tryParse(rawMs?.toString() ?? '');
    if (ms == null || ms <= 0) return '未知';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    if (diff.inDays < 7) return '${diff.inDays} 天前';
    final month = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '${dt.year}-$month-$day $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final body = _loading
        ? const Center(child: AppLoadingIndicator())
        : _error != null
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline, size: 48, color: colorScheme.error),
                  const SizedBox(height: 12),
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _loadDevices,
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),
          )
        : RefreshIndicator(
            onRefresh: _loadDevices,
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                16,
                floatingGlassSettingsContentTopInset(context),
                16,
                24,
              ),
              children: [
                _buildOverviewCard(colorScheme),
                const SizedBox(height: 16),
                if (_devices.isEmpty)
                  _buildEmptyCard(colorScheme)
                else
                  ..._devices.map(
                    (device) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildDeviceCard(device, colorScheme),
                    ),
                  ),
              ],
            ),
          );

    return Scaffold(
      extendBodyBehindAppBar: !widget.isEmbedded,
      appBar: widget.isEmbedded
          ? null
          : FloatingGlassAppBar(
              flexibleSpace: const FloatingGlassTopBarBackground(),
              title: const Text('登录设备管理'),
              actions: [
                IconButton(
                  tooltip: '刷新',
                  onPressed: _loading ? null : _loadDevices,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
      body: floatingGlassSettingsBody(
        context,
        standalone: !widget.isEmbedded,
        child: body,
      ),
    );
  }

  Widget _buildOverviewCard(ColorScheme colorScheme) {
    return OptionalLiquidGlassCard(
      borderRadius: 16,
      highContrast: true,
      fallbackDecoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.verified_user_outlined,
                color: colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '当前共 ${_devices.length} 台活跃设备',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _maskedEmail.isNotEmpty
                        ? '绑定邮箱 $_maskedEmail · 踢出设备需通过邮箱验证码确认'
                        : '踢出设备需通过绑定邮箱验证码确认',
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurfaceVariant,
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

  Widget _buildEmptyCard(ColorScheme colorScheme) {
    return OptionalLiquidGlassCard(
      borderRadius: 16,
      highContrast: true,
      fallbackDecoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              Icons.devices_rounded,
              size: 40,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              '暂无已记录的登录设备',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceCard(
    Map<String, dynamic> device,
    ColorScheme colorScheme,
  ) {
    final platform = (device['platform'] ?? 'unknown').toString();
    final version = (device['app_version'] ?? 'unknown').toString();
    final ip = (device['ip_address'] ?? '').toString();
    final isCurrent = device['is_current'] == true;
    final isOnline = device['is_online'] == true;
    final title = _resolveDeviceTitle(device);
    final lastSeenText = _formatLastSeen(device['last_seen_at']);

    return OptionalLiquidGlassCard(
      borderRadius: 16,
      highContrast: true,
      fallbackDecoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: isCurrent
            ? Border.all(color: colorScheme.primary.withValues(alpha: 0.45))
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: isCurrent
                      ? colorScheme.primaryContainer
                      : colorScheme.surfaceContainerHighest,
                  child: Icon(
                    _resolvePlatformIcon(platform),
                    color: isCurrent
                        ? colorScheme.onPrimaryContainer
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (isCurrent)
                            _buildBadge(
                              '当前设备',
                              colorScheme.primaryContainer,
                              colorScheme.onPrimaryContainer,
                            ),
                          if (isOnline)
                            _buildBadge(
                              '在线',
                              colorScheme.tertiaryContainer,
                              colorScheme.onTertiaryContainer,
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${platform.toUpperCase()}${version != 'unknown' ? ' · v$version' : ''}',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isCurrent)
                  OutlinedButton.icon(
                    onPressed: () => _onKickPressed(device),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colorScheme.error,
                      side: BorderSide(
                        color: colorScheme.error.withValues(alpha: 0.5),
                      ),
                    ),
                    icon: const Icon(Icons.logout_rounded, size: 16),
                    label: const Text('踢出'),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  Icons.access_time_rounded,
                  size: 14,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  '最近活跃: $lastSeenText',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                if (ip.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'IP: $ip',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBadge(String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }
}

class _KickDeviceVerificationDialog extends StatefulWidget {
  final String deviceId;
  final String deviceName;
  final String maskedEmail;
  final Future<Map<String, dynamic>> Function(String deviceId) sendKickCode;
  final Future<Map<String, dynamic>> Function(String deviceId, String code)
  kickDevice;

  const _KickDeviceVerificationDialog({
    required this.deviceId,
    required this.deviceName,
    required this.maskedEmail,
    required this.sendKickCode,
    required this.kickDevice,
  });

  @override
  State<_KickDeviceVerificationDialog> createState() =>
      _KickDeviceVerificationDialogState();
}

class _KickDeviceVerificationDialogState
    extends State<_KickDeviceVerificationDialog> {
  final TextEditingController _codeController = TextEditingController();
  Timer? _countdownTimer;
  int _secondsLeft = 0;
  bool _sendingCode = false;
  bool _submitting = false;
  String? _errorText;
  String? _infoText;

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _codeController.dispose();
    super.dispose();
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    setState(() => _secondsLeft = 60);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_secondsLeft <= 1) {
        timer.cancel();
        setState(() => _secondsLeft = 0);
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  Future<void> _sendCode() async {
    if (_sendingCode || _secondsLeft > 0) return;
    setState(() {
      _sendingCode = true;
      _errorText = null;
      _infoText = null;
    });

    final res = await widget.sendKickCode(widget.deviceId);
    if (!mounted) return;

    setState(() => _sendingCode = false);
    if (res['success'] == true) {
      final emailHint = (res['masked_email'] ?? widget.maskedEmail).toString();
      setState(() {
        _infoText = emailHint.isNotEmpty
            ? '验证码已发送至 $emailHint'
            : '验证码已发送至您的绑定邮箱';
      });
      _startCountdown();
    } else {
      setState(() {
        _errorText = (res['message'] ?? '发送验证码失败').toString();
      });
    }
  }

  Future<void> _submitKick() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() => _errorText = '请输入邮箱验证码');
      return;
    }
    setState(() {
      _submitting = true;
      _errorText = null;
    });

    final res = await widget.kickDevice(widget.deviceId, code);
    if (!mounted) return;

    setState(() => _submitting = false);
    if (res['success'] == true) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _errorText = (res['message'] ?? '踢出设备失败').toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final emailLabel = widget.maskedEmail.isNotEmpty
        ? widget.maskedEmail
        : '绑定邮箱';

    return AlertDialog(
      title: const Text('验证邮箱并踢出设备'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '确认将「${widget.deviceName}」踢下线？该设备将被立即强制退出，需要重新输入密码才能登录。',
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '安全验证邮箱：$emailLabel',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _codeController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: const InputDecoration(
                      labelText: '邮箱验证码',
                      hintText: '6 位数字',
                      counterText: '',
                      prefixIcon: Icon(Icons.mark_email_read_outlined),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: OutlinedButton(
                    onPressed: (_sendingCode || _secondsLeft > 0)
                        ? null
                        : _sendCode,
                    child: _sendingCode
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_secondsLeft > 0 ? '${_secondsLeft}s' : '获取验证码'),
                  ),
                ),
              ],
            ),
            if (_infoText != null) ...[
              const SizedBox(height: 8),
              Text(
                _infoText!,
                style: TextStyle(fontSize: 12, color: colorScheme.primary),
              ),
            ],
            if (_errorText != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorText!,
                style: TextStyle(fontSize: 12, color: colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting
              ? null
              : () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: colorScheme.error,
            foregroundColor: colorScheme.onError,
          ),
          onPressed: _submitting ? null : _submitKick,
          child: _submitting
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colorScheme.onError,
                  ),
                )
              : const Text('确认踢出'),
        ),
      ],
    );
  }
}
