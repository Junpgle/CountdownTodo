import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../services/course_service.dart';
import '../../../services/hfut_schedule_parser.dart';
import '../dialogs/zf_time_config_dialog.dart';
import '../course_webview_screen.dart';
import '../../../utils/page_transitions.dart';

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
      statusNotifier.value = "❌ 发生异常\n读取文件失败或格式崩溃";
      if (dialogContext != null && dialogContext!.mounted) Navigator.pop(dialogContext!);
    }
  }

  Future<void> importFromWebView() async {
    final String? htmlContent = await Navigator.push<String>(
      context,
      PageTransitions.slideHorizontal(const CourseWebViewScreen()),
    );

    if (htmlContent == null || htmlContent.isEmpty) return;

    ValueNotifier<String> statusNotifier = ValueNotifier("解析网页内容中...");
    BuildContext? dialogContext;

    _showProgressDialog(statusNotifier, (ctx) => dialogContext = ctx);

    try {
      await Future.delayed(const Duration(milliseconds: 400));
      statusNotifier.value = "正在智能提取课程数据...";

      bool success = false;
      String sourceName = "网页导入";

      // 🚀 核心改进：优先尝试作为 JSON 识别（适配合工大等前后端分离系统）
      String? jsonCandidate;
      if (htmlContent.contains('"lessonList"') && htmlContent.contains('"scheduleList"')) {
        try {
          // 尝试寻找最外层的 JSON 大括号
          final startIdx = htmlContent.indexOf('{');
          final endIdx = htmlContent.lastIndexOf('}');
          if (startIdx != -1 && endIdx != -1 && endIdx > startIdx) {
            jsonCandidate = htmlContent.substring(startIdx, endIdx + 1);
          }
        } catch (_) {}
      }

      if (jsonCandidate != null && HfutScheduleParser.isValid(jsonCandidate)) {
        sourceName = "合肥工业大学";
        statusNotifier.value = "识别到: $sourceName (API数据)\n正在读取...";
        success = await CourseService.importScheduleFromJson(jsonCandidate);
      } else if (HfutScheduleParser.isValid(htmlContent)) {
        sourceName = "合肥工业大学";
        statusNotifier.value = "识别到: $sourceName (教务系统)\n正在智能解析...";
        success = await CourseService.importScheduleFromJson(htmlContent);
      } else if (htmlContent.contains('timetable_con') ||
          htmlContent.contains('id="table1"') ||
          htmlContent.contains('kbgrid_table')) {
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
          htmlContent,
          semesterStart!,
          customTimes: userAdjustedTimes,
        );
      } else {
        // Fallback or generic HTML parsing
        if (semesterStart == null) {
          statusNotifier.value = "⚠️ 导入中断\n请先在设置中配置【开学日期】";
          await Future.delayed(const Duration(seconds: 2));
          if (dialogContext != null && dialogContext!.mounted) Navigator.pop(dialogContext!);
          return;
        }

        // Check if it's likely XMU
        if (htmlContent.contains('XMUSTUDENT') || htmlContent.toLowerCase().contains('<html')) {
          sourceName = "智能网页解析";
          success = await CourseService.importXmuScheduleFromHtml(htmlContent, semesterStart!);
        }
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
        // 构建更详细的失败日志输出到 UI
        String detail = "未能识别到有效的课程表格式";
        if (htmlContent.length < 300) {
          detail = "页面内容过少 (${htmlContent.length} 字符)，可能尚未进入课表页面。";
        } else if (htmlContent.contains('login') || htmlContent.contains('用户登录')) {
          detail = "识别到登录页面，请登录后进入[我的课表]再试。";
        } else {
          detail = "识别失败。已将网页源码保存至本地分析。";
          
          try {
            // 🚀 核心改进：请求权限并强行尝试写入公开下载目录
            if (Platform.isAndroid) {
              await Permission.storage.request();
              // 尝试标准的 Android 下载路径
              final downloadDir = Directory('/storage/emulated/0/Download');
              if (await downloadDir.exists()) {
                final filePath = '${downloadDir.path}/hfut_course_debug.html';
                final file = File(filePath);
                await file.writeAsString(htmlContent);
                debugPrint('[Debug] Saved to Public Download: $filePath');
                detail += "\n\n已存至手机[下载](Download)目录\n文件名: hfut_course_debug.html";
                statusNotifier.value = "❌ 导入失败\n$detail";
                await Future.delayed(const Duration(seconds: 5));
                if (dialogContext != null && dialogContext!.mounted) Navigator.pop(dialogContext!);
                return;
              }
            }

            // 兜底方案（如果下载目录不可写）：保存到外部私有目录
            Directory? directory = await getExternalStorageDirectory();
            directory ??= await getApplicationDocumentsDirectory();
            final filePath = '${directory.path}/hfut_course_debug.html';
            await File(filePath).writeAsString(htmlContent);
            detail += "\n\n已存至外部存储:\n$filePath";
          } catch (e) {
            debugPrint('[Debug] Failed to save file: $e');
            detail += "\n保存文件失败: $e";
          }
        }
        
        statusNotifier.value = "❌ 导入失败\n$detail";
        if (sourceName != "正方教务系统") {
          await Future.delayed(const Duration(seconds: 5));
          if (dialogContext != null && dialogContext!.mounted) Navigator.pop(dialogContext!);
        } else {
          showMessage('❌ 导入失败');
        }
      }
    } catch (e) {
      statusNotifier.value = "❌ 发生异常\n解析网页失败";
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
