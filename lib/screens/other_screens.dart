import 'package:flutter/material.dart';
import '../storage_service.dart';

// --- 排行榜页面 ---
class LeaderboardScreen extends StatelessWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("排行榜 (Top 10)")),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: StorageService.getLeaderboard(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          var list = snapshot.data!;
          if (list.isEmpty) return const Center(child: Text("暂无排名数据"));

          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (ctx, i) => const Divider(),
            itemBuilder: (ctx, i) {
              var item = list[i];
              Color? rankColor;
              if (i == 0) rankColor = Colors.amber; // 金
              else if (i == 1) rankColor = Colors.grey[400]; // 银
              else if (i == 2) rankColor = Colors.orange[300]; // 铜

              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: rankColor ?? Colors.blue[100],
                  child: Text("${i + 1}"),
                ),
                title: Text(item['username'], style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text("用时: ${item['time']}秒"),
                trailing: Text("${item['score']}分",
                    style: const TextStyle(fontSize: 20, color: Colors.red, fontWeight: FontWeight.bold)),
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
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(10.0),
                  child: Text(list[i], style: const TextStyle(fontSize: 14)),
                ),
              );
            },
          );
        },
      ),
    );
  }
}