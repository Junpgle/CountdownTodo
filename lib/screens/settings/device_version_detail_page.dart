import 'package:flutter/material.dart';
import '../../services/api_service.dart';

class DeviceVersionDetailPage extends StatefulWidget {
  const DeviceVersionDetailPage({super.key});

  @override
  State<DeviceVersionDetailPage> createState() =>
      _DeviceVersionDetailPageState();
}

class _DeviceVersionDetailPageState extends State<DeviceVersionDetailPage> {
  bool _loading = true;
  Map<String, dynamic>? _onlineData;
  Map<String, dynamic>? _versionData;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final online = await ApiService.fetchOnlineStats();
      final version = await ApiService.fetchDeviceVersionStats();
      setState(() {
        _onlineData = online;
        _versionData = version;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设备版本明细'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline,
                          size: 48, color: Colors.red),
                      const SizedBox(height: 16),
                      Text('加载失败: $_error'),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _loadData,
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildOnlineCard(),
                      const SizedBox(height: 16),
                      _buildVersionCard(),
                    ],
                  ),
                ),
    );
  }

  Widget _buildOnlineCard() {
    final data = _onlineData?['data'];
    final stats = data?['stats'] as Map<String, dynamic>? ?? {};
    final totalOnline = data?['totalOnline'] ?? 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.wifi,
                    size: 20, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  '当前在线设备',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '总计在线: $totalOnline 台设备',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            if (stats.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('暂无在线设备',
                    style: TextStyle(color: Colors.grey[600], fontSize: 13)),
              )
            else
              ...stats.entries
                  .map((e) => _buildPlatformSection(e.key, e.value)),
          ],
        ),
      ),
    );
  }

  Widget _buildVersionCard() {
    final data = _versionData?['data'];
    final stats = data?['stats'] as Map<String, dynamic>? ?? {};
    final totalDevices = data?['totalDevices'] ?? 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.devices,
                    size: 20, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  '设备历史版本分布',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '总计设备: $totalDevices 台',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            if (stats.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('暂无设备记录',
                    style: TextStyle(color: Colors.grey[600], fontSize: 13)),
              )
            else
              ...stats.entries
                  .map((e) => _buildPlatformSection(e.key, e.value)),
          ],
        ),
      ),
    );
  }

  Widget _buildPlatformSection(String platform, dynamic versions) {
    final versionMap = versions is Map ? versions : <String, dynamic>{};
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '💻 $platform',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          ...versionMap.entries.map((e) {
            final version = e.key;
            final count = e.value is int
                ? e.value
                : int.tryParse(e.value.toString()) ?? 0;
            return Padding(
              padding: const EdgeInsets.only(left: 16, top: 2),
              child: Row(
                children: [
                  const Text('├─ ', style: TextStyle(color: Colors.grey)),
                  Text('v$version',
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 13)),
                  const Spacer(),
                  Text('$count 台',
                      style: TextStyle(color: Colors.grey[700], fontSize: 13)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
