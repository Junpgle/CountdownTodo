import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../services/browser_file_service.dart';
import '../../services/course_service.dart';
import '../parsers/hfut_parser.dart';
import '../widgets/zf_time_config_dialog.dart';
import '../widgets/course_webview_screen.dart';
import '../../utils/page_transitions.dart';
import '../../utils/text_file_reader.dart';
import '../../storage_service.dart';

class CourseImportHandler {
  final BuildContext context;
  final String username;
  DateTime? semesterStart;
  final VoidCallback onRescheduleReminders;
  final Function(String) showMessage;
  final Function(DateTime)? onSemesterStartChanged;

  CourseImportHandler({
    required this.context,
    required this.username,
    required this.semesterStart,
    required this.onRescheduleReminders,
    required this.showMessage,
    this.onSemesterStartChanged,
  });

  Future<bool> _ensureSemesterStartSet() async {
    if (semesterStart != null) return true;

    final DateTime? picked = await showDialog<DateTime>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.school_outlined, color: Colors.orange),
              SizedBox(width: 10),
              Text('请先设置开学日期'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '导入课表需要知道开学日期，才能计算每节课的具体日期。',
                style: TextStyle(fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 16),
              const Text(
                '请选择本学期的第一天（周一）：',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_month),
                  label: const Text('选择开学日期'),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                      helpText: '选择开学日期',
                    );
                    if (picked != null && ctx.mounted) {
                      Navigator.pop(ctx, picked);
                    }
                  },
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
          ],
        );
      },
    );

    if (picked == null) return false;

    semesterStart = picked;
    StorageService.saveAppSetting(
      StorageService.KEY_SEMESTER_START,
      picked.toIso8601String(),
    );
    onSemesterStartChanged?.call(picked);
    return true;
  }

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
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2))),
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 20, horizontal: 24),
                    child: Row(
                      children: [
                        Icon(Icons.school_outlined,
                            color: Theme.of(context).colorScheme.secondary),
                        SizedBox(width: 12),
                        Text('请选择所属高校/系统',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  _buildSchoolTile(
                      context,
                      'hf',
                      '合肥工业大学',
                      '支持 聚在工大JSON/教务网页HTML 格式',
                      Icons.engineering_rounded,
                      Colors.orange),
                  _buildSchoolTile(context, 'xm', '厦门大学', '支持 MHTML/HTML 导出文件',
                      Icons.account_balance_rounded, Colors.blue),
                  _buildSchoolTile(context, 'xj', '厦门大学嘉庚学院', '支持教务网页 HTML 格式',
                      Icons.school_rounded, Colors.redAccent),
                  _buildSchoolTile(context, 'xd', '西安电子科技大学', '支持 .ics 日历文件',
                      Icons.wifi_protected_setup_rounded, Colors.indigo),
                  _buildSchoolTile(context, 'zf', '通用正方教务系统', '支持大多数学校的教务导出',
                      Icons.grid_view_rounded, Colors.teal),
                  _buildSchoolTile(context, 'hl', '河南财经政法大学',
                      '支持教务html/mhtml格式', Icons.gavel_rounded, Colors.green),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (selectedSchool == null) return;

    if (!await _ensureSemesterStartSet()) return;

    // 2. 根据学校执行不同的导入方式
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );

    if (result == null) return;
    final pickedFile = result.files.single;
    final filePath = pickedFile.path;
    final pickedBytes = pickedFile.bytes;

    ValueNotifier<String> statusNotifier = ValueNotifier("处理中...");
    BuildContext? dialogContext;
    _showProgressDialog(statusNotifier, (ctx) => dialogContext = ctx);

    try {
      String content;
      if (pickedBytes != null) {
        content = utf8.decode(pickedBytes, allowMalformed: true);
      } else if (filePath != null) {
        try {
          content = await readTextFile(filePath);
        } catch (e) {
          throw Exception('无法读取文件内容: $e');
        }
      } else {
        throw Exception('无法读取所选文件');
      }

      bool success = false;
      String sourceName = "";

      switch (selectedSchool) {
        case 'hf':
          sourceName = "合肥工业大学";
          success = await CourseService.importScheduleFromJson(
              username, content,
              semesterStart: semesterStart);
          break;
        case 'xd':
          sourceName = "西安电子科技大学";
          if (semesterStart == null) throw Exception("请先设置开学日期");
          success = await CourseService.importXidianScheduleFromIcs(
              username, content, semesterStart!);
          break;
        case 'zf':
          sourceName = "正方教务系统";
          if (dialogContext != null && dialogContext!.mounted)
            Navigator.pop(dialogContext!);
          Map<int, Map<String, int>>? userAdjustedTimes =
              await showDialog<Map<int, Map<String, int>>>(
            context: context,
            barrierDismissible: false,
            builder: (context) => const ZfTimeConfigDialog(),
          );
          if (userAdjustedTimes == null) return;
          _showLoadingDialog("正在按照校准的时间导入...");
          if (semesterStart == null) {
            _closeLoadingDialog();
            throw Exception("请先设置开学日期");
          }
          success = await CourseService.importZfSoftScheduleFromHtml(
              username, content, semesterStart!,
              customTimes: userAdjustedTimes);
          break;
        case 'xm':
        case 'hl':
          sourceName = selectedSchool == 'xm' ? "厦门大学" : "河南财经政法大学";
          if (semesterStart == null) throw Exception("请先设置开学日期");
          success = await CourseService.importXmuScheduleFromHtml(
              username, content, semesterStart!);
          break;
        case 'xj':
          sourceName = "厦门大学嘉庚学院";
          if (semesterStart == null) throw Exception("请先设置开学日期");
          success = await CourseService.importXujcScheduleFromHtml(
              username, content, semesterStart!);
          break;
        default:
          throw Exception("未知的导入方式");
      }

      if (success) {
        statusNotifier.value = "✅ $sourceName 导入成功！";
        onRescheduleReminders();
        await Future.delayed(const Duration(milliseconds: 1000));
        if (dialogContext != null && dialogContext!.mounted)
          Navigator.pop(dialogContext!);
      } else {
        statusNotifier.value = "❌ 导入失败\n文件格式不匹配或解析错误";
        await Future.delayed(const Duration(seconds: 2));
        if (dialogContext != null && dialogContext!.mounted)
          Navigator.pop(dialogContext!);
      }
    } catch (e) {
      statusNotifier.value =
          "❌ 发生错误\n${e.toString().replaceFirst('Exception: ', '')}";
      await Future.delayed(const Duration(seconds: 2));
      if (dialogContext != null && dialogContext!.mounted)
        Navigator.pop(dialogContext!);
    }
  }

  Widget _buildSchoolTile(BuildContext context, String id, String name,
      String sub, IconData icon, Color color) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12)),
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
                  Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2))),
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 20, horizontal: 24),
                    child: Row(
                      children: [
                        Icon(Icons.public,
                            color: Theme.of(context).colorScheme.secondary),
                        SizedBox(width: 12),
                        Text('选择教务入口',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  ...schoolUrls.entries.map((e) => ListTile(
                        leading: Icon(Icons.language_rounded,
                            color: Theme.of(context).colorScheme.secondary),
                        title: Text(e.key),
                        subtitle: Text(e.value,
                            style: const TextStyle(fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        onTap: () => Navigator.pop(context, e.value),
                      )),
                  if (lastUrl != null && !schoolUrls.values.contains(lastUrl))
                    ListTile(
                      leading: const Icon(Icons.history_rounded,
                          color: Colors.orangeAccent),
                      title: const Text('上次抓取的链接'),
                      subtitle: Text(lastUrl,
                          style: const TextStyle(fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      onTap: () => Navigator.pop(context, lastUrl),
                    ),
                  ListTile(
                    leading:
                        const Icon(Icons.input_rounded, color: Colors.grey),
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

    if (!await _ensureSemesterStartSet()) return;

    // 修复电脑端返回时因为复杂动画导致的 WebView 进程卡死问题
    final bool isDesktop =
        Theme.of(context).platform == TargetPlatform.windows ||
            Theme.of(context).platform == TargetPlatform.macOS ||
            Theme.of(context).platform == TargetPlatform.linux;

    final Route<String> route = isDesktop
        ? PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) =>
                CourseWebViewScreen(initialUrl: selectedUrl),
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
          )
        : PageTransitions.slideHorizontal(
            CourseWebViewScreen(initialUrl: selectedUrl));

    final String? htmlContent = await Navigator.push<String>(
      context,
      route,
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
      if (htmlContent.contains('"lessonList"') &&
          htmlContent.contains('"scheduleList"')) {
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
        success = await CourseService.importScheduleFromJson(
            username, jsonCandidate,
            semesterStart: semesterStart);
      } else if (HfutScheduleParser.isValid(htmlContent)) {
        sourceName = "合肥工业大学";
        statusNotifier.value = "识别到: $sourceName (教务系统)\n正在智能解析...";
        success = await CourseService.importScheduleFromJson(
            username, htmlContent,
            semesterStart: semesterStart);
      } else if (htmlContent.contains('timetable_con') ||
          htmlContent.contains('id="table1"') ||
          htmlContent.contains('kbgrid_table')) {
        sourceName = "正方教务系统";
        if (dialogContext != null && dialogContext!.mounted)
          Navigator.pop(dialogContext!);

        Map<int, Map<String, int>>? userAdjustedTimes =
            await showDialog<Map<int, Map<String, int>>>(
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
          username,
          htmlContent,
          semesterStart!,
          customTimes: userAdjustedTimes,
        );
      } else {
        // Fallback or generic HTML parsing
        if (semesterStart == null) {
          statusNotifier.value = "⚠️ 导入中断\n请先在设置中配置【开学日期】";
          await Future.delayed(const Duration(seconds: 2));
          if (dialogContext != null && dialogContext!.mounted)
            Navigator.pop(dialogContext!);
          return;
        }

        // Check if it's likely XMU or XUJC
        if (htmlContent.contains('厦门大学嘉庚学院') ||
            htmlContent.contains('jw.xujc.com')) {
          sourceName = "厦门大学嘉庚学院";
          success = await CourseService.importXujcScheduleFromHtml(
              username, htmlContent, semesterStart!);
        } else if (htmlContent.contains('XMUSTUDENT') ||
            htmlContent.toLowerCase().contains('<html')) {
          sourceName = "智能网页解析";
          success = await CourseService.importXmuScheduleFromHtml(
              username, htmlContent, semesterStart!);
        }
      }

      if (sourceName == "正方教务系统") _closeLoadingDialog();

      if (success) {
        statusNotifier.value = "✅ $sourceName 导入成功！\n请返回主页查看课表";
        onRescheduleReminders();
        if (sourceName != "正方教务系统") {
          await Future.delayed(const Duration(milliseconds: 1200));
          if (dialogContext != null && dialogContext!.mounted)
            Navigator.pop(dialogContext!);
        } else {
          showMessage('✅ $sourceName 导入成功！');
        }
      } else {
        // 构建更详细的失败日志输出到 UI
        String detail = "未能识别到有效的课程表格式";
        if (htmlContent.length < 300) {
          detail = "页面内容过少 (${htmlContent.length} 字符)，可能尚未进入课表页面。";
        } else if (htmlContent.contains('login') ||
            htmlContent.contains('用户登录')) {
          detail = "识别到登录页面，请登录后进入[我的课表]再试。";
        } else {
          detail = "识别失败。已将网页源码保存至本地分析。";

          try {
            final savedPath = await BrowserFileService.saveTextFile(
              htmlContent,
              'hfut_course_debug.html',
              mimeType: 'text/html;charset=utf-8',
            );
            detail += "\n\n已保存调试文件:\n$savedPath";
          } catch (e) {
            debugPrint('[Debug] Failed to save file: $e');
            detail += "\n保存文件失败: $e";
          }
        }

        statusNotifier.value = "❌ 导入失败\n$detail";
        if (sourceName != "正方教务系统") {
          await Future.delayed(const Duration(seconds: 5));
          if (dialogContext != null && dialogContext!.mounted)
            Navigator.pop(dialogContext!);
        } else {
          showMessage('❌ 导入失败');
        }
      }
    } catch (e) {
      statusNotifier.value = "❌ 发生异常\n解析网页失败";
      if (dialogContext != null && dialogContext!.mounted)
        Navigator.pop(dialogContext!);
    }
  }

  void _showProgressDialog(
      ValueNotifier<String> statusNotifier, Function(BuildContext) onCtx) {
    showDialog(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (ctx) {
        onCtx(ctx);
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
                    return Text(value,
                        style: const TextStyle(fontSize: 15, height: 1.4));
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
    if (Navigator.of(context, rootNavigator: true).canPop()) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }
}
