import 'package:flutter/material.dart';
import '../../../services/api_service.dart';

class ChangePasswordDialog extends StatefulWidget {
  final int userId;
  final Function(bool force) onLogout;

  const ChangePasswordDialog({
    Key? key,
    required this.userId,
    required this.onLogout,
  }) : super(key: key);

  @override
  State<ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<ChangePasswordDialog> {
  final oldPassCtrl = TextEditingController();
  final newPassCtrl = TextEditingController();
  final confirmPassCtrl = TextEditingController();
  bool isSubmitting = false;

  @override
  void dispose() {
    oldPassCtrl.dispose();
    newPassCtrl.dispose();
    confirmPassCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("修改密码"),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: oldPassCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: "当前密码",
                  prefixIcon: Icon(Icons.lock_outline)),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: newPassCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: "新密码", prefixIcon: Icon(Icons.lock)),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: confirmPassCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: "确认新密码",
                  prefixIcon: Icon(Icons.check_circle_outline)),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: isSubmitting ? null : () => Navigator.pop(context),
            child: const Text("取消")),
        FilledButton(
          onPressed: isSubmitting
              ? null
              : () async {
            if (newPassCtrl.text != confirmPassCtrl.text) {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('两次输入的新密码不一致')));
              return;
            }
            if (newPassCtrl.text.isEmpty ||
                oldPassCtrl.text.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('请填写完整')));
              return;
            }

            setState(() => isSubmitting = true);
            final res = await ApiService.changePassword(
                widget.userId, oldPassCtrl.text, newPassCtrl.text);
            setState(() => isSubmitting = false);

            if (!mounted) return;
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(res['message'] ??
                    (res['success'] ? '修改成功' : '修改失败'))));

            if (res['success']) {
              widget.onLogout(true);
            }
          },
          child: isSubmitting
              ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white))
              : const Text("确认修改"),
        ),
      ],
    );
  }
}
