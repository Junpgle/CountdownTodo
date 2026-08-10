import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../models/minor_age_signal_state.dart';
import '../../../models/minor_mode_state.dart';
import '../../../services/minor_mode_service.dart';
import '../../../utils/app_platform.dart';
import '../../../widgets/app_settings_widgets.dart';

class MinorModeSettingsPage extends StatefulWidget {
  final String? initialTarget;
  final bool isEmbedded;

  const MinorModeSettingsPage({
    super.key,
    this.initialTarget,
    this.isEmbedded = false,
  });

  @override
  State<MinorModeSettingsPage> createState() => _MinorModeSettingsPageState();
}

class _MinorModeSettingsPageState extends State<MinorModeSettingsPage> {
  final Map<String, GlobalKey> _itemKeys = {
    'minor_mode': GlobalKey(),
    'minor_mode_status': GlobalKey(),
  };
  String? _highlightTarget;

  @override
  void initState() {
    super.initState();
    MinorModeService.instance.initialize();
    if (widget.initialTarget != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToTarget(widget.initialTarget!);
      });
    }
  }

  void _scrollToTarget(String target) {
    final key = _itemKeys[target];
    if (key?.currentContext == null) return;
    setState(() => _highlightTarget = target);
    Scrollable.ensureVisible(
      key!.currentContext!,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
      alignment: 0.15,
    );
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _highlightTarget = null);
    });
  }

  Future<void> _setManualEnabled(bool enabled) async {
    await MinorModeService.instance.setManualEnabled(enabled);
  }

  Future<void> _pickManualBirthDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final current = MinorModeService.instance.manualBirthDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime(today.year - 12, today.month, today.day),
      firstDate: DateTime(1900),
      lastDate: today,
      helpText: '选择出生日期',
      cancelText: '取消',
      confirmText: '确定',
    );
    if (picked == null) return;
    await MinorModeService.instance.setManualBirthDate(picked);
  }

  Future<void> _refresh() async {
    await MinorModeService.instance.refreshMinorModeState();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('系统未成年人模式状态已刷新')),
    );
  }

  Future<void> _openSystemSettings() async {
    final opened = await MinorModeService.instance.openMinorModeSettings();
    if (!mounted || opened) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('当前设备无法打开系统未成年人模式设置')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<MinorModeState>(
      valueListenable: MinorModeService.instance.stateNotifier,
      builder: (context, state, _) {
        return ValueListenableBuilder<MinorAgeSignalState>(
          valueListenable: MinorModeService.instance.googleAgeSignalNotifier,
          builder: (context, googleAgeSignal, _) {
            return Scaffold(
              appBar: widget.isEmbedded
                  ? null
                  : AppBar(title: const Text('未成年人模式')),
              body: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  _buildStatusSection(context, state, googleAgeSignal),
                  const SizedBox(height: 16),
                  _buildManualSection(context, state),
                  if (AppPlatform.isAndroid) ...[
                    const SizedBox(height: 16),
                    _buildGoogleAgeSignalsSection(context, googleAgeSignal),
                  ],
                  if (state.systemSupported) ...[
                    const SizedBox(height: 16),
                    AppSettingsSection(
                      title: '系统设置',
                      children: [
                        ListTile(
                          leading: Icon(
                            Icons.open_in_new,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          title: const Text('打开手机系统设置'),
                          subtitle: const Text('系统模式由手机系统管理'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: _openSystemSettings,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _requestGoogleAgeSignals() async {
    final state = await MinorModeService.instance.requestGoogleAgeSignals();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(state.status.label)),
    );
  }

  Widget _buildGoogleAgeSignalsSection(
    BuildContext context,
    MinorAgeSignalState state,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final canRequest = state.available;
    return AppSettingsSection(
      title: 'Google Play 年龄信号',
      children: [
        ListTile(
          leading: Icon(
            Icons.account_circle_outlined,
            color: state.status == MinorAgeSignalStatus.shared
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant,
          ),
          title: Text(state.status.label),
          subtitle: Text(
            state.status == MinorAgeSignalStatus.shared
                ? state.isMinor
                    ? '年龄范围：${state.ageRangeLabel}；已纳入 Android 未成年人策略'
                    : '年龄范围：${state.ageRangeLabel}；当前不触发未成年人策略'
                : '仅主动请求后生效，未分享时不会改变当前模式',
          ),
        ),
        const AppSettingsDivider(),
        ListTile(
          leading: Icon(Icons.verified_outlined, color: colorScheme.primary),
          title: const Text('请求年龄信号'),
          subtitle: const Text('只有主动点击后才会向 Google Play 请求，可能显示授权提示'),
          trailing: const Icon(Icons.chevron_right),
          enabled: canRequest,
          onTap: canRequest ? _requestGoogleAgeSignals : null,
        ),
      ],
    );
  }

  Widget _buildStatusSection(
    BuildContext context,
    MinorModeState state,
    MinorAgeSignalState googleAgeSignal,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final googleMinorEnabled = googleAgeSignal.isMinor;
    final effective = state.effectiveMinorMode || googleMinorEnabled;
    final ageRangeLabel = googleMinorEnabled
        ? googleAgeSignal.ageRangeLabel
        : state.ageBand.label;
    final status = googleMinorEnabled
        ? 'Google Play 年龄信号已开启未成年人策略'
        : state.systemEnabled
            ? '已跟随系统开启'
            : effective
                ? 'App 未成年人模式已开启'
                : state.systemSupported
                    ? '系统未成年人模式未开启'
                    : '系统联动当前设备暂不支持';
    final statusIcon =
        effective ? Icons.shield_outlined : Icons.shield_moon_outlined;

    return AppSettingsSection(
      title: '状态',
      children: [
        AppSettingsHighlightedTile(
          targetId: 'minor_mode_status',
          highlightTarget: _highlightTarget,
          itemKeys: _itemKeys,
          borderRadius: BorderRadius.zero,
          child: ListTile(
            leading: Icon(
              statusIcon,
              color: effective
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
            ),
            title: Text(status),
            subtitle: Text(
              googleMinorEnabled
                  ? '来源：Google 年龄信号'
                  : '来源：${state.source.label}',
            ),
            trailing: IconButton(
              tooltip: '刷新状态',
              icon: const Icon(Icons.refresh),
              onPressed: _refresh,
            ),
          ),
        ),
        const AppSettingsDivider(),
        ListTile(
          leading: Icon(Icons.groups_2_outlined,
              color: colorScheme.onSurfaceVariant),
          title: const Text('年龄范围'),
          trailing: Text(
            ageRangeLabel,
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
        ),
        const AppSettingsDivider(),
        ListTile(
          leading: Icon(Icons.verified_user_outlined,
              color: colorScheme.onSurfaceVariant),
          title: const Text('家长身份认证'),
          trailing: Text(
            state.parentAuthenticationSupported ? '支持' : '暂不支持',
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
        ),
        if (state.systemEnabled) ...[
          const AppSettingsDivider(),
          ListTile(
            leading: Icon(Icons.lock_outline, color: colorScheme.primary),
            title: const Text('此模式由手机系统管理'),
            subtitle: const Text('无法在应用内关闭或绕过'),
          ),
        ],
        if (state.systemStateReadFailed) ...[
          const AppSettingsDivider(),
          ListTile(
            leading:
                Icon(Icons.warning_amber_outlined, color: colorScheme.error),
            title: const Text('系统状态暂时无法读取'),
            subtitle: const Text('应用会在恢复前保留最近一次安全状态'),
          ),
        ],
      ],
    );
  }

  Widget _buildManualSection(BuildContext context, MinorModeState state) {
    final colorScheme = Theme.of(context).colorScheme;
    final birthDate = MinorModeService.instance.manualBirthDate;
    return AppSettingsSection(
      title: 'App 未成年人模式',
      children: [
        AppSettingsHighlightedTile(
          targetId: 'minor_mode',
          highlightTarget: _highlightTarget,
          itemKeys: _itemKeys,
          borderRadius: BorderRadius.zero,
          child: SwitchListTile(
            secondary: Icon(Icons.tune, color: colorScheme.primary),
            title: const Text('手动开启'),
            subtitle: Text(
              state.systemEnabled
                  ? '系统模式已开启，App 不能将有效模式关闭'
                  : '用于系统联动不可用或系统模式关闭时的兜底保护',
            ),
            value: state.manualEnabled,
            onChanged: state.systemEnabled ? null : _setManualEnabled,
          ),
        ),
        const AppSettingsDivider(),
        ListTile(
          leading: Icon(Icons.cake_outlined, color: colorScheme.primary),
          title: const Text('出生日期'),
          subtitle: Text(
            birthDate == null
                ? '选择后自动计算年龄段并开启 App 未成年人模式'
                : '仅保存在本机：${MinorAgeBandSystemMapping.fromBirthDate(birthDate).label}',
          ),
          trailing: Text(
            birthDate == null
                ? '未设置'
                : DateFormat('yyyy-MM-dd').format(birthDate),
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
          onTap: _pickManualBirthDate,
        ),
      ],
    );
  }
}
