import 'package:flutter/material.dart';
import '../storage_service.dart';
import '../services/api_service.dart';

// --- 排行榜页面 ---
class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("排行榜"),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: "世界榜 (云端)"),
            Tab(text: "本地榜"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _LeaderboardList(isCloud: true),
          _LeaderboardList(isCloud: false),
        ],
      ),
    );
  }
}

class _LeaderboardList extends StatefulWidget {
  final bool isCloud;
  const _LeaderboardList({required this.isCloud});

  @override
  State<_LeaderboardList> createState() => _LeaderboardListState();
}

class _LeaderboardListState extends State<_LeaderboardList> {
  Future<List<Map<String, dynamic>>>? _future;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      if (widget.isCloud) {
        _future = _fetchCloudData();
      } else {
        _future = StorageService.getLeaderboard();
      }
    });
  }

  Future<List<Map<String, dynamic>>> _fetchCloudData() async {
    try {
      final list = await ApiService.fetchLeaderboard();
      // 确保类型转换安全
      return list.map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (e) {
      debugPrint("获取排行榜失败: $e");
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => _refresh(),
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text("加载失败: ${snapshot.error}"));
          }

          var list = snapshot.data ?? [];
          if (list.isEmpty) {
            return const Center(child: Text("暂无排名数据", style: TextStyle(color: Colors.grey)));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(10),
            itemCount: list.length,
            separatorBuilder: (ctx, i) => const Divider(),
            itemBuilder: (ctx, i) {
              var item = list[i];
              Color? rankColor;
              if (i == 0) rankColor = Colors.amber; // 金
              else if (i == 1) rankColor = Colors.grey[400]; // 银
              else if (i == 2) rankColor = Colors.orange[300]; // 铜

              // 兼容云端字段 (duration) 和 本地字段 (time)
              // API: {username, score, duration}
              // Local: {username, score, time}
              String timeStr = (item['duration'] ?? item['time'] ?? 0).toString();

              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: rankColor ?? Colors.blue[100],
                  foregroundColor: rankColor != null ? Colors.white : Colors.black87,
                  child: Text("${i + 1}", style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                title: Text(item['username'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text("用时: ${timeStr}秒"),
                trailing: Text("${item['score']}分",
                    style: const TextStyle(fontSize: 20, color: Colors.indigo, fontWeight: FontWeight.bold)),
              );
            },
          );
        },
      ),
    );
  }
}

// --- 历史记录页面 ---
class HistoryScreen extends StatelessWidget {
  final String username;
  const HistoryScreen({super.key, required this.username});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("$username 的答题记录")),
      body: FutureBuilder<List<String>>(
        future: StorageService.getHistory(username),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          var list = snapshot.data!;
          if (list.isEmpty) return const Center(child: Text("暂无历史记录"));

          return ListView.builder(
            padding: const EdgeInsets.all(10),
            itemCount: list.length,
            itemBuilder: (ctx, i) {
              return Card(
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Text(list[i], style: const TextStyle(fontSize: 14, height: 1.5)),
                ),
              );
            },
          );
        },
      ),
    );
  }
}