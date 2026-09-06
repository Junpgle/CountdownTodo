import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../models.dart';
import '../../services/browser_file_service.dart';
import '../../services/course_service.dart';
import '../../utils/app_dialogs.dart';
import '../parsers/hfut_parser.dart';
import '../parsers/xmu_parser.dart';
import '../parsers/xujc_parser.dart';
import '../parsers/xidian_parser.dart';
import '../parsers/zfsoft_parser.dart';
import '../widgets/zf_time_config_dialog.dart';
import '../widgets/course_time_repair_dialog.dart';
import '../widgets/course_webview_screen.dart';
import '../../utils/page_transitions.dart';
import '../../utils/text_file_reader.dart';
import '../../storage_service.dart';
import '../course_schedule_semantics.dart';
import '../course_import_preflight.dart';

/// 导入模式
enum ImportMode {
  replace, // 替换目标学期课表
  merge, // 按时间段合并并与其他学期共存
}

class CourseImportHandler {
  final BuildContext context;
  final String username;
  final VoidCallback onRescheduleReminders;
  final Function(String) showMessage;

  CourseImportHandler({
    required this.context,
    required this.username,
    required this.onRescheduleReminders,
    required this.showMessage,
  });

  /// 让用户选择导入到哪个学期
  /// 返回选中的完整学期信息，解析和保存都必须使用同一个学期。
  Future<SemesterInfo?> _askTargetSemester() =>
      CourseImportPreflight.selectTargetSemester(context);

  /// 检测冲突并让用户选择导入模式
  /// 返回 ImportMode，如果用户取消则返回 null
  Future<ImportMode?> _askImportMode(List<CourseItem> newCourses) async {
    // 检测是否有时间冲突
    final conflicts =
        await CourseService.detectTimeConflicts(username, newCourses);
    if (!context.mounted) return null;

    if (conflicts.isNotEmpty) {
      // 有冲突：提示用户将替换同一学期同一时间段的旧课程
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          final colorScheme = Theme.of(ctx).colorScheme;
          // 去重冲突课程（按课程名+教师分组显示）
          final conflictSummary = <String, int>{};
          for (final c in conflicts) {
            final key = '${c.courseName} (${c.teacherName})';
            conflictSummary[key] = (conflictSummary[key] ?? 0) + 1;
          }

          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: colorScheme.error),
                const SizedBox(width: 10),
                const Text('检测到时间冲突'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '以下 ${conflictSummary.length} 门课程与新课表存在时间冲突，导入后将被替换：',
                    style: TextStyle(
                        fontSize: 14, color: colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  ...conflictSummary.entries.map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Icon(Icons.circle,
                                size: 8, color: colorScheme.error),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${e.key}${e.value > 1 ? " (${e.value}节)" : ""}',
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      )),
                  const SizedBox(height: 12),
                  Text(
                    '不冲突的课程将保留。',
                    style: TextStyle(
                        fontSize: 13, color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('继续导入'),
              ),
            ],
          );
        },
      );

      if (confirmed != true) return null;
      // 有冲突时自动使用按时间段合并，保留其他学期和不冲突课程。
      return ImportMode.merge;
    } else {
      // 无冲突：让用户选择导入方式
      final mode = await showDialog<ImportMode>(
        context: context,
        builder: (ctx) {
          final colorScheme = Theme.of(ctx).colorScheme;
          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Icon(Icons.school_outlined, color: colorScheme.primary),
                const SizedBox(width: 10),
                const Text('选择导入方式'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 替换选项
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.pop(ctx, ImportMode.replace),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(color: colorScheme.outlineVariant),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.swap_horiz_rounded,
                            color: colorScheme.secondary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('替换现有课表',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              Text(
                                '清除该学期旧课表，仅保留新导入的课程',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // 共存选项
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.pop(ctx, ImportMode.merge),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(color: colorScheme.primary),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.merge_rounded, color: colorScheme.primary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('与现有课表共存',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.primary)),
                              const SizedBox(height: 4),
                              Text(
                                '替换该学期的冲突课程，保留其他学期的课表',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
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

      return mode;
    }
  }

  Future<List<CourseItem>?> _repairMissingTimes(
      List<CourseItem> courses) async {
    if (courses.every(CourseScheduleSemantics.hasUsableTime)) {
      return courses;
    }
    if (!context.mounted) return null;
    return CourseTimeRepairDialog.show(context, courses);
  }

  Future<void> smartImportCourse() async {
    // 先完成所有不会产生副作用的导入前置检查，再让用户选择来源和文件。
    final targetSemester = await _askTargetSemester();
    if (targetSemester == null || !context.mounted) return;

    // 1. 先弹出学校选择器
    final String? selectedSchool = await showAppModalBottomSheet<String>(
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

    // 2. 根据学校执行不同的导入方式
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );

    if (result == null) return;
    final pickedFile = result.files.single;
    final filePath = pickedFile.path;
    final pickedBytes = pickedFile.bytes;

    _showLoadingDialog("处理中...");

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
        throw Exception('无法读取文件');
      }

      String sourceName = "";
      List<CourseItem> parsedCourses = [];

      // 第一步：解析课程（不保存）
      switch (selectedSchool) {
        case 'hf':
          sourceName = "合肥工业大学";
          if (!HfutScheduleParser.isValid(content)) {
            throw Exception('文件格式不匹配');
          }
          parsedCourses = HfutScheduleParser.parse(
            content,
            semesterStart: targetSemester.startDate,
          );
          break;
        case 'xd':
          sourceName = "西安电子科技大学";
          parsedCourses = XidianScheduleParser.parseIcs(
            content,
            targetSemester.startDate,
          );
          break;
        case 'zf':
        case 'hl':
          sourceName = selectedSchool == 'zf' ? "正方教务系统" : "河南财经政法大学";
          _closeLoadingDialog();
          if (!context.mounted) return;
          Map<int, Map<String, int>>? userAdjustedTimes =
              await showDialog<Map<int, Map<String, int>>>(
            context: context,
            barrierDismissible: false,
            builder: (context) => const ZfTimeConfigDialog(),
          );
          if (userAdjustedTimes == null) return;
          _showLoadingDialog("正在解析课表...");
          parsedCourses = ZfSoftScheduleParser.parseHtml(
            content,
            targetSemester.startDate,
            customTimes: userAdjustedTimes,
          );
          break;
        case 'xm':
          sourceName = "厦门大学";
          parsedCourses =
              XmuScheduleParser.parseHtml(content, targetSemester.startDate);
          break;
        case 'xj':
          sourceName = "厦门大学嘉庚学院";
          parsedCourses = XujcScheduleParser.parseHtml(
            content,
            targetSemester.startDate,
          );
          break;
        default:
          throw Exception("未知的导入方式");
      }

      parsedCourses = await CourseService.prepareImportedCourses(
        parsedCourses,
        semesterId: targetSemester.id,
        semesterStart: targetSemester.startDate,
      );

      if (parsedCourses.isEmpty) {
        _closeLoadingDialog();
        showMessage('❌ 导入失败\n文件格式不匹配或解析错误');
        return;
      }

      final repairedCourses = await _repairMissingTimes(parsedCourses);
      if (repairedCourses == null) {
        _closeLoadingDialog();
        return;
      }
      parsedCourses = repairedCourses;

      // 第二步：关闭进度弹窗，选择导入模式
      _closeLoadingDialog();

      final mode = await _askImportMode(parsedCourses);
      if (mode == null) {
        _closeLoadingDialog(); // 确保关闭所有 loading
        return; // 用户取消
      }

      // 第三步：根据用户选择保存
      _showLoadingDialog(mode == ImportMode.merge ? "正在合并课表..." : "正在导入课表...");

      if (mode == ImportMode.merge) {
        await CourseService.mergeCoursesForSemester(
          username,
          targetSemester.id,
          parsedCourses,
        );
      } else {
        await CourseService.replaceCoursesForSemester(
          username,
          targetSemester.id,
          parsedCourses,
        );
      }

      _closeLoadingDialog();
      showMessage('✅ $sourceName 导入成功！');
      onRescheduleReminders();
    } catch (e) {
      _closeLoadingDialog();
      showMessage('❌ 导入失败: $e');
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
    // 先校验并确定目标学期，避免打开网页、登录和抓取完成后才发现无法计算课程日期。
    final targetSemester = await _askTargetSemester();
    if (targetSemester == null || !context.mounted) return;

    // 🚀 1. 弹出高校选择器，预设地址
    final String? lastUrl = await StorageService.getLastCourseImportUrl();
    if (!context.mounted) return;

    final Map<String, String> schoolUrls = {
      '合肥工业大学': 'https://one.hfut.edu.cn/',
      '厦门大学': 'https://jw.xmu.edu.cn/gsapp/sys/wdkbapp/*default/index.do',
      '厦大嘉庚': 'http://jw.xujc.com/student/index.php',
      '河南财经政法大学': 'https://xk.huel.edu.cn/jwglxt/xtgl/login_slogin.html',
    };

    final String? selectedUrl = await showAppModalBottomSheet<String>(
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

    if (!context.mounted) return;

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

    if (htmlContent == null || htmlContent.isEmpty || !context.mounted) return;

    _showLoadingDialog("解析网页内容中...");

    try {
      await Future.delayed(const Duration(milliseconds: 400));
      if (!context.mounted) return;

      String sourceName = "网页导入";
      List<CourseItem> parsedCourses = [];
      final normalizedUrl = selectedUrl.toLowerCase();

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

      // 第一步：解析课程（不保存）
      if (jsonCandidate != null && HfutScheduleParser.isValid(jsonCandidate)) {
        sourceName = "合肥工业大学";
        parsedCourses = HfutScheduleParser.parse(jsonCandidate,
            semesterStart: targetSemester.startDate);
      } else if (HfutScheduleParser.isValid(htmlContent)) {
        sourceName = "合肥工业大学";
        parsedCourses = HfutScheduleParser.parse(htmlContent,
            semesterStart: targetSemester.startDate);
      } else if (htmlContent.contains('timetable_con') ||
          htmlContent.contains('id="table1"') ||
          htmlContent.contains('kbgrid_table')) {
        sourceName = "正方教务系统";
        _closeLoadingDialog();
        if (!context.mounted) return;

        Map<int, Map<String, int>>? userAdjustedTimes =
            await showDialog<Map<int, Map<String, int>>>(
          context: context,
          barrierDismissible: false,
          builder: (context) => const ZfTimeConfigDialog(),
        );

        if (userAdjustedTimes == null) return;

        _showLoadingDialog("正在解析课表...");

        parsedCourses = ZfSoftScheduleParser.parseHtml(
          htmlContent,
          targetSemester.startDate,
          customTimes: userAdjustedTimes,
        );
      } else {
        // 只有确认过来源后才选择对应解析器，不再把任意 HTML 猜成厦大课表。
        if (htmlContent.contains('厦门大学嘉庚学院') ||
            normalizedUrl.contains('xujc.com')) {
          sourceName = "厦门大学嘉庚学院";
          parsedCourses = XujcScheduleParser.parseHtml(
              htmlContent, targetSemester.startDate);
        } else if (normalizedUrl.contains('huel.edu.cn')) {
          sourceName = "河南财经政法大学";
          _closeLoadingDialog();
          if (!context.mounted) return;

          final userAdjustedTimes =
              await showDialog<Map<int, Map<String, int>>>(
            context: context,
            barrierDismissible: false,
            builder: (context) => const ZfTimeConfigDialog(),
          );
          if (userAdjustedTimes == null) return;

          _showLoadingDialog("正在解析课表...");
          parsedCourses = ZfSoftScheduleParser.parseHtml(
            htmlContent,
            targetSemester.startDate,
            customTimes: userAdjustedTimes,
          );
        } else if (htmlContent.contains('XMUSTUDENT') ||
            normalizedUrl.contains('xmu.edu.cn')) {
          sourceName = "厦门大学";
          parsedCourses = XmuScheduleParser.parseHtml(
              htmlContent, targetSemester.startDate);
        }
      }

      parsedCourses = await CourseService.prepareImportedCourses(
        parsedCourses,
        semesterId: targetSemester.id,
        semesterStart: targetSemester.startDate,
      );

      final repairedCourses = await _repairMissingTimes(parsedCourses);
      if (repairedCourses == null) {
        _closeLoadingDialog();
        return;
      }
      parsedCourses = repairedCourses;

      if (sourceName == "正方教务系统" || sourceName == "河南财经政法大学") {
        _closeLoadingDialog();
      }

      if (parsedCourses.isEmpty) {
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

        _closeLoadingDialog();
        showMessage('❌ 导入失败\n$detail');
        return;
      }

      // 第二步：关闭进度弹窗，选择导入模式
      _closeLoadingDialog();

      final mode = await _askImportMode(parsedCourses);
      if (mode == null) {
        _closeLoadingDialog(); // 确保关闭所有 loading
        return; // 用户取消
      }

      // 第三步：根据用户选择保存
      _showLoadingDialog(mode == ImportMode.merge ? "正在合并课表..." : "正在导入课表...");

      if (mode == ImportMode.merge) {
        await CourseService.mergeCoursesForSemester(
          username,
          targetSemester.id,
          parsedCourses,
        );
      } else {
        await CourseService.replaceCoursesForSemester(
          username,
          targetSemester.id,
          parsedCourses,
        );
      }

      if (!context.mounted) return;
      _closeLoadingDialog();
      showMessage('✅ $sourceName 导入成功！');
      onRescheduleReminders();
    } catch (e) {
      _closeLoadingDialog();
      showMessage('❌ 导入异常: $e');
    }
  }

  void _showLoadingDialog(String message) {
    if (!context.mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
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
    if (!context.mounted) return;
    if (Navigator.of(context, rootNavigator: true).canPop()) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }
}
