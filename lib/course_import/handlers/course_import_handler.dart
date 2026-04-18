import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/course_service.dart';
import '../parsers/hfut_parser.dart';
import '../widgets/zf_time_config_dialog.dart';
import '../widgets/course_webview_screen.dart';
import '../../utils/page_transitions.dart';
import '../../storage_service.dart';

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
    // 1. 先弹出学校选择器
    final String? selectedSchool = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true, // 允许弹窗超过半屏
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20, horizontal: 24),
                    child: Row(
                      children: [
                        Icon(Icons.school_outlined, color: Colors.blueAccent),
                        SizedBox(width: 12),
                        Text('请选择所属高校/系统', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  _buildSchoolTile(context, 'hf', '合肥工业大学', '支持 聚在工大JSON/教务网页HTML 格式', Icons.engineering_rounded, Colors.orange),
                  _buildSchoolTile(context, 'xm', '厦门大学', '支持 MHTML/HTML 导出文件', Icons.account_balance_rounded, Colors.blue),
                  _buildSchoolTile(context, 'xj', '厦门大学嘉庚学院', '支持教务网页 HTML 格式', Icons.school_rounded, Colors.redAccent),
                  _buildSchoolTile(context, 'xd', '西安电子科技大学', '支持 .ics 日历文件', Icons.wifi_protected_setup_rounded, Colors.indigo),
                  _buildSchoolTile(context, 'zf', '通用正方教务系统', '支持大多数学校的教务导出', Icons.grid_view_rounded, Colors.teal),
                  _buildSchoolTile(context, 'hl', '河南财经政法大学', '支持教务html/mhtml格式', Icons.gavel_rounded, Colors.green),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (selectedSchool == null) return;

    // 2. 根据学校执行不同的导入方式
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.any,
    );

    if (result == null || result.files.single.path == null) return;

    String filePath = result.files.single.path!;
    File file = File(filePath);

    ValueNotifier<String> statusNotifier = ValueNotifier("处理中...");
    BuildContext? dialogContext;
    _showProgressDialog(statusNotifier, (ctx) => dialogContext = ctx);

    try {
      String content;
      try {
        content = await file.readAsString();
      } catch (e) {
        content = utf8.decode(await file.readAsBytes(), allowMalformed: true);
      }

      bool success = false;
      String sourceName = "";

      switch (selectedSchool) {
        case 'hf':
          sourceName = "合肥工业大学";
          success = await CourseService.importScheduleFromJson(content, semesterStart: semesterStart);
          break;
        case 'xd':
          sourceName = "西安电子科技大学";
          if (semesterStart == null) throw Exception("请先设置开学日期");
          success = await CourseService.importXidianScheduleFromIcs(content, semesterStart!);
          break;
        case 'zf':
          sourceName = "正方教务系统";
          if (dialogContext != null && dialogContext!.mounted) Navigator.pop(dialogContext!);
          Map<int, Map<String, int>>? userAdjustedTimes = await showDialog<Map<int, Map<String, int>>>(
            context: context,
            barrierDismissible: false,
            builder: (context) => const ZfTimeConfigDialog(),
          );
          if (userAdjustedTimes == null) return;
          _showLoadingDialog("正在按照校准的时间导入...");
          if (semesterStart == null) { _closeLoadingDialog(); throw Exception("请先设置开学日期"); }
          success = await CourseService.importZfSoftScheduleFromHtml(content, semesterStart!, customTimes: userAdjustedTimes);
          break;
        case 'xm':
        case 'hl':
          sourceName = selectedSchool == 'xm' ? "厦门大学" : "河南财经政法大学";
          if (semesterStart == null) throw Exception("请先设置开学日期");
          success = await CourseService.importXmuScheduleFromHtml(content, semesterStart!);
          break;
        case 'xj':
          sourceName = "厦门大学嘉庚学院";
          if (semesterStart == null) throw Exception("请先设置开学日期");
          success = await CourseService.importXujcScheduleFromHtml(content, semesterStart!);
          break;
        default:
          throw Exception("未知的导入方式");
      }

      if (success) {
        statusNotifier.value = "✅ $sourceName 导入成功！";
        onRescheduleReminders();
        await Future.delayed(const Duration(milliseconds: 1000));
        if (dialogContext != null && dialogContext!.mounted) Navigator.pop(dialogContext!);
      } else {
        statusNotifier.value = "❌ 导入失败\n文件格式不匹配或解析错误";
        await Future.delayed(const Duration(seconds: 2));
        if (dialogContext != null && dialogContext!.mounted) Navigator.pop(dialogContext!);
      }
    } catch (e) {
      statusNotifier.value = "❌ 发生错误\n${e.toString().replaceFirst('Exception: ', '')}";
      await Future.delayed(const Duration(seconds: 2));
      if (dialogContext != null && dialogContext!.mounted) Navigator.pop(dialogContext!);
    }
  }

  Widget _buildSchoolTile(BuildContext context, String id, String name, String sub, IconData icon, Color color) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, color: color),
      ),
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(sub, style: const TextStyle(fontSize: 12)),
      onTap: () => Navigator.pop(context, id),
    );
  }

  Future<void> importFromWebView() async {
    // 🚀 1. 弹出高校选择器，预设地址
    final String? lastUrl = await StorageService.getLastCourseImportUrl();
    
    final Map<String, String> schoolUrls = {
      '合肥工业大学': 'https://one.hfut.edu.cn/',
      '厦门大学': 'https://jw.xmu.edu.cn/gsapp/sys/wdkbapp/*default/index.do',
      '厦大嘉庚': 'http://jw.xujc.com/student/index.php',
      '河南财经政法大学': 'https://xk.huel.edu.cn/jwglxt/xtgl/login_slogin.html',
    };

    final String? selectedUrl = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20, horizontal: 24),
                    child: Row(
                      children: [
                        Icon(Icons.public, color: Colors.blueAccent),
                        SizedBox(width: 12),
                        Text('选择教务入口', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  ...schoolUrls.entries.map((e) => ListTile(
                    leading: const Icon(Icons.language_rounded, color: Colors.blueAccent),
                    title: Text(e.key),
                    subtitle: Text(e.value, style: const TextStyle(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () => Navigator.pop(context, e.value),
                  )).toList(),
                  if (lastUrl != null && !schoolUrls.values.contains(lastUrl))
                    ListTile(
                      leading: const Icon(Icons.history_rounded, color: Colors.orangeAccent),
                      title: const Text('上次抓取的链接'),
                      subtitle: Text(lastUrl, style: const TextStyle(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => Navigator.pop(context, lastUrl),
                    ),
                  ListTile(
                    leading: const Icon(Icons.input_rounded, color: Colors.grey),
                    title: const Text('手动输入'),
                    onTap: () => Navigator.pop(context, 'https://www.bing.com'),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (selectedUrl == null) return;

    final String? htmlContent = await Navigator.push<String>(
      context,
      PageTransitions.slideHorizontal(CourseWebViewScreen(initialUrl: selectedUrl)),
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
        success = await CourseService.importScheduleFromJson(jsonCandidate, semesterStart: semesterStart);
      } else if (HfutScheduleParser.isValid(htmlContent)) {
        sourceName = "合肥工业大学";
        statusNotifier.value = "识别到: $sourceName (教务系统)\n正在智能解析...";
        success = await CourseService.importScheduleFromJson(htmlContent, semesterStart: semesterStart);
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

        // Check if it's likely XMU or XUJC
        if (htmlContent.contains('厦门大学嘉庚学院') || htmlContent.contains('jw.xujc.com')) {
          sourceName = "厦门大学嘉庚学院";
          success = await CourseService.importXujcScheduleFromHtml(htmlContent, semesterStart!);
        } else if (htmlContent.contains('XMUSTUDENT') || htmlContent.toLowerCase().contains('<html')) {
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
