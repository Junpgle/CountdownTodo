import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'course_service.dart';
import '../storage_service.dart';

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

    // 🚀 使用 ValueNotifier 来驱动弹窗内的文本变化，实现步骤播报
    ValueNotifier<String> statusNotifier = ValueNotifier("获取课表文件中...");

    // 弹出不可取消的进度弹窗
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 20),
              Expanded(
                child: ValueListenableBuilder<String>(
                  valueListenable: statusNotifier,
                  builder: (context, value, child) {
                    return Text(
                      value,
                      style: const TextStyle(fontSize: 15, height: 1.4),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );

    try {
      // 稍微加一点延时，防止处理太快导致弹窗一闪而过体验不佳
      await Future.delayed(const Duration(milliseconds: 600));
      statusNotifier.value = "正在识别课表类型...";

      // 获取传递过来的文件路径
      String filePath = files.first.path;
      File file = File(filePath);

      // 1. 安全读取文件内容
      String content = await _safeReadFile(file);
      String ext = filePath.split('.').last.toLowerCase();

      await Future.delayed(const Duration(milliseconds: 600));

      bool success = false;
      String sourceName = "";

      // 2. 🚀 智能嗅探文件类型与内容特征
      if (ext == 'ics' || content.contains('BEGIN:VCALENDAR')) {
        sourceName = "西安电子科技大学";
        statusNotifier.value = "识别到: $sourceName\n正在导入...";

        DateTime? semStart = await StorageService.getSemesterStart();
        if (semStart == null) {
          statusNotifier.value = "⚠️ 导入中断\n请先在设置中配置【开学日期】";
          await Future.delayed(const Duration(seconds: 2));
          if (context.mounted) Navigator.pop(context);
          return;
        }
        success = await CourseService.importXidianScheduleFromIcs(content, semStart);
      }
      else if (['mhtml', 'html', 'htm'].contains(ext) || content.contains('quoted-printable') || content.toLowerCase().contains('<html')) {
        sourceName = "厦门大学";
        statusNotifier.value = "识别到: $sourceName\n正在深度解码导入...";

        DateTime? semStart = await StorageService.getSemesterStart();
        if (semStart == null) {
          statusNotifier.value = "⚠️ 导入中断\n请先在设置中配置【开学日期】";
          await Future.delayed(const Duration(seconds: 2));
          if (context.mounted) Navigator.pop(context);
          return;
        }
        success = await CourseService.importXmuScheduleFromHtml(content, semStart);
      }
      else if (['json', 'txt'].contains(ext) || content.trim().startsWith('[') || content.trim().startsWith('{')) {
        sourceName = "聚在工大";
        statusNotifier.value = "识别到: $sourceName\n正在导入...";

        success = await CourseService.importScheduleFromJson(content);
      }
      else {
        statusNotifier.value = "❌ 未知的文件格式\n暂不支持解析该文件";
        await Future.delayed(const Duration(seconds: 2));
        ReceiveSharingIntent.instance.reset();
        if (context.mounted) Navigator.pop(context);
        return;
      }

      // 3. 提示结果并刷新主页
      if (success) {
        statusNotifier.value = "✅ 导入成功！\n正在刷新课表...";
        await Future.delayed(const Duration(milliseconds: 800)); // 给用户一点时间看成功提示
        if (context.mounted) {
          Navigator.pop(context); // 关闭弹窗
          onSuccess(); // 通知主页刷新数据
        }
      } else {
        statusNotifier.value = "❌ 导入失败\n课表解析错误或文件已损坏";
        await Future.delayed(const Duration(seconds: 2));
        if (context.mounted) Navigator.pop(context);
      }

    } catch (e) {
      debugPrint("处理外部共享文件崩溃: $e");
      statusNotifier.value = "❌ 发生异常\n读取文件失败或格式崩溃";
      await Future.delayed(const Duration(seconds: 2));
      if (context.mounted) Navigator.pop(context);
    } finally {
      // 处理完毕后清空缓存意图，避免重复处理
      ReceiveSharingIntent.instance.reset();
    }
  }

  /// 辅助方法：安全读取文件，防止非 UTF-8 编码抛出异常
  static Future<String> _safeReadFile(File file) async {
    try {
      return await file.readAsString();
    } catch (e) {
      // 如果默认 readAsString 失败（通常是因为编码问题），降级为允许乱码的字节解码
      List<int> bytes = await file.readAsBytes();
      return utf8.decode(bytes, allowMalformed: true);
    }
  }

  /// 页面销毁时释放资源
  static void dispose() {
    _intentDataStreamSubscription?.cancel();
  }
}