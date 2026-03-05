import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'course_service.dart';
import '../storage_service.dart';

class ExternalShareHandler {
  static StreamSubscription? _intentDataStreamSubscription;
  static bool _isProcessing = false; // 🚀 终极防抖锁：防止系统疯狂发送 Intent 导致多线程死循环卡死 ANR

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
    // 🚀 核心拦截：如果正在处理，或者文件为空，立刻抛弃后续的重复通知！
    if (files.isEmpty || _isProcessing) return;
    _isProcessing = true;

    // 🚀 防白屏修复：给 Flutter 引擎留出 500 毫秒画出第一帧主页界面，然后再弹窗
    await Future.delayed(const Duration(milliseconds: 500));

    // 确保调用环境还存活
    if (!context.mounted) {
      _isProcessing = false;
      return;
    }

    ValueNotifier<String> statusNotifier = ValueNotifier("获取课表文件中...");
    BuildContext? dialogContext; // 🚀 独立捕获弹窗的 Context，保证 100% 能把它关掉

    // 弹出不可取消的进度弹窗
    showDialog(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (ctx) {
        dialogContext = ctx; // 记录弹窗自己的专属生命周期
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
      // 过渡动画延时
      await Future.delayed(const Duration(milliseconds: 400));
      statusNotifier.value = "正在识别课表类型...";

      // 获取传递过来的文件路径
      String filePath = files.first.path;
      File file = File(filePath);

      // 安全读取文件内容
      String content = await _safeReadFile(file);
      String ext = filePath.split('.').last.toLowerCase();

      await Future.delayed(const Duration(milliseconds: 400));

      bool success = false;
      String sourceName = "";

      // 智能嗅探文件类型与内容特征
      if (ext == 'ics' || content.contains('BEGIN:VCALENDAR')) {
        sourceName = "西安电子科技大学";
        statusNotifier.value = "识别到: $sourceName\n正在导入...";

        DateTime? semStart = await StorageService.getSemesterStart();
        if (semStart == null) {
          statusNotifier.value = "⚠️ 导入中断\n请先在设置中配置【开学日期】";
          await Future.delayed(const Duration(seconds: 2));
          _closeDialogSafely(dialogContext);
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
          _closeDialogSafely(dialogContext);
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
        _closeDialogSafely(dialogContext);
        return;
      }

      // 提示结果并刷新主页
      if (success) {
        statusNotifier.value = "✅ 导入成功！\n正在刷新课表...";
        await Future.delayed(const Duration(milliseconds: 800));
        _closeDialogSafely(dialogContext);
        onSuccess(); // 通知主页刷新数据
      } else {
        statusNotifier.value = "❌ 导入失败\n课表解析错误或文件已损坏";
        await Future.delayed(const Duration(seconds: 2));
        _closeDialogSafely(dialogContext);
      }

    } catch (e) {
      debugPrint("处理外部共享文件崩溃: $e");
      statusNotifier.value = "❌ 发生异常\n读取文件失败或格式崩溃";
      await Future.delayed(const Duration(seconds: 2));
      _closeDialogSafely(dialogContext);
    } finally {
      // 🚀 终极清理：彻底斩断所有后续排队的重复意图，并释放互斥锁
      ReceiveSharingIntent.instance.reset();
      _isProcessing = false;
    }
  }

  /// 🚀 核心修复：绝对安全的关闭弹窗方法，不依赖外部主页的存活状态
  static void _closeDialogSafely(BuildContext? dialogContext) {
    if (dialogContext != null && dialogContext.mounted) {
      Navigator.pop(dialogContext);
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