import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math' as math;
import 'dart:convert'; // 用于 jsonEncode 保存缓存
import '../storage_service.dart';
import '../services/api_service.dart';

// 定义数据过滤范围
enum DeviceFilter { all, pc, mobile, phone, tablet }

extension DeviceFilterExtension on DeviceFilter {
  String get label {
    switch (this) {
      case DeviceFilter.all: return "聚合数据";
      case DeviceFilter.pc: return "电脑端";
      case DeviceFilter.mobile: return "移动端";
      case DeviceFilter.phone: return "手机";
      case DeviceFilter.tablet: return "平板";
    }
  }
}

class ScreenTimeDetailScreen extends StatefulWidget {
  final List<dynamic> todayStats; // 今日精确数据

  const ScreenTimeDetailScreen({super.key, required this.todayStats});

  @override
  State<ScreenTimeDetailScreen> createState() => _ScreenTimeDetailScreenState();
}

class _ScreenTimeDetailScreenState extends State<ScreenTimeDetailScreen> {
  DeviceFilter _currentFilter = DeviceFilter.all;
  Map<String, List<dynamic>> _historyStats = {};
  Map<String, String> _cloudMappings = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    // 延迟加载数据，避开页面跳转的动画期
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) _loadHistory();
      });
    });
  }

  Future<void> _loadHistory() async {
    final history = await StorageService.getScreenTimeHistory();
    final mappings = await StorageService.getAppMappings();

    // 确保今日历史被今日的最新精确数据覆盖
    String todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    history[todayStr] = widget.todayStats;

    if (mounted) {
      setState(() {
        _historyStats = history;
        _cloudMappings = mappings;
        _isLoading = false;
      });
    }

    // 异步检查并补充缺失的近七日云端数据
    _fetchCloudHistory();
  }

  Future<void> _fetchCloudHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      int? userId = prefs.getInt('current_user_id');
      if (userId == null) return;

      DateTime now = DateTime.now();
      bool hasChanges = false;

      // 并发拉取过去 6 天的云端数据
      List<Future<void>> fetchTasks = [];
      for (int i = 1; i <= 6; i++) {
        DateTime d = now.subtract(Duration(days: i));
        String dateStr = DateFormat('yyyy-MM-dd').format(d);

        // 核心优化：如果本地已经存在这天的数据且不为空，说明以前已经加载/缓存过，跳过网络请求
        if (_historyStats.containsKey(dateStr) && _historyStats[dateStr]!.isNotEmpty) {
          continue;
        }

        fetchTasks.add(() async {
          try {
            var cloudData = await ApiService.fetchScreenTime(userId, dateStr);
            if (cloudData.isNotEmpty) {
              _historyStats[dateStr] = cloudData;
              hasChanges = true;
            }
          } catch (_) {
            // 忽略单次请求错误
          }
        }());
      }

      if (fetchTasks.isNotEmpty) {
        await Future.wait(fetchTasks);
      }

      if (hasChanges) {
        // 将新获取的完整历史数据覆盖保存到本地，下次进入将直接命中缓存
        await prefs.setString(StorageService.KEY_SCREEN_TIME_HISTORY, jsonEncode(_historyStats));

        if (mounted) {
          setState(() {}); // 刷新图表渲染
        }
      }
    } catch (e) {
      debugPrint("拉取或保存历史云端数据失败: $e");
    }
  }

  // --- 核心过滤与格式化方法 ---
  bool _matchesFilter(String deviceName, DeviceFilter filter) {
    deviceName = deviceName.toLowerCase();
    switch (filter) {
      case DeviceFilter.all: return true;
      case DeviceFilter.pc: return deviceName.contains("windows") || deviceName.contains("pc") || deviceName.contains("lapt");
      case DeviceFilter.mobile: return deviceName.contains("phone") || deviceName.contains("tablet");
      case DeviceFilter.phone: return deviceName.contains("phone");
      case DeviceFilter.tablet: return deviceName.contains("tablet");
    }
  }

  List<dynamic> _getFilteredStats(List<dynamic> rawStats, DeviceFilter filter) {
    return rawStats.where((item) {
      String dName = item['device_name'] ?? "";
      return _matchesFilter(dName, filter);
    }).toList();
  }

  int _getTotalDuration(List<dynamic> rawStats, DeviceFilter filter) {
    final filtered = _getFilteredStats(rawStats, filter);
    return filtered.fold(0, (sum, item) => sum + (item['duration'] as int));
  }

  static String formatHM(int totalSeconds) {
    if (totalSeconds == 0) return "0分钟";
    int h = totalSeconds ~/ 3600;
    int m = (totalSeconds % 3600) ~/ 60;
    int s = totalSeconds % 60;
    if (h > 0) return "${h}小时 ${m}分钟";
    if (m > 0) return "${m}分钟";
    return "${s}秒";
  }

  static String formatShortHM(int totalSeconds) {
    if (totalSeconds == 0) return "0分";
    int h = totalSeconds ~/ 3600;
    int m = (totalSeconds % 3600) ~/ 60;
    if (h > 0) return "${h}时${m}分";
    if (m > 0) return "${m}分";
    return "${totalSeconds}秒";
  }

  static String simplifyDeviceName(String device) {
    device = device.toLowerCase();
    if (device.contains("phone")) return "手机";
    if (device.contains("tablet")) return "平板";
    if (device.contains("windows") || device.contains("pc") || device.contains("lapt")) return "电脑";
    return "未知设备";
  }

  static IconData getDeviceIcon(String device) {
    device = device.toLowerCase();
    if (device.contains("phone")) return Icons.smartphone;
    if (device.contains("tablet")) return Icons.tablet_android;
    if (device.contains("windows") || device.contains("pc") || device.contains("lapt")) return Icons.laptop_windows;
    return Icons.devices;
  }

  static IconData getCategoryIcon(String category) {
    switch (category) {
      case '社交通讯': return Icons.chat_bubble_outline;
      case '影音娱乐': return Icons.movie_creation_outlined;
      case '学习办公': return Icons.menu_book_outlined;
      case '实用工具': return Icons.build_circle_outlined;
      case '购物支付': return Icons.shopping_bag_outlined;
      case '导航出行': return Icons.map_outlined;
      case '游戏与辅助': return Icons.sports_esports_outlined;
      case '健康运动': return Icons.directions_run_outlined;
      case '系统应用': return Icons.settings_applications_outlined;
      case '其他类别': return Icons.more_horiz;
      case '未分类': return Icons.help_outline;
      default: return Icons.category_outlined;
    }
  }

  static String getCategoryForApp(String appName, String? backendCategory, Map<String, String> mappings) {
    if (mappings.containsKey(appName) && mappings[appName] != '未分类') {
      return mappings[appName]!;
    }
    if (backendCategory != null && backendCategory != '未分类') {
      return backendCategory;
    }

    String lower = appName.toLowerCase();
    if (lower.contains('微信') || lower.contains('qq') || lower.contains('小红书') || lower.contains('短信') || lower.contains('微博') || lower.contains('weixin')) return '社交通讯';
    if (lower.contains('抖音') || lower.contains('哔哩') || lower.contains('bilibili') || lower.contains('网易云') || lower.contains('音乐') || lower.contains('视频') || lower.contains('大麦') || lower.contains('猫眼') || lower.contains('直播') || lower.contains('纷玩岛') || lower.contains('全民k歌')) return '影音娱乐';
    if (lower.contains('豆包') || lower.contains('千问') || lower.contains('效率') || lower.contains('数学') || lower.contains('word') || lower.contains('excel') || lower.contains('studio') || lower.contains('工大') || lower.contains('clion') || lower.contains('笔记') || lower.contains('math')) return '学习办公';
    if (lower.contains('计算器') || lower.contains('天气') || lower.contains('时钟') || lower.contains('日历') || lower.contains('相册') || lower.contains('相机') || lower.contains('浏览') || lower.contains('edge') || lower.contains('chrome') || lower.contains('管家') || lower.contains('压缩') || lower.contains('设置') || lower.contains('管理') || lower.contains('助手') || lower.contains('intent')) return '实用工具';
    if (lower.contains('淘宝') || lower.contains('拼多多') || lower.contains('京东') || lower.contains('支付宝') || lower.contains('闲鱼') || lower.contains('美团')) return '购物支付';
    if (lower.contains('地图') || lower.contains('12306') || lower.contains('火车') || lower.contains('出行') || lower.contains('打车') || lower.contains('导航') || lower.contains('公交')) return '导航出行';
    if (lower.contains('原神') || lower.contains('yuanshen') || lower.contains('米游') || lower.contains('启动器') || lower.contains('游戏') || lower.contains('王者') || lower.contains('和平精英')) return '游戏与辅助';
    if (lower.contains('健康') || lower.contains('运动') || lower.contains('手环') || lower.contains('体育') || lower.contains('health')) return '健康运动';
    if (lower.contains('桌面') || lower.contains('系统') || lower.contains('组件') || lower.contains('商店') || lower.contains('服务') || lower.contains('安全') || lower.contains('分享') || lower.contains('副屏') || lower.contains('协同') || lower.contains('小爱') || lower.contains('账号')) return '系统应用';

    return '未分类';
  }

  static List<MapEntry<String, Map<String, dynamic>>> getGroupedApps(List<dynamic> filteredStats) {
    Map<String, Map<String, dynamic>> grouped = {};
    for (var item in filteredStats) {
      String appName = item['app_name'] ?? "未知应用";
      String deviceName = item['device_name'] ?? "未知设备";
      int duration = item['duration'] ?? 0;

      if (!grouped.containsKey(appName)) {
        grouped[appName] = {'total': 0, 'devices': <String, int>{}};
      }

      grouped[appName]!['total'] = (grouped[appName]!['total'] as int) + duration;
      Map<String, int> deviceMap = grouped[appName]!['devices'];
      deviceMap[deviceName] = (deviceMap[deviceName] ?? 0) + duration;
    }

    var sorted = grouped.entries.toList();
    sorted.sort((a, b) => (b.value['total'] as int).compareTo(a.value['total'] as int));
    return sorted;
  }

  static Widget buildDeviceBreakdown(Map<String, int> devices, bool isAllFilter) {
    if (!isAllFilter && devices.length == 1) {
      return Text(simplifyDeviceName(devices.keys.first), style: const TextStyle(fontSize: 10, color: Colors.blueGrey));
    }
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: devices.entries.map((e) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(getDeviceIcon(e.key), size: 12, color: Colors.blueGrey),
            const SizedBox(width: 2),
            Text(
                "${simplifyDeviceName(e.key)} ${formatShortHM(e.value)}",
                style: const TextStyle(fontSize: 10, color: Colors.blueGrey, fontWeight: FontWeight.w600)
            ),
          ],
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text("详细统计", style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildMainContent(),
    );
  }

  Widget _buildMainContent() {
    DateTime now = DateTime.now();
    String todayStr = DateFormat('yyyy-MM-dd').format(now);
    String yesterdayStr = DateFormat('yyyy-MM-dd').format(now.subtract(const Duration(days: 1)));

    int todayTotal = _getTotalDuration(_historyStats[todayStr] ?? [], _currentFilter);
    int yesterdayTotal = _getTotalDuration(_historyStats[yesterdayStr] ?? [], _currentFilter);
    int diff = todayTotal - yesterdayTotal;

    final filteredTodayStats = _getFilteredStats(_historyStats[todayStr] ?? [], _currentFilter);
    final topApps = getGroupedApps(filteredTodayStats);

    Map<String, List<dynamic>> categoryGroups = {};
    for (var item in filteredTodayStats) {
      String appName = item['app_name'] ?? '未知应用';
      String cat = getCategoryForApp(appName, item['category'], _cloudMappings);

      item['category'] = cat;

      if (!categoryGroups.containsKey(cat)) categoryGroups[cat] = [];
      categoryGroups[cat]!.add(item);
    }

    List<MapEntry<String, int>> catDurations = categoryGroups.entries.map((e) {
      int dur = e.value.fold(0, (sum, item) => sum + (item['duration'] as int));
      return MapEntry(e.key, dur);
    }).toList();

    catDurations.sort((a, b) => b.value.compareTo(a.value));

    List<Map<String, dynamic>> finalCategories = [];
    if (catDurations.length <= 6) {
      for (var entry in catDurations) {
        finalCategories.add({'name': entry.key, 'duration': entry.value, 'items': categoryGroups[entry.key]});
      }
    } else {
      for (int i = 0; i < 5; i++) {
        var entry = catDurations[i];
        finalCategories.add({'name': entry.key, 'duration': entry.value, 'items': categoryGroups[entry.key]});
      }
      int otherDur = 0;
      List<dynamic> otherItems = [];
      for (int i = 5; i < catDurations.length; i++) {
        otherDur += catDurations[i].value;
        otherItems.addAll(categoryGroups[catDurations[i].key]!);
      }
      finalCategories.add({'name': '其他类别', 'duration': otherDur, 'items': otherItems});
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFilters(),
          _buildTotalCard(todayTotal, diff),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionHeader("近七日趋势", Icons.bar_chart),
                _buildChartCard(now),

                const SizedBox(height: 24),

                if (finalCategories.isNotEmpty) ...[
                  _buildSectionHeader("今日类别分布", Icons.category_rounded),
                  _buildCategoryGrid(finalCategories),
                  const SizedBox(height: 24),
                ],

                if (topApps.isNotEmpty) ...[
                  _buildSectionHeader("今日最常使用", Icons.dashboard_rounded),
                  _buildTop4Grid(topApps),
                  const SizedBox(height: 24),
                ],

                if (topApps.length > 4) ...[
                  _buildSectionHeader("其余应用明细", Icons.format_list_bulleted_rounded),
                  _buildRestList(topApps),
                ],

                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return SizedBox(
      height: 55,
      child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          itemCount: DeviceFilter.values.length,
          itemBuilder: (ctx, i) {
            final filter = DeviceFilter.values[i];
            return Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: ChoiceChip(
                label: Text(filter.label, style: const TextStyle(fontWeight: FontWeight.bold)),
                selected: _currentFilter == filter,
                onSelected: (selected) {
                  if (selected) setState(() => _currentFilter = filter);
                },
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                showCheckmark: false,
              ),
            );
          }
      ),
    );
  }

  Widget _buildTotalCard(int todayTotal, int diff) {
    bool isIncrease = diff >= 0;
    String diffText = "较昨日${isIncrease ? '增加' : '减少'} ${formatHM(diff.abs())}";

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Card(
        elevation: 2,
        color: Theme.of(context).colorScheme.surfaceContainer.withOpacity(0.95),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("今日使用时长", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                    const SizedBox(height: 8),
                    Text(
                      formatHM(todayTotal),
                      style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.primary),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(isIncrease ? Icons.trending_up : Icons.trending_down, size: 16, color: isIncrease ? Colors.orange.shade800 : Colors.green.shade800),
                        const SizedBox(width: 4),
                        Text(diffText, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isIncrease ? Colors.orange.shade800 : Colors.green.shade800)),
                      ],
                    )
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.access_time_filled, size: 40, color: Theme.of(context).colorScheme.primary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChartCard(DateTime now) {
    List<int> dailyTotals = [];
    List<String> labels = [];

    // 收集过去 7 天的数据
    for (int i = 6; i >= 0; i--) {
      DateTime d = now.subtract(Duration(days: i));
      String dateStr = DateFormat('yyyy-MM-dd').format(d);
      String labelStr = i == 0 ? "今日" : DateFormat('MM/dd').format(d);

      int total = _getTotalDuration(_historyStats[dateStr] ?? [], _currentFilter);
      dailyTotals.add(total);
      labels.add(labelStr);
    }

    return Card(
      elevation: 2,
      color: Theme.of(context).colorScheme.surfaceContainer.withOpacity(0.95),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: SizedBox(
          width: double.infinity,
          height: 200,
          child: CustomPaint(
            painter: BarChartPainter(
              data: dailyTotals,
              labels: labels,
              primaryColor: Theme.of(context).colorScheme.primary,
              textColor: Colors.blueGrey,
            ),
          ),
        ),
      ),
    );
  }

  // --- 3x2 分类宫格 ---
  Widget _buildCategoryGrid(List<Map<String, dynamic>> categories) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.0,
      ),
      itemCount: categories.length,
      itemBuilder: (ctx, i) {
        final cat = categories[i];
        final String name = cat['name'];
        final int dur = cat['duration'];
        final List<dynamic> items = cat['items'];

        return InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => CategoryDetailScreen(
                categoryName: name,
                stats: items,
                isAllFilter: _currentFilter == DeviceFilter.all,
              )),
            );
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.6),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.withOpacity(0.1)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(getCategoryIcon(name), color: Theme.of(context).colorScheme.primary, size: 28),
                const SizedBox(height: 8),
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 4),
                Text(formatShortHM(dur), style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- Top 4 应用宫格 (2x2) ---
  Widget _buildTop4Grid(List<MapEntry<String, Map<String, dynamic>>> apps) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.15,
      ),
      itemCount: math.min(4, apps.length),
      itemBuilder: (ctx, i) {
        final app = apps[i];
        final devices = app.value['devices'] as Map<String, int>;

        return Container(
          decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainer.withOpacity(0.95),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 4, offset: const Offset(0, 2))
              ]
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.15),
                    child: Text(
                      app.key.isNotEmpty ? app.key[0].toUpperCase() : "?",
                      style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(app.key, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
                ],
              ),
              const Spacer(),
              Text(formatHM(app.value['total'] as int), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.primary)),

              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: buildDeviceBreakdown(devices, _currentFilter == DeviceFilter.all),
              ),
            ],
          ),
        );
      },
    );
  }

  // --- 其余应用列表 ---
  Widget _buildRestList(List<MapEntry<String, Map<String, dynamic>>> apps) {
    return Card(
      elevation: 2,
      color: Theme.of(context).colorScheme.surfaceContainer.withOpacity(0.95),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: apps.length - 4,
        separatorBuilder: (_, __) => Divider(height: 1, indent: 60, endIndent: 16, color: Colors.grey.withOpacity(0.15)),
        itemBuilder: (ctx, i) {
          final app = apps[i + 4];
          final devices = app.value['devices'] as Map<String, int>;

          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: CircleAvatar(
              radius: 20,
              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Text(
                app.key.isNotEmpty ? app.key[0].toUpperCase() : "?",
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
            title: Text(app.key, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: buildDeviceBreakdown(devices, _currentFilter == DeviceFilter.all)
            ),
            trailing: Text(formatHM(app.value['total'] as int), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.blueGrey)),
          );
        },
      ),
    );
  }
}

// ==========================================
// 新增：三级界面 (分类详情)
// ==========================================
class CategoryDetailScreen extends StatelessWidget {
  final String categoryName;
  final List<dynamic> stats;
  final bool isAllFilter;

  const CategoryDetailScreen({
    super.key,
    required this.categoryName,
    required this.stats,
    required this.isAllFilter,
  });

  @override
  Widget build(BuildContext context) {
    final apps = _ScreenTimeDetailScreenState.getGroupedApps(stats);
    int totalDur = apps.fold(0, (sum, app) => sum + (app.value['total'] as int));

    return Scaffold(
      appBar: AppBar(
        title: Text(categoryName),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
            child: Column(
              children: [
                Icon(_ScreenTimeDetailScreenState.getCategoryIcon(categoryName), size: 48, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 12),
                Text("该类别总计", style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                const SizedBox(height: 4),
                Text(
                  _ScreenTimeDetailScreenState.formatHM(totalDur),
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary),
                ),
              ],
            ),
          ),
          Expanded(
            child: apps.isEmpty
                ? const Center(child: Text("暂无数据"))
                : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: apps.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final app = apps[i];
                final devices = app.value['devices'] as Map<String, int>;
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  leading: CircleAvatar(
                    radius: 20,
                    backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                    child: Text(
                      app.key.isNotEmpty ? app.key[0].toUpperCase() : "?",
                      style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold),
                    ),
                  ),
                  title: Text(app.key, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: _ScreenTimeDetailScreenState.buildDeviceBreakdown(devices, isAllFilter)
                  ),
                  trailing: Text(_ScreenTimeDetailScreenState.formatHM(app.value['total'] as int),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                );
              },
            ),
          )
        ],
      ),
    );
  }
}

// --- 纯手工绘制：带高亮与平均线的近七日柱状图 ---
class BarChartPainter extends CustomPainter {
  final List<int> data;
  final List<String> labels;
  final Color primaryColor;
  final Color textColor;

  BarChartPainter({required this.data, required this.labels, required this.primaryColor, required this.textColor});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty || size.width == 0) return;

    final double bottomPadding = 30.0;
    final double topPadding = 25.0;
    final double chartHeight = size.height - bottomPadding - topPadding;

    int maxVal = data.reduce(math.max);
    if (maxVal == 0) maxVal = 1;

    double avgVal = data.reduce((a, b) => a + b) / data.length;

    final double barWidth = (size.width / data.length) * 0.35;
    final double spacing = size.width / data.length;

    final Paint barPaint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < data.length; i++) {
      double xCenter = (i * spacing) + (spacing / 2);
      double barH = (data[i] / maxVal) * chartHeight;

      barPaint.color = (i == data.length - 1) ? primaryColor : primaryColor.withOpacity(0.25);

      Rect barRect = Rect.fromLTWH(xCenter - barWidth / 2, size.height - bottomPadding - barH, barWidth, barH);
      RRect rRect = RRect.fromRectAndRadius(barRect, const Radius.circular(6));
      canvas.drawRRect(rRect, barPaint);

      if (data[i] == maxVal && maxVal > 1) {
        String hm = _ScreenTimeDetailScreenState.formatShortHM(data[i]);
        _drawText(canvas, hm, Offset(xCenter, size.height - bottomPadding - barH - 12), fontSize: 10, color: primaryColor, bold: true);
      }

      _drawText(canvas, labels[i], Offset(xCenter, size.height - 12), fontSize: 11, color: textColor, bold: i == data.length - 1);
    }

    if (avgVal > 0) {
      double avgY = size.height - bottomPadding - ((avgVal / maxVal) * chartHeight);
      final Paint dashPaint = Paint()
        ..color = Colors.orangeAccent.shade400
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;

      _drawDashedLine(canvas, Offset(0, avgY), Offset(size.width, avgY), dashPaint);

      _drawText(canvas, "平均 ${_ScreenTimeDetailScreenState.formatShortHM(avgVal.toInt())}", Offset(size.width - 25, avgY - 10), fontSize: 10, color: Colors.orange.shade800, bold: true);
    }
  }

  void _drawText(Canvas canvas, String text, Offset center, {double fontSize = 12, Color color = Colors.black, bool bold = false}) {
    final textPainter = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: color, fontSize: fontSize, fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(canvas, Offset(center.dx - textPainter.width / 2, center.dy - textPainter.height / 2));
  }

  void _drawDashedLine(Canvas canvas, Offset p1, Offset p2, Paint paint) {
    const double dashWidth = 5;
    const double dashSpace = 5;
    double distance = (p2 - p1).distance;
    double dx = (p2.dx - p1.dx) / distance;
    double dy = (p2.dy - p1.dy) / distance;

    double startX = p1.dx;
    double startY = p1.dy;

    while (distance >= 0) {
      double drawLen = math.min(dashWidth, distance);
      canvas.drawLine(Offset(startX, startY), Offset(startX + dx * drawLen, startY + dy * drawLen), paint);
      startX += dx * (dashWidth + dashSpace);
      startY += dy * (dashWidth + dashSpace);
      distance -= (dashWidth + dashSpace);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}