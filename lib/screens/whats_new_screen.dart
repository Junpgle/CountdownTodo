import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../update_service.dart';
import '../utils/page_transitions.dart';
import 'home_dashboard.dart';
import 'login_screen.dart';

class WhatsNewScreen extends StatefulWidget {
  final String? loggedInUser;

  const WhatsNewScreen({super.key, this.loggedInUser});

  static Future<bool> shouldShow() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final prefs = await SharedPreferences.getInstance();
      final lastVersion = prefs.getString('last_shown_whats_new_version');
      return lastVersion != info.version;
    } catch (_) {
      return false;
    }
  }

  @override
  State<WhatsNewScreen> createState() => _WhatsNewScreenState();
}

class _WhatsNewScreenState extends State<WhatsNewScreen> {
  String _currentVersion = '';
  List<ChangelogEntry> _changelogHistory = [];
  bool _loading = true;
  bool _fetchFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      _currentVersion = info.version;
    } catch (_) {}

    try {
      final manifest = await UpdateService.checkManifest(
        preferCache: false,
        refreshInBackground: true,
      );
      if (manifest != null && mounted) {
        setState(() {
          _changelogHistory = manifest.changelogHistory
              .where((e) => _normalizeVersion(e.versionName) ==
                  _normalizeVersion(_currentVersion))
              .toList();
          _loading = false;
        });
        return;
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _loading = false;
        _fetchFailed = true;
      });
    }
  }

  String _normalizeVersion(String v) =>
      v.trim().split('+').first.split('-').first;

  Future<void> _done() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_shown_whats_new_version', _currentVersion);

    if (!mounted) return;

    final username = widget.loggedInUser;
    final dest = (username != null && username.isNotEmpty)
        ? HomeDashboard(username: username)
        : const LoginScreen();
    Navigator.of(context).pushAndRemoveUntil(
      PageTransitions.fadeThrough(dest),
      (_) => false,
    );
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: _buildContent(scheme),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _done,
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('开始使用'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Row(children: [
          Icon(Icons.system_update_rounded, size: 28, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _loading ? '版本更新' : 'v$_currentVersion 更新日志',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
          ),
        ]),
        const SizedBox(height: 16),
        if (_loading)
          const Center(child: CircularProgressIndicator(strokeWidth: 2))
        else if (_fetchFailed)
          _buildOfflineNotice(scheme)
        else if (_changelogHistory.isEmpty)
          _buildEmptyNotice(scheme)
        else
          ..._changelogHistory.map((entry) =>
              _buildVersionEntry(entry, scheme)),
      ],
    );
  }

  Widget _buildOfflineNotice(ColorScheme scheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.wifi_off, color: Colors.orange[700], size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '当前无网络连接，请联网后查看更新内容。',
              style: TextStyle(
                color: scheme.onSurface.withValues(alpha: 0.7),
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyNotice(ColorScheme scheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(Icons.new_releases_outlined,
              size: 48, color: scheme.primary.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          Text(
            '本版本暂无更新日志',
            style: TextStyle(
              fontSize: 16,
              color: scheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVersionEntry(ChangelogEntry entry, ColorScheme scheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(20)),
              child: Text('v${entry.versionName}',
                  style: TextStyle(
                      color: scheme.onPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.bold)),
            ),
          ]),
          const SizedBox(height: 14),
          ...entry.items.map((item) => _buildBulletItem(item, scheme)),
        ],
      ),
    );
  }

  Widget _buildBulletItem(String item, ColorScheme scheme) {
    Color dotColor = scheme.onSurface.withValues(alpha: 0.4);
    if (item.startsWith('【新增】')) {
      dotColor = Colors.green;
    } else if (item.startsWith('【优化】')) {
      dotColor = scheme.primary;
    } else if (item.startsWith('【修复】')) {
      dotColor = Colors.orange;
    } else if (item.startsWith('【重构】')) {
      dotColor = Colors.purple;
    } else if (item.startsWith('⚠️')) {
      dotColor = Colors.red;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(item,
                style: TextStyle(
                    fontSize: 13.5,
                    color: scheme.onSurface.withValues(alpha: 0.75),
                    height: 1.45)),
          ),
        ],
      ),
    );
  }
}
