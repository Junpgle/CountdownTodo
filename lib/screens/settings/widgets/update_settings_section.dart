import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

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
  String? _downloadedPackagePath;
  bool _isForceDownloading = false;
  double _forceDownloadProgress = 0;
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
      final downloadedPackagePath = manifest == null
          ? null
          : await UpdateService.isPackageAlreadyDownloaded(
              manifest.versionName);

      if (!mounted) return;
      setState(() {
        _packageInfo = packageInfo;
        _manifest = manifest;
        _currentChangelog = currentChangelog;
        _latestChangelog = latestChangelog;
        _updateSource = source;
        _hasDeltaPackage = hasDelta;
        _downloadedPackagePath = downloadedPackagePath;
        _errorMessage = manifest == null ? '暂时无法获取更新信息' : null;
        _isLoading = false;
        _isRefreshing = false;
      });

      if (hasUpdate && mounted && AppPlatform.isAndroid) {
        unawaited(
          UpdateService.autoDownloadLatestOnWifi(
            context,
            manifest,
            onProgress: (progress) {
              if (!mounted) return;
              setState(() {
                _isDownloading = true;
                _downloadKind = 'Wi-Fi 自动下载';
                _downloadProgress = progress;
              });
            },
            onComplete: (path) {
              if (!mounted) return;
              setState(() {
                _isDownloading = false;
                _downloadProgress = 1;
                _downloadKind = null;
                _downloadedPackagePath = path;
              });
            },
            onError: (_) {
              if (!mounted) return;
              setState(() {
                _isDownloading = false;
                _downloadKind = null;
              });
            },
          ),
        );
      }
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
    if (_downloadedPackagePath != null) {
      await _installDownloadedPackage();
      return;
    }
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

  Future<void> _forceDownloadLatest() async {
    if (_isForceDownloading) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('强制下载最新版完整包'),
        content: const Text(
          '强制下载会忽略当前版本检查，直接获取清单中的最新版完整安装包。\n\n'
          '该版本可能尚未正式发布，存在不稳定或兼容性问题，请确认后继续。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('确认下载'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _isForceDownloading = true;
      _forceDownloadProgress = 0;
    });

    await UpdateService.forceDownloadLatest(
      context,
      onProgress: (progress) {
        if (mounted) setState(() => _forceDownloadProgress = progress);
      },
      onComplete: (path) => unawaited(_finishForceDownload(path)),
      onError: (message) {
        if (!mounted) return;
        setState(() {
          _isForceDownloading = false;
          _forceDownloadProgress = 0;
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      },
    );
  }

  Future<void> _finishForceDownload(String path) async {
    if (!mounted) return;
    setState(() {
      _isForceDownloading = false;
      _forceDownloadProgress = 1;
      _downloadedPackagePath = path;
    });
    await _promptInstall(path);
  }

  Future<void> _finishDownload(String path) async {
    if (!mounted) return;
    setState(() {
      _isDownloading = false;
      _downloadProgress = 1;
      _downloadKind = null;
      _downloadedPackagePath = path;
    });
    await _promptInstall(path);
  }

  Future<void> _installDownloadedPackage() async {
    final path = _downloadedPackagePath;
    if (path == null) return;
    await UpdateService.installPackage(path);
  }

  Future<void> _promptInstall(String path) async {
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

  Future<void> _openBetaReleases() async {
    final uri = Uri.parse('https://github.com/Junpgle/CountdownTodo/releases');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法打开尝鲜版本下载页面')),
      );
    }
  }

  Future<void> _showCurrentChangelog() async {
    final entry = _currentChangelog;
    var isExpanded = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final items = entry?.items ?? const <String>[];
          final hasMoreItems = items.length > 5;
          final visibleItems =
              isExpanded ? items : items.take(5).toList(growable: false);

          return SafeArea(
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
                          ...visibleItems.map(
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
                          if (hasMoreItems)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: () {
                                  setSheetState(() {
                                    isExpanded = !isExpanded;
                                  });
                                },
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.only(top: 2),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                ),
                                icon: Icon(
                                  isExpanded
                                      ? Icons.keyboard_arrow_up_rounded
                                      : Icons.keyboard_arrow_down_rounded,
                                  size: 18,
                                ),
                                label: Text(
                                  isExpanded ? '收起更新日志' : '展开全部更新日志',
                                ),
                              ),
                            ),
                        ],
                      ),
              ),
            ),
          );
        },
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
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.verified_outlined,
                color: colorScheme.onPrimaryContainer),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('当前版本',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelLarge
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 3),
                          Text(_currentVersionLabel(),
                              style: Theme.of(context).textTheme.bodyMedium),
                        ],
                      ),
                    ),
                    if (_currentChangelog != null)
                      OutlinedButton.icon(
                        onPressed: _showCurrentChangelog,
                        icon: const Icon(Icons.notes_outlined, size: 16),
                        label: const Text('查看日志'),
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          textStyle: const TextStyle(fontSize: 12),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.event_outlined,
                        size: 15, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 5),
                    Text('更新于 $date',
                        style: TextStyle(
                            fontSize: 12, color: colorScheme.onSurfaceVariant)),
                  ],
                ),
              ],
            ),
          ),
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: colorScheme.onPrimaryContainer.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.new_releases_outlined,
                    color: colorScheme.onPrimaryContainer),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '发现新版本',
                      style: TextStyle(
                        color: colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'v${manifest.versionName}',
                      style: TextStyle(
                        color: colorScheme.onPrimaryContainer
                            .withValues(alpha: 0.8),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              if (latestDate?.isNotEmpty == true)
                Text('更新于 $latestDate',
                    style: TextStyle(
                        color: colorScheme.onPrimaryContainer, fontSize: 12)),
            ],
          ),
          if (manifest.updateInfo.title.isNotEmpty &&
              manifest.updateInfo.title != '版本更新 ${manifest.versionName}') ...[
            const SizedBox(height: 12),
            Text(manifest.updateInfo.title,
                style: TextStyle(
                    color: colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600)),
          ],
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 11, 12, 6),
              decoration: BoxDecoration(
                color: colorScheme.onPrimaryContainer.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: notes
                    .map(
                      (note) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Icon(Icons.circle,
                                  size: 5,
                                  color: colorScheme.onPrimaryContainer),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(note,
                                  style: TextStyle(
                                      color: colorScheme.onPrimaryContainer)),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
          if (_downloadedPackagePath != null) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _installDownloadedPackage,
                icon: const Icon(Icons.system_update_alt_rounded),
                label: const Text('立即安装'),
              ),
            ),
          ] else if (_isDownloading) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: LinearProgressIndicator(
                    value: _downloadProgress == 0 ? null : _downloadProgress,
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(6),
                    color: colorScheme.onPrimaryContainer,
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

  Widget _buildUpdateSource(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.alt_route_rounded,
                  color: colorScheme.primary, size: 21),
              const SizedBox(width: 9),
              const Text('更新渠道',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 5),
          Text('选择版本清单的获取线路，安装包仍使用清单提供的地址。',
              style:
                  TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color:
                    colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                border: Border.all(color: colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildUpdateSourceChoice(
                        context,
                        value: UpdateService.updateSourceGithub,
                        title: 'GitHub 官方',
                        subtitle: '信息更新更及时',
                        icon: Icons.code_rounded,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _buildUpdateSourceChoice(
                        context,
                        value: UpdateService.updateSourceServer,
                        title: '阿里云加速',
                        subtitle: '国内访问更快',
                        icon: Icons.cloud_outlined,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.info_outline,
                  size: 15, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  _updateSource == UpdateService.updateSourceServer
                      ? '当前使用阿里云加速线路，国内访问通常更快。'
                      : '当前使用 GitHub 官方线路，版本信息更新更及时。',
                  style: TextStyle(
                      fontSize: 12, color: colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUpdateSourceChoice(
    BuildContext context, {
    required String value,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final selected = _updateSource == value;

    return InkWell(
      onTap: () => unawaited(_setUpdateSource(value)),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primaryContainer.withValues(alpha: 0.55)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? colorScheme.primary : Colors.transparent,
            width: selected ? 1.2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: selected
                    ? colorScheme.primaryContainer
                    : colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                size: 20,
                color: selected
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (selected) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.check_circle_rounded,
                size: 18,
                color: colorScheme.primary,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBetaReleaseTile() {
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: colorScheme.tertiaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.rocket_launch_outlined,
            color: colorScheme.onTertiaryContainer),
      ),
      title: const Text('获取尝鲜版本'),
      subtitle: Text('前往 GitHub 下载最新开发版，体验最新功能',
          style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12)),
      trailing: Icon(Icons.open_in_new, color: colorScheme.onSurfaceVariant),
      onTap: _openBetaReleases,
    );
  }

  Widget _buildForceDownloadTile() {
    final colorScheme = Theme.of(context).colorScheme;
    final packageReady = _downloadedPackagePath != null;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child:
            Icon(Icons.download_rounded, color: colorScheme.onPrimaryContainer),
      ),
      title: Text(packageReady ? '立即安装最新版' : '强制下载最新版完整包'),
      subtitle: packageReady
          ? const Text('完整安装包已下载完成，确认后开始安装')
          : _isForceDownloading
              ? Text(
                  '下载中 ${(_forceDownloadProgress * 100).toStringAsFixed(0)}%',
                  style: TextStyle(fontSize: 12, color: colorScheme.primary),
                )
              : const Text('忽略当前版本检查，下载清单中的最新完整安装包'),
      trailing: packageReady
          ? Icon(Icons.system_update_alt_rounded, color: colorScheme.primary)
          : _isForceDownloading
              ? SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    value: _forceDownloadProgress > 0
                        ? _forceDownloadProgress
                        : null,
                    color: colorScheme.primary,
                  ),
                )
              : Icon(Icons.file_download_outlined,
                  color: colorScheme.onSurfaceVariant),
      onTap: packageReady
          ? _installDownloadedPackage
          : (_isForceDownloading ? null : _forceDownloadLatest),
    );
  }

  Widget _buildUpdateTools(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
            border: Border.all(color: colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              _buildBetaReleaseTile(),
              Divider(
                height: 1,
                indent: 62,
                color: colorScheme.outlineVariant,
              ),
              _buildForceDownloadTile(),
            ],
          ),
        ),
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
        if (!AppPlatform.isWeb) _buildUpdateTools(context),
        const AppSettingsDivider(),
        _buildUpdateSource(context),
      ],
    );
  }
}
