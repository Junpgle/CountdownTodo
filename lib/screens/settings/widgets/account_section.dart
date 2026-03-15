import 'package:flutter/material.dart';

class AccountSection extends StatelessWidget {
  final String username;
  final int? userId;
  final String userTier;
  final double syncProgress;
  final bool isLoadingStatus;
  final VoidCallback onRefreshStatus;
  final VoidCallback onForceFullSync;
  final VoidCallback onLogout;
  final VoidCallback onChangePassword;

  const AccountSection({
    Key? key,
    required this.username,
    required this.userId,
    required this.userTier,
    required this.syncProgress,
    required this.isLoadingStatus,
    required this.onRefreshStatus,
    required this.onForceFullSync,
    required this.onLogout,
    required this.onChangePassword,
  }) : super(key: key);

  Color getTierColor(String tier) {
    switch (tier.toLowerCase()) {
      case 'admin':
        return Colors.redAccent;
      case 'promax':
        return Colors.purpleAccent; // 或金色 #FFD700
      case 'pro':
        return Colors.orangeAccent;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 8.0, bottom: 8.0, top: 16.0),
          child: Text('账户管理',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey)),
        ),
        Card(
          elevation: 2,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Column(
            children: [
              ListTile(
                leading: CircleAvatar(
                    backgroundColor:
                        Theme.of(context).colorScheme.primaryContainer,
                    child: const Icon(Icons.person)),
                title: Text(username,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(userId != null ? "UID: $userId" : "离线模式"),
                trailing:
                    const Icon(Icons.edit_square, size: 20, color: Colors.grey),
                onTap: onChangePassword,
              ),
              const Divider(height: 1, indent: 56),
              Padding(
                padding: const EdgeInsets.only(
                    left: 56, right: 16, top: 12, bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("账户等级", style: TextStyle(fontSize: 14)),
                        isLoadingStatus
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : Text(
                                  userTier.toUpperCase(),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: getTierColor(userTier)
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text("今日同步额度",
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: syncProgress,
                        minHeight: 6,
                        backgroundColor: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation<Color>(
                            syncProgress > 0.9
                                ? Colors.redAccent
                                : Theme.of(context).colorScheme.primary),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, indent: 56),
              ListTile(
                leading: const Icon(Icons.cloud_sync, color: Colors.deepPurple),
                title: const Text('强制全量同步'),
                subtitle: const Text('重置同步水位，从云端拉取所有最新数据'),
                trailing: const Icon(Icons.chevron_right),
                onTap: onForceFullSync,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
