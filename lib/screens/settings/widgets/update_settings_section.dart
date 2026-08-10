import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../services/minor_mode_policy.dart';
import '../../../services/minor_mode_service.dart';
import '../../../update_service.dart';
import '../../../utils/app_platform.dart';
import '../../../widgets/app_settings_widgets.dart';
import '../../../widgets/app_state_views.dart';

/// Settings block for the installed version, release notes and update flow.
class UpdateSettingsSection extends StatefulWidget {
  const UpdateSettingsSection({super.key});

  @override
  State<UpdateSettingsSection> createState() => _UpdateSettingsSectionState();
}

class _UpdateSettingsSectionState extends State<UpdateSettingsSection> {
  PackageInfo? _packageInfo;
  AppManifest? _manifest;
  ChangelogEntry? _currentChangelog;
  ChangelogEntry? _latestChangelog;
  String _updateSource = UpdateService.updateSourceGithub;
  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _hasDeltaPackage = false;
  bool _isDownloading = false;
  double _downloadProgress = 0;
  String? _downloadKind;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  String _cleanVersion(String version) =>
      version.trim().split('+').first.split('-').first;

  int _compareVersions(String left, String right) {
    final a = _cleanVersion(left)
        .split('.')
        .map((part) => int.tryParse(part) ?? 0)
        .toList();
    final b = _cleanVersion(right)
        .split('.')
        .map((part) => int.tryParse(part) ?? 0)
        .toList();
    final length = a.length > b.length ? a.length : b.length;
    for (var index = 0; index < length; index++) {
      final av = index < a.length ? a[index] : 0;
      final bv = index < b.length ? b[index] : 0;
      if (av != bv) return av.compareTo(bv);
    }
    return 0;
  }

  ChangelogEntry? _findChangelog(List<ChangelogEntry> entries, String version) {
    final cleanVersion = _cleanVersion(version);
    for (final entry in entries) {
      if (_cleanVersion(entry.versionName) == cleanVersion) return entry;
    }
    return null;
  }

  Future<void> _load({bool refresh = false}) async {
    if (refresh) {
      if (_isRefreshing) return;
      setState(() => _isRefreshing = true);
    }

    try {
      final results = await Future.wait<dynamic>([
        PackageInfo.fromPlatform(),
        UpdateService.checkManifest(
          preferCache: !refresh,
          refreshInBackground: !refresh,
        ),
        UpdateService.getUpdateSource(),
      ]);
      final packageInfo = results[0] as PackageInfo;
      final manifest = results[1] as AppManifest?;
      final source = results[2] as String;
      var currentChangelog = manifest == null
          ? null
          : _findChangelog(manifest.changelogHistory, packageInfo.version);
      if (currentChangelog == null &&
          manifest != null &&
          _compareVersions(manifest.versionName, packageInfo.version) == 0 &&
          manifest.updateInfo.description.trim().isNotEmpty) {
        currentChangelog = ChangelogEntry(
          versionName: packageInfo.version,
          date: '',
          items: manifest.updateInfo.description
              .split(RegExp(r'\r?\n'))
              .where((item) => item.trim().isNotEmpty)
              .toList(),
        );
      }
      final latestChangelog = manifest == null
          ? null
          : _findChangelog(manifest.changelogHistory, manifest.versionName);
      final hasUpdate = manifest != null &&
          _compareVersions(manifest.versionName, packageInfo.version) > 0;
      final hasDelta = hasUpdate && AppPlatform.isAndroid
          ? await UpdateService.hasUsableDeltaPackage(manifest)
          : false;

      if (!mounted) return;
      setState(() {
        _packageInfo = packageInfo;
        _manifest = manifest;
        _currentChangelog = currentChangelog;
        _latestChangelog = latestChangelog;
        _updateSource = source;
        _hasDeltaPackage = hasDelta;
        _errorMessage = manifest == null ? '暂时无法获取更新信息' : null;
        _isLoading = false;
        _isRefreshing = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isRefreshing = false;
        _errorMessage = '暂时无法获取更新信息，请检查网络后重试';
      });
    }
  }

  bool get _hasUpdate {
    final packageInfo = _packageInfo;
    final manifest = _manifest;
    if (packageInfo == null || manifest == null) return false;
    return _compareVersions(manifest.versionName, packageInfo.version) > 0;
  }

  bool get _hasDownloadPackage {
    final updateInfo = _manifest?.updateInfo;
    if (updateInfo == null) return false;
    return updateInfo.fullPackageUrl.isNotEmpty ||
        updateInfo.pcPackageUrl.isNotEmpty ||
        updateInfo.macPackageUrl.isNotEmpty ||
        updateInfo.androidArchPackages.isNotEmpty;
  }

  String _currentVersionLabel() {
    final packageInfo = _packageInfo;
    if (packageInfo == null) return '加载中...';
    return 'v${packageInfo.version} (Build ${packageInfo.buildNumber})';
  }

  Future<void> _setUpdateSource(String source) async {
    if (source == _updateSource) return;
    final authorized = await MinorModeService.instance.authorizeAction(
      MinorModeAction.updateSource,
    );
    if (!authorized) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              MinorModeService.instance.authorizationFailureMessage(
                MinorModeAction.updateSource,
              ),
            ),
          ),
        );
      }
      return;
    }
    await UpdateService.setUpdateSource(source);
    if (mounted) setState(() => _updateSource = source);
  }

  Future<void> _downloadPackage({required bool preferDelta}) async {
    final manifest = _manifest;
    if (_isDownloading || manifest == null || !_hasDownloadPackage) return;

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0;
      _downloadKind = preferDelta ? '增量包' : '全量包';
    });

    await UpdateService.downloadLatestPackage(
      context,
      manifest,
      preferDelta: preferDelta,
      onProgress: (progress) {
        if (mounted) setState(() => _downloadProgress = progress);
      },
      onComplete: (path) => unawaited(_finishDownload(path)),
      onError: (message) {
        if (!mounted) return;
        setState(() {
          _isDownloading = false;
          _downloadKind = null;
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      },
    );
  }

  Future<void> _finishDownload(String path) async {
    if (!mounted) return;
    setState(() {
      _isDownloading = false;
      _downloadProgress = 1;
    });

    if (AppPlatform.isWeb) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已打开最新版本资源')));
      return;
    }

    final shouldInstall = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('下载完成'),
        content: Text(
            AppPlatform.isMacOS ? '更新包已下载完成，是否打开下载目录？' : '更新包已下载完成，是否立即安装？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(AppPlatform.isMacOS ? '打开目录' : '立即安装'),
          ),
        ],
      ),
    );
    if (shouldInstall == true) await UpdateService.installPackage(path);
  }

  Future<void> _showCurrentChangelog() async {
    final entry = _currentChangelog;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.72,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: entry == null
                ? const Center(child: Text('暂无该版本的更新日志'))
                : ListView(
                    children: [
                      Text(
                        'v${entry.versionName}',
                        style: Theme.of(sheetContext)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      if (entry.date.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          entry.date,
                          style: TextStyle(
                            color: Theme.of(sheetContext)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      ...entry.items.map(
                        (item) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('•  '),
                              Expanded(child: Text(item)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  List<String> _latestReleaseNotes() {
    final entry = _latestChangelog;
    if (entry != null && entry.items.isNotEmpty) return entry.items;
    return _manifest?.updateInfo.description
            .split(RegExp(r'\r?\n'))
            .where((item) => item.trim().isNotEmpty)
            .toList() ??
        const [];
  }

  Widget _buildVersionCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final entry = _currentChangelog;
    final date = entry?.date.isNotEmpty == true ? entry!.date : '暂无记录';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.verified_outlined, color: colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('当前版本',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 3),
                    Text(_currentVersionLabel()),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed:
                    _currentChangelog == null ? null : _showCurrentChangelog,
                icon: const Icon(Icons.description_outlined, size: 18),
                label: const Text('更新日志'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('更新日期：$date',
              style: TextStyle(color: colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _buildLatestVersionCard(BuildContext context) {
    final manifest = _manifest;
    if (manifest == null || !_hasUpdate) return const SizedBox.shrink();
    final colorScheme = Theme.of(context).colorScheme;
    final latestDate = _latestChangelog?.date;
    final notes = _latestReleaseNotes();

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.new_releases_outlined,
                  color: colorScheme.onPrimaryContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '发现新版本  v${manifest.versionName}',
                  style: TextStyle(
                    color: colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              if (latestDate?.isNotEmpty == true)
                Text(latestDate!,
                    style: TextStyle(color: colorScheme.onPrimaryContainer)),
            ],
          ),
          if (manifest.updateInfo.title.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(manifest.updateInfo.title,
                style: TextStyle(color: colorScheme.onPrimaryContainer)),
          ],
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...notes.map(
              (note) => Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(
                  '• $note',
                  style: TextStyle(color: colorScheme.onPrimaryContainer),
                ),
              ),
            ),
          ],
          if (_isDownloading) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: LinearProgressIndicator(
                    value: _downloadProgress == 0 ? null : _downloadProgress,
                    color: colorScheme.primary,
                    backgroundColor:
                        colorScheme.onPrimaryContainer.withValues(alpha: 0.15),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${_downloadKind ?? '更新包'} ${(_downloadProgress * 100).toStringAsFixed(0)}%',
                  style: TextStyle(color: colorScheme.onPrimaryContainer),
                ),
              ],
            ),
          ] else if (_hasDownloadPackage) ...[
            const SizedBox(height: 14),
            if (AppPlatform.isAndroid) ...[
              Text(
                _hasDeltaPackage
                    ? '已匹配当前安装包，可选择增量包；下载后会校验并生成完整 APK。'
                    : '当前版本没有可用的匹配增量包，将下载全量包。',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: () => _downloadPackage(preferDelta: false),
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('下载全量包'),
                  ),
                  if (_hasDeltaPackage)
                    OutlinedButton.icon(
                      onPressed: () => _downloadPackage(preferDelta: true),
                      icon: const Icon(Icons.compress_rounded),
                      label: const Text('下载增量包'),
                    ),
                ],
              ),
            ] else
              FilledButton.icon(
                onPressed: () => _downloadPackage(preferDelta: false),
                icon: const Icon(Icons.download_rounded),
                label: const Text('下载更新包'),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildChannelCard({
    required BuildContext context,
    required String value,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final selected = _updateSource == value;
    return InkWell(
      onTap: () => _setUpdateSource(value),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(minWidth: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primary.withValues(alpha: 0.1)
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? colorScheme.primary : colorScheme.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                color: selected
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: 11, color: colorScheme.onSurfaceVariant)),
              ],
            ),
            if (selected) ...[
              const SizedBox(width: 8),
              Icon(Icons.check_circle, size: 18, color: colorScheme.primary),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildUpdateSource(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('更新渠道',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 4),
          Text('选择版本清单的获取线路；安装包仍会使用清单提供的校验地址。',
              style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildChannelCard(
                context: context,
                value: UpdateService.updateSourceGithub,
                title: 'GitHub 官方源',
                subtitle: '信息更新更及时',
                icon: Icons.code_rounded,
              ),
              _buildChannelCard(
                context: context,
                value: UpdateService.updateSourceServer,
                title: '阿里云加速源',
                subtitle: '国内访问更快',
                icon: Icons.cloud_outlined,
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const AppLoadingView();

    final colorScheme = Theme.of(context).colorScheme;
    return AppSettingsSection(
      title: '版本更新',
      trailing: TextButton.icon(
        onPressed: _isRefreshing ? null : () => _load(refresh: true),
        icon: _isRefreshing
            ? const AppLoadingIndicator(size: 18)
            : const Icon(Icons.refresh_rounded, size: 18),
        label: const Text('检查更新'),
      ),
      children: [
        _buildVersionCard(context),
        if (_errorMessage != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Row(
              children: [
                Icon(Icons.cloud_off_outlined,
                    size: 18, color: colorScheme.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_errorMessage!,
                      style: TextStyle(color: colorScheme.error)),
                ),
              ],
            ),
          ),
        _buildLatestVersionCard(context),
        const AppSettingsDivider(),
        _buildUpdateSource(context),
      ],
    );
  }
}
