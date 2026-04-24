import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models.dart';
import '../storage_service.dart';

class HistoricalCountdownsScreen extends StatefulWidget {
  final String username;
  const HistoricalCountdownsScreen({super.key, required this.username});

  @override
  State<HistoricalCountdownsScreen> createState() =>
      _HistoricalCountdownsScreenState();
}

class _HistoricalCountdownsScreenState
    extends State<HistoricalCountdownsScreen> {
  List<CountdownItem> _history = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final allCountdowns = await StorageService.getCountdowns(widget.username);
    setState(() {
      // 过滤出已过期的倒计时
      _history = allCountdowns.where((item) {
        return item.targetDate.difference(DateTime.now()).inDays + 1 < 0;
      }).toList();
      _isLoading = false;
    });
  }

  Future<void> _deleteItem(CountdownItem item) async {
    await StorageService.permanentlyDeleteCountdown(widget.username, item.id);
    _loadData();
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已彻底删除该历史记录')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('历史倒计时')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _history.isEmpty
              ? const Center(
                  child:
                      Text("暂无已过期的历史倒计时", style: TextStyle(color: Colors.grey)))
              : AnimatedList(
                  key: ValueKey('countdowns_${_history.length}'),
                  padding: const EdgeInsets.all(16),
                  initialItemCount: _history.length,
                  itemBuilder: (context, index, animation) {
                    final item = _history[index];
                    final diff =
                        (item.targetDate.difference(DateTime.now()).inDays + 1)
                            .abs();

                    return SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(-0.3, 0.0),
                        end: Offset.zero,
                      ).animate(CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutCubic,
                      )),
                      child: FadeTransition(
                        opacity: animation,
                        child: Card(
                          elevation: 0,
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest
                              .withValues(alpha: 0.5),
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          child: ListTile(
                            title: Text(item.title,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            subtitle: Text(
                                "目标日: ${DateFormat('yyyy-MM-dd').format(item.targetDate)}  (已过 $diff 天)"),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: Colors.redAccent),
                              onPressed: () => _deleteItem(item),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
