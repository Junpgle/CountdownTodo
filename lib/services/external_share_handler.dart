import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'course_service.dart';
import '../storage_service.dart';
import 'llm_service.dart';

class ExternalShareHandler {
  static StreamSubscription? _intentDataStreamSubscription;
  static bool _isProcessing = false;

  /// 初始化监听，放在主页的 initState 中调用
  /// [onCourseImported] 课表导入成功回调
  /// [onTodoRecognized] 图片识别待办回调，传入识别结果列表
  static void init(
    BuildContext context,
    Function onCourseImported, {
    Function(List<Map<String, dynamic>>)? onTodoRecognized,
  }) {
    if (!Platform.isAndroid && !Platform.isIOS) return;

    _intentDataStreamSubscription =
        ReceiveSharingIntent.instance.getMediaStream().listen(
      (List<SharedMediaFile> value) {
        _processSharedFiles(context, value, onCourseImported,
            onTodoRecognized: onTodoRecognized);
      },
      onError: (err) {
        debugPrint("获取外部意图失败: $err");
      },
    );

    ReceiveSharingIntent.instance.getInitialMedia().then(
      (List<SharedMediaFile> value) {
        _processSharedFiles(context, value, onCourseImported,
            onTodoRecognized: onTodoRecognized);
      },
    );
  }

  static void _processSharedFiles(
    BuildContext context,
    List<SharedMediaFile> files,
    Function onSuccess, {
    Function(List<Map<String, dynamic>>)? onTodoRecognized,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (files.isEmpty || _isProcessing) return;
    _isProcessing = true;

    await Future.delayed(const Duration(milliseconds: 500));

    if (!context.mounted) {
      _isProcessing = false;
      return;
    }

    ValueNotifier<String> statusNotifier = ValueNotifier("处理中...");
    BuildContext? dialogContext;

    showDialog(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (ctx) {
        dialogContext = ctx;
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
      await Future.delayed(const Duration(milliseconds: 400));

      String filePath = files.first.path;
      File file = File(filePath);
      String ext = filePath.split('.').last.toLowerCase();

      // 检测是否为图片
      final imageExtensions = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'];
      final isImage = imageExtensions.contains(ext);

      if (isImage) {
        // 图片处理：调用大模型识别待办
        statusNotifier.value = "识别到图片\n正在调用大模型分析...";

        final config = await LLMService.getConfig();
        if (config == null || !config.isConfigured) {
          statusNotifier.value = "⚠️ 需要配置大模型API\n请在设置中配置后重试";
          await Future.delayed(const Duration(seconds: 2));
          _closeDialogSafely(dialogContext);
          return;
        }

        try {
          final results = await LLMService.parseTodoFromImage(filePath);

          statusNotifier.value = "✅ 识别成功！\n发现${results.length}个待办事项";
          await Future.delayed(const Duration(milliseconds: 800));
          _closeDialogSafely(dialogContext);

          if (onTodoRecognized != null && results.isNotEmpty) {
            onTodoRecognized(results);
          }
        } catch (e) {
          debugPrint("大模型图片识别失败: $e");
          statusNotifier.value = "❌ 图片识别失败\n$e";
          await Future.delayed(const Duration(seconds: 2));
          _closeDialogSafely(dialogContext);
        }
      } else {
        // 文件处理：课表导入
        statusNotifier.value = "获取课表文件中...";

        String content = await _safeReadFile(file);

        await Future.delayed(const Duration(milliseconds: 400));

        bool success = false;
        String sourceName = "";

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
          success = await CourseService.importXidianScheduleFromIcs(
              content, semStart);
        } else if (content.contains('timetable_con') ||
            content.contains('id="table1"')) {
          sourceName = "正方教务系统";
          statusNotifier.value = "识别到: $sourceName\n正在深度解析...";

          DateTime? semStart = await StorageService.getSemesterStart();
          if (semStart == null) {
            statusNotifier.value = "⚠️ 导入中断\n请先在设置中配置【开学日期】";
            await Future.delayed(const Duration(seconds: 2));
            _closeDialogSafely(dialogContext);
            return;
          }
          success = await CourseService.importZfSoftScheduleFromHtml(
              content, semStart);
        } else if (['mhtml', 'html', 'htm'].contains(ext) ||
            content.contains('quoted-printable') ||
            content.toLowerCase().contains('<html')) {
          sourceName = "厦门大学";
          statusNotifier.value = "识别到: $sourceName\n正在深度解码导入...";

          DateTime? semStart = await StorageService.getSemesterStart();
          if (semStart == null) {
            statusNotifier.value = "⚠️ 导入中断\n请先在设置中配置【开学日期】";
            await Future.delayed(const Duration(seconds: 2));
            _closeDialogSafely(dialogContext);
            return;
          }
          success =
              await CourseService.importXmuScheduleFromHtml(content, semStart);
        } else if (['json', 'txt'].contains(ext) ||
            content.trim().startsWith('[') ||
            content.trim().startsWith('{')) {
          sourceName = "聚在工大";
          statusNotifier.value = "识别到: $sourceName\n正在导入...";
          success = await CourseService.importScheduleFromJson(content);
        } else {
          statusNotifier.value = "❌ 未知的文件格式\n暂不支持解析该文件";
          await Future.delayed(const Duration(seconds: 2));
          _closeDialogSafely(dialogContext);
          return;
        }

        if (success) {
          statusNotifier.value = "✅ 导入成功！\n正在刷新课表...";
          await Future.delayed(const Duration(milliseconds: 800));
          _closeDialogSafely(dialogContext);
          onSuccess();
        } else {
          statusNotifier.value = "❌ 导入失败\n课表解析错误或文件已损坏";
          await Future.delayed(const Duration(seconds: 2));
          _closeDialogSafely(dialogContext);
        }
      }
    } catch (e) {
      debugPrint("处理外部共享文件崩溃: $e");
      statusNotifier.value = "❌ 发生异常\n读取文件失败或格式崩溃";
      await Future.delayed(const Duration(seconds: 2));
      _closeDialogSafely(dialogContext);
    } finally {
      ReceiveSharingIntent.instance.reset();
      _isProcessing = false;
    }
  }

  static void _closeDialogSafely(BuildContext? dialogContext) {
    if (dialogContext != null && dialogContext.mounted) {
      Navigator.pop(dialogContext);
    }
  }

  static Future<String> _safeReadFile(File file) async {
    try {
      return await file.readAsString();
    } catch (e) {
      List<int> bytes = await file.readAsBytes();
      return utf8.decode(bytes, allowMalformed: true);
    }
  }

  static void dispose() {
    _intentDataStreamSubscription?.cancel();
  }
}
