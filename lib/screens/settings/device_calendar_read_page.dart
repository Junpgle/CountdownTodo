import 'package:flutter/material.dart';

import '../../services/device_calendar_read_service.dart';
import '../../utils/app_platform.dart';
import '../../widgets/floating_glass_control.dart';

Future<bool> showDeviceCalendarReadOnlyConfirmation(
    BuildContext context) async {
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('读取手机日历？'),
          content: const Text(
            '只会在本机前台读取日程，用于首页、周视图和半月/月视图展示。'
            '不会写入系统日历，不会导入为待办，也不会上传或参与任何同步。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('继续'),
            ),
          ],
        ),
      ) ??
      false;
}

/// The compact, immediate toggle used by the one-time feature guide.
class GuideDeviceCalendarReadToggle extends StatefulWidget {
  const GuideDeviceCalendarReadToggle({super.key});

  @override
  State<GuideDeviceCalendarReadToggle> createState() =>
      _GuideDeviceCalendarReadToggleState();
}

class _GuideDeviceCalendarReadToggleState
    extends State<GuideDeviceCalendarReadToggle> {
  bool _loading = true;
  bool _enabled = false;
  bool _permissionGranted = false;
  bool _changing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final enabled = await DeviceCalendarReadService.isEnabled();
    final granted = await DeviceCalendarReadService.checkPermission();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _permissionGranted = granted;
      _loading = false;
    });
  }

  Future<void> _setEnabled(bool enabled) async {
    if (_changing) return;
    setState(() => _changing = true);
    try {
      if (enabled) {
        if (!await showDeviceCalendarReadOnlyConfirmation(context)) return;
        final granted = await DeviceCalendarReadService.checkPermission() ||
            await DeviceCalendarReadService.requestPermission();
        if (!granted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('需要日历读取权限才能展示手机日程')),
            );
          }
          return;
        }
      }
      await DeviceCalendarReadService.setEnabled(enabled);
      await _load();
    } finally {
      if (mounted) setState(() => _changing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      color: colors.secondaryContainer,
      child: LiquidGlassSwitchListTile(
        key: const ValueKey('guide-device-calendar-read-switch'),
        value: _enabled,
        onChanged: _loading || _changing ? null : _setEnabled,
        secondary: const Icon(Icons.phone_android_outlined),
        title: const Text('在 App 中显示手机日程'),
        subtitle: Text(
          _loading
              ? '正在检查本机日历访问状态…'
              : _permissionGranted
                  ? '首页与周视图、半月/月视图会在打开时读取当前日程'
                  : '默认关闭；开启后才会请求日历读取权限',
        ),
      ),
    );
  }
}

class DeviceCalendarReadPage extends StatefulWidget {
  const DeviceCalendarReadPage({super.key, this.isEmbedded = false});

  final bool isEmbedded;

  @override
  State<DeviceCalendarReadPage> createState() => _DeviceCalendarReadPageState();
}

class _DeviceCalendarReadPageState extends State<DeviceCalendarReadPage> {
  bool _loading = true;
  bool _enabled = false;
  bool _permissionGranted = false;
  bool _changing = false;
  List<DeviceCalendarSource> _sources = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!DeviceCalendarReadService.isSupported) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final enabled = await DeviceCalendarReadService.isEnabled();
    final granted = await DeviceCalendarReadService.checkPermission();
    final sources = granted
        ? await DeviceCalendarReadService.getSources()
        : const <DeviceCalendarSource>[];
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _permissionGranted = granted;
      _sources = sources;
      _loading = false;
    });
  }

  Future<void> _setEnabled(bool enabled) async {
    if (_changing) return;
    setState(() => _changing = true);
    try {
      if (enabled) {
        if (!await showDeviceCalendarReadOnlyConfirmation(context)) return;
        final granted = await DeviceCalendarReadService.checkPermission() ||
            await DeviceCalendarReadService.requestPermission();
        if (!granted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('需要日历读取权限才能展示手机日程')),
            );
          }
          return;
        }
        await DeviceCalendarReadService.setEnabled(true);
      } else {
        await DeviceCalendarReadService.setEnabled(false);
      }
      await _load();
    } finally {
      if (mounted) setState(() => _changing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      extendBodyBehindAppBar: !widget.isEmbedded,
      appBar: widget.isEmbedded
          ? null
          : FloatingGlassAppBar(
              flexibleSpace: const FloatingGlassTopBarBackground(),
              title: const Text('读取手机日历'),
            ),
      body: floatingGlassSettingsBody(
        context,
        standalone: !widget.isEmbedded,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            widget.isEmbedded
                ? 16
                : floatingGlassSettingsContentTopInset(context, extra: 16),
            16,
            24,
          ),
          children: [
            Card(
              color: colors.secondaryContainer,
              child: const ListTile(
                leading: Icon(Icons.shield_outlined),
                title: Text('严格本地只读'),
                subtitle: Text('不写回系统日历，不生成待办，不上传，也不同步。'),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: SwitchListTile.adaptive(
                value: _enabled,
                onChanged: _loading ||
                        _changing ||
                        !DeviceCalendarReadService.isSupported
                    ? null
                    : _setEnabled,
                title: const Text('在 App 中显示手机日程'),
                subtitle: Text(
                  _permissionGranted
                      ? '首页与周视图、半月/月视图会在打开时读取当前日程'
                      : '开启后会请求日历读取权限',
                ),
              ),
            ),
            if (!DeviceCalendarReadService.isSupported)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: Text('仅 Android 和 iPhone 支持读取手机系统日历。'),
              )
            else if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_permissionGranted) ...[
              const SizedBox(height: 20),
              Text('可读取的日历', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              if (_sources.isEmpty)
                const Text('系统没有返回可读取的日历。')
              else
                ..._sources.map(
                  (source) => ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    leading: Icon(Icons.calendar_today_outlined,
                        color: colors.primary),
                    title: Text(source.name),
                    subtitle:
                        source.account == null ? null : Text(source.account!),
                  ),
                ),
            ],
            if (AppPlatform.isIOS)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'iOS 将显示系统提供的“完整日历访问”授权名称；本功能的代码仍只读取事件，不包含任何写入接口。',
                ),
              ),
          ],
        ),
      ),
    );
  }
}
