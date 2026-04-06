import 'dart:io';
import 'package:flutter/material.dart';

class SystemSection extends StatelessWidget {
  final VoidCallback onOpenFeatureGuide;
  final String cacheSizeStr;
  final VoidCallback onClearCache;
  final VoidCallback onShowStorageAnalysis;
  final bool isCheckingUpdate;
  final VoidCallback onCheckUpdates;
  final VoidCallback onLogout;
  final VoidCallback onViewPrivacyPolicy;
  final VoidCallback onWithdrawPrivacyAgreement;

  const SystemSection({
    Key? key,
    required this.onOpenFeatureGuide,
    required this.cacheSizeStr,
    required this.onClearCache,
    required this.onShowStorageAnalysis,
    required this.isCheckingUpdate,
    required this.onCheckUpdates,
    required this.onLogout,
    required this.onViewPrivacyPolicy,
    required this.onWithdrawPrivacyAgreement,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 8.0, bottom: 8.0, top: 16.0),
          child: Text('系统与关于',
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
                leading: const Icon(Icons.school_rounded, color: Colors.indigo),
                title: const Text('重新查看新版教程与权限设置'),
                subtitle: const Text('可再次查看功能介绍与重新配置各项权限'),
                trailing: const Icon(Icons.chevron_right),
                onTap: onOpenFeatureGuide,
              ),
              if (!Platform.isWindows) ...[
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.cleaning_services,
                      color: Colors.blueAccent),
                  title: const Text('深度清理缓存与冗余'),
                  subtitle: const Text('包含更新残留包与深度图片缓存'),
                  trailing: Text(cacheSizeStr,
                      style: const TextStyle(
                          color: Colors.grey, fontWeight: FontWeight.bold)),
                  onTap: onClearCache,
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.data_usage, color: Colors.orange),
                  title: const Text('存储空间深度分析'),
                  subtitle: const Text('找出占用数百MB的隐藏文件'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: onShowStorageAnalysis,
                ),
              ],
              const Divider(height: 1, indent: 56),
              ListTile(
                leading: const Icon(Icons.system_update, color: Colors.green),
                title: const Text('检查新版本'),
                trailing: isCheckingUpdate
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.chevron_right),
                onTap: isCheckingUpdate ? null : onCheckUpdates,
              ),
              const Divider(height: 1, indent: 56),
              ListTile(
                leading:
                    const Icon(Icons.privacy_tip_outlined, color: Colors.teal),
                title: const Text('隐私政策'),
                subtitle: const Text('查看完整隐私政策内容'),
                trailing: const Icon(Icons.chevron_right),
                onTap: onViewPrivacyPolicy,
              ),
              const Divider(height: 1, indent: 56),
              ListTile(
                leading: const Icon(Icons.do_not_disturb_on_outlined,
                    color: Colors.orange),
                title: const Text('撤回隐私政策同意'),
                subtitle: const Text('撤回后将无法使用需要同步的功能'),
                onTap: onWithdrawPrivacyAgreement,
              ),
              const Divider(height: 1, indent: 56),
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.redAccent),
                title: const Text('退出当前账号',
                    style: TextStyle(color: Colors.redAccent)),
                onTap: onLogout,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
