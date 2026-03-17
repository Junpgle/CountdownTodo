import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../../services/course_service.dart';
import '../dialogs/zf_time_config_dialog.dart';

class CourseImportHandler {
  final BuildContext context;
  final DateTime? semesterStart;
  final VoidCallback onRescheduleReminders;
  final Function(String) showMessage;

  CourseImportHandler({
    required this.context,
    required this.semesterStart,
    required this.onRescheduleReminders,
    required this.showMessage,
  });

  Future<void> smartImportCourse() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.any,
    );

    if (result == null || result.files.single.path == null) return;

    String filePath = result.files.single.path!;
    File file = File(filePath);

    ValueNotifier<String> statusNotifier = ValueNotifier("获取课表文件中...");
    BuildContext? dialogContext;

    _showProgressDialog(statusNotifier, (ctx) => dialogContext = ctx);

    try {
      await Future.delayed(const Duration(milliseconds: 400));
      statusNotifier.value = "正在智能识别文件类型...";

      String content;
      String ext = filePath.split('.').last.toLowerCase();

      try {
        content = await file.readAsString();
      } catch (e) {
        List<int> bytes = await file.readAsBytes();
        content = utf8.decode(bytes, allowMalformed: true);
      }

      await Future.delayed(const Duration(milliseconds: 400));

      bool success = false;
      String sourceName = "";

      if (ext == 'ics' || content.contains('BEGIN:VCALENDAR')) {
        sourceName = "西安电子科技大学";
        statusNotifier.value = "识别到: $sourceName\n正在导入...";

        if (semesterStart == null) {
          statusNotifier.value = "⚠️ 导入中断\n请先在设置中配置【开学日期】";
          await Future.delayed(const Duration(seconds: 2));
          if (dialogContext != null && dialogContext!.mounted) Navigator.pop(dialogContext!);
          return;
        }
        success = await CourseService.importXidianScheduleFromIcs(content, semesterStart!);
      } else if (content.contains('timetable_con') || content.contains('id="table1"')) {
        sourceName = "正方教务系统";
        if (dialogContext != null && dialogContext!.mounted) Navigator.pop(dialogContext!);

        Map<int, Map<String, int>>? userAdjustedTimes = await showDialog<Map<int, Map<String, int>>>(
          context: context,
          barrierDismissible: false,
          builder: (context) => const ZfTimeConfigDialog(),
        );

        if (userAdjustedTimes == null) return;

        _showLoadingDialog("正在按照校准的时间导入课表...");

        if (semesterStart == null) {
          _closeLoadingDialog();
          showMessage('⚠️ 请先设置开学日期');
          return;
        }

        success = await CourseService.importZfSoftScheduleFromHtml(
          content,
          semesterStart!,
          customTimes: userAdjustedTimes,
        );
      } else if (['mhtml', 'html', 'htm'].contains(ext) ||
          content.contains('quoted-printable') ||
          content.toLowerCase().contains('<html')) {
        sourceName = "厦门大学";
        statusNotifier.value = "识别到: $sourceName\n正在深度解码导入...";

        if (semesterStart == null) {
          statusNotifier.value = "⚠️ 导入中断\n请先在设置中配置【开学日期】";
          await Future.delayed(const Duration(seconds: 2));
          if (dialogContext != null && dialogContext!.mounted) Navigator.pop(dialogContext!);
          return;
        }
        success = await CourseService.importXmuScheduleFromHtml(content, semesterStart!);
      } else if (['json', 'txt'].contains(ext) || content.trim().startsWith('[') || content.trim().startsWith('{')) {
        sourceName = "聚在工大";
        statusNotifier.value = "识别到: $sourceName\n正在导入...";
        success = await CourseService.importScheduleFromJson(content);
      } else {
        statusNotifier.value = "❌ 未知的文件格式\n暂不支持解析该文件";
        await Future.delayed(const Duration(seconds: 2));
        if (dialogContext != null && dialogContext!.mounted) Navigator.pop(dialogContext!);
        return;
      }

      if (sourceName == "正方教务系统") _closeLoadingDialog();

      if (success) {
        statusNotifier.value = "✅ $sourceName 导入成功！\n请返回主页查看课表";
        onRescheduleReminders();
        if (sourceName != "正方教务系统") {
          await Future.delayed(const Duration(milliseconds: 1200));
          if (dialogContext != null && dialogContext!.mounted) Navigator.pop(dialogContext!);
        } else {
          showMessage('✅ $sourceName 导入成功！');
        }
      } else {
        statusNotifier.value = "❌ 导入失败\n课表解析错误或文件已损坏";
        if (sourceName != "正方教务系统") {
          await Future.delayed(const Duration(seconds: 2));
          if (dialogContext != null && dialogContext!.mounted) Navigator.pop(dialogContext!);
        } else {
          showMessage('❌ 导入失败');
        }
      }
    } catch (e) {
      debugPrint("处理智能导入时崩溃: $e");
      statusNotifier.value = "❌ 发生异常\n读取文件失败或格式崩溃";
      if (dialogContext != null && dialogContext!.mounted) Navigator.pop(dialogContext!);
    }
  }

  void _showProgressDialog(ValueNotifier<String> statusNotifier, Function(BuildContext) onCtx) {
    showDialog(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (ctx) {
        onCtx(ctx);
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
                    return Text(value, style: const TextStyle(fontSize: 15, height: 1.4));
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showLoadingDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }

  void _closeLoadingDialog() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }
}
