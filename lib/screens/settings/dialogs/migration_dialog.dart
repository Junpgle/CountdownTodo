import 'package:flutter/material.dart';
import '../../../services/api_service.dart';
import '../../../services/migration_service.dart';

class MigrationDialog extends StatefulWidget {
  final VoidCallback onSuccess;

  const MigrationDialog({
    Key? key,
    required this.onSuccess,
  }) : super(key: key);

  @override
  State<MigrationDialog> createState() => _MigrationDialogState();
}

class _MigrationDialogState extends State<MigrationDialog> {
  final emailCtrl = TextEditingController();
  final passCtrl = TextEditingController();
  bool isMigrating = false;
  String statusText = "";

  @override
  void dispose() {
    emailCtrl.dispose();
    passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("一键全量账号与数据迁移"),
      content: isMigrating
          ? Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 20),
          Text(statusText, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), textAlign: TextAlign.center),
        ],
      )
          : Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('请输入您最初在 Cloudflare 服务器上注册用的邮箱与密码。系统会自动验证拉取，随后向阿里云注入您的配置。', style: TextStyle(fontSize: 13)),
          const SizedBox(height: 16),
          TextField(
            controller: emailCtrl,
            decoration: const InputDecoration(labelText: '旧账号邮箱', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: passCtrl,
            obscureText: true,
            decoration: const InputDecoration(labelText: '旧账号密码', border: OutlineInputBorder()),
          ),
        ],
      ),
      actions: isMigrating
          ? null
          : [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("取消")),
        FilledButton(
            onPressed: () async {
              if (emailCtrl.text.isEmpty || passCtrl.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('不能留空哦')));
                return;
              }

              setState(() {
                isMigrating = true;
                statusText = "准备中...";
              });

              try {
                await MigrationService.runMigration(
                    context: context,
                    oldUrl: ApiService.cloudflareUrl,  // D1 URL
                    newUrl: ApiService.aliyunUrl, // ECS URL
                    email: emailCtrl.text,
                    password: passCtrl.text,
                    onProgress: (msg) {
                      setState(() => statusText = msg);
                    }
                );

                if (!mounted) return;
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ 迁移大成功！您的所有数据和账户已落户阿里云。')));
                widget.onSuccess();
              } catch (e) {
                setState(() {
                  isMigrating = false;
                  statusText = "";
                });
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ 迁移失败: $e')));
                }
              }
            },
            child: const Text("验证并开始迁移")
        ),
      ],
    );
  }
}
