import 'dart:async';
import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'course_service.dart';

class ExternalShareHandler {
  static StreamSubscription? _intentDataStreamSubscription;

  /// 初始化监听，放在主页的 initState 中调用
  static void init(BuildContext context, Function onSuccessCallback) {
    // 1. 处理 App 在后台运行时，其他应用分享进来的文件 (热启动)
    _intentDataStreamSubscription = ReceiveSharingIntent.instance.getMediaStream().listen((List<SharedMediaFile> value) {
      _processSharedFiles(context, value, onSuccessCallback);
    }, onError: (err) {
      debugPrint("获取外部意图失败: $err");
    });

    // 2. 处理 App 未启动时，点击文件直接唤起 App (冷启动)
    ReceiveSharingIntent.instance.getInitialMedia().then((List<SharedMediaFile> value) {
      _processSharedFiles(context, value, onSuccessCallback);
    });
  }

  static void _processSharedFiles(BuildContext context, List<SharedMediaFile> files, Function onSuccess) async {
    if (files.isEmpty) return;

    // 获取传递过来的文件路径 (可能是 content:// 或 file:// 转换后的实际物理路径)
    String filePath = files.first.path;

    // 我们只处理 JSON 或 TXT 文件
    if (filePath.toLowerCase().endsWith('.json') || filePath.toLowerCase().endsWith('.txt')) {
      bool success = await CourseService.importScheduleFromFile(filePath);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? '✅ 外部课表解析成功！' : '❌ 课表解析失败，文件格式不符'),
            backgroundColor: success ? Colors.green : Colors.redAccent,
          ),
        );
        // 如果解析成功，调用传入的回调函数 (如 _loadAllData) 刷新主页卡片
        if (success) {
          onSuccess();
        }
      }
    }

    // 处理完毕后清空缓存意图，避免重复处理
    ReceiveSharingIntent.instance.reset();
  }

  /// 页面销毁时释放资源
  static void dispose() {
    _intentDataStreamSubscription?.cancel();
  }
}