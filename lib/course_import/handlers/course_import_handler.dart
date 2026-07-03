import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../models.dart';
import '../../services/browser_file_service.dart';
import '../../services/course_service.dart';
import '../parsers/hfut_parser.dart';
import '../parsers/xmu_parser.dart';
import '../parsers/xujc_parser.dart';
import '../parsers/xidian_parser.dart';
import '../parsers/zfsoft_parser.dart';
import '../widgets/zf_time_config_dialog.dart';
import '../widgets/course_webview_screen.dart';
import '../../utils/page_transitions.dart';
import '../../utils/text_file_reader.dart';
import '../../storage_service.dart';

/// 导入模式
enum ImportMode {
  replace, // 替换现有课表
  merge, // 与现有课表共存
}

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
    // 先尝试从存储读取最新值（处理构造时未传入的情况）
    if (semesterStart == null) {
      semesterStart = await StorageService.getSemesterStart();
    }
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

  /// 检测冲突并让用户选择导入模式
  /// 返回 ImportMode，如果用户取消则返回 null
  Future<ImportMode?> _askImportMode(List<CourseItem> newCourses) async {
    // 检测是否有时间冲突
    final conflicts =
        await CourseService.detectTimeConflicts(username, newCourses);

    if (conflicts.isNotEmpty) {
      // 有冲突：提示用户将覆盖冲突课程
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
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    color: colorScheme.error),
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
                    '以下 ${conflictSummary.length} 门课程与新课表存在时间冲突，导入后将被覆盖：',
                    style: TextStyle(
                        fontSize: 14, color: colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  ...conflictSummary.entries.map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Icon(Icons.circle, size: 8,
                                color: colorScheme.error),
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
                        fontSize: 13,
                        color: colorScheme.onSurfaceVariant),
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
      // 有冲突时自动使用合并模式（只覆盖冲突的，保留不冲突的）
      return ImportMode.merge;
    } else {
      // 无冲突：让用户选择导入方式
      final mode = await showDialog<ImportMode>(
        context: context,
        builder: (ctx) {
          final colorScheme = Theme.of(ctx).colorScheme;
          return AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Icon(Icons.school_outlined,
                    color: colorScheme.primary),
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
                      border: Border.all(
                          color: colorScheme.outlineVariant),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.swap_horiz_rounded,
                            color: colorScheme.secondary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              const Text('替换现有课表',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              Text(
                                '清除旧课表，仅保留新导入的课程',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: colorScheme
                                        .onSurfaceVariant),
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
                      border: Border.all(
                          color: colorScheme.primary),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.merge_rounded,
                            color: colorScheme.primary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text('与现有课表共存',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.primary)),
                              const SizedBox(height: 4),
                              Text(
                                '新旧课表合并，适用于不同学期的课表',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: colorScheme
                                        .onSurfaceVariant),
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
          parsedCourses = HfutScheduleParser.parse(content,
              semesterStart: semesterStart);
          break;
        case 'xd':
          sourceName = "西安电子科技大学";
          if (semesterStart == null) throw Exception("请先设置开学日期");
          parsedCourses =
              XidianScheduleParser.parseIcs(content, semesterStart!);
          break;
        case 'zf':
          sourceName = "正方教务系统";
          _closeLoadingDialog();
          Map<int, Map<String, int>>? userAdjustedTimes =
              await showDialog<Map<int, Map<String, int>>>(
            context: context,
            barrierDismissible: false,
            builder: (context) => const ZfTimeConfigDialog(),
          );
          if (userAdjustedTimes == null) return;
          _showLoadingDialog("正在解析课表...");
          if (semesterStart == null) {
            _closeLoadingDialog();
            throw Exception("请先设置开学日期");
          }
          parsedCourses = ZfSoftScheduleParser.parseHtml(
            content,
            semesterStart!,
            customTimes: userAdjustedTimes,
          );
          break;
        case 'xm':
        case 'hl':
          sourceName = selectedSchool == 'xm' ? "厦门大学" : "河南财经政法大学";
          if (semesterStart == null) throw Exception("请先设置开学日期");
          parsedCourses =
              XmuScheduleParser.parseHtml(content, semesterStart!);
          break;
        case 'xj':
          sourceName = "厦门大学嘉庚学院";
          if (semesterStart == null) throw Exception("请先设置开学日期");
          parsedCourses =
              XujcScheduleParser.parseHtml(content, semesterStart!);
          break;
        default:
          throw Exception("未知的导入方式");
      }

      if (parsedCourses.isEmpty) {
        _closeLoadingDialog();
        showMessage('❌ 导入失败\n文件格式不匹配或解析错误');
        return;
      }

      // 第二步：关闭进度弹窗，询问导入模式
      _closeLoadingDialog();

      final mode = await _askImportMode(parsedCourses);
      if (mode == null) {
        _closeLoadingDialog(); // 确保关闭所有 loading
        return; // 用户取消
      }

      // 第三步：根据用户选择保存
      _showLoadingDialog(
          mode == ImportMode.merge ? "正在合并课表..." : "正在导入课表...");

      if (mode == ImportMode.merge) {
        await CourseService.mergeCoursesToSql(username, parsedCourses);
      } else {
        await CourseService.saveCourses(username, parsedCourses);
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

    _showLoadingDialog("解析网页内容中...");

    try {
      await Future.delayed(const Duration(milliseconds: 400));

      String sourceName = "网页导入";
      List<CourseItem> parsedCourses = [];

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
            semesterStart: semesterStart);
      } else if (HfutScheduleParser.isValid(htmlContent)) {
        sourceName = "合肥工业大学";
        parsedCourses = HfutScheduleParser.parse(htmlContent,
            semesterStart: semesterStart);
      } else if (htmlContent.contains('timetable_con') ||
          htmlContent.contains('id="table1"') ||
          htmlContent.contains('kbgrid_table')) {
        sourceName = "正方教务系统";
        _closeLoadingDialog();

        Map<int, Map<String, int>>? userAdjustedTimes =
            await showDialog<Map<int, Map<String, int>>>(
          context: context,
          barrierDismissible: false,
          builder: (context) => const ZfTimeConfigDialog(),
        );

        if (userAdjustedTimes == null) return;

        _showLoadingDialog("正在解析课表...");

        if (semesterStart == null) {
          _closeLoadingDialog();
          showMessage('⚠️ 请先设置开学日期');
          return;
        }

        parsedCourses = ZfSoftScheduleParser.parseHtml(
          htmlContent,
          semesterStart!,
          customTimes: userAdjustedTimes,
        );
      } else {
        // Fallback or generic HTML parsing
        if (semesterStart == null) {
          _closeLoadingDialog();
          showMessage('⚠️ 请先设置开学日期');
          return;
        }

        // Check if it's likely XMU or XUJC
        if (htmlContent.contains('厦门大学嘉庚学院') ||
            htmlContent.contains('jw.xujc.com')) {
          sourceName = "厦门大学嘉庚学院";
          parsedCourses =
              XujcScheduleParser.parseHtml(htmlContent, semesterStart!);
        } else if (htmlContent.contains('XMUSTUDENT') ||
            htmlContent.toLowerCase().contains('<html')) {
          sourceName = "智能网页解析";
          parsedCourses =
              XmuScheduleParser.parseHtml(htmlContent, semesterStart!);
        }
      }

      if (sourceName == "正方教务系统") _closeLoadingDialog();

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

      // 第二步：关闭进度弹窗，询问导入模式
      _closeLoadingDialog();

      final mode = await _askImportMode(parsedCourses);
      if (mode == null) {
        _closeLoadingDialog(); // 确保关闭所有 loading
        return; // 用户取消
      }

      // 第三步：根据用户选择保存
      _showLoadingDialog(
          mode == ImportMode.merge ? "正在合并课表..." : "正在导入课表...");

      if (mode == ImportMode.merge) {
        await CourseService.mergeCoursesToSql(username, parsedCourses);
      } else {
        await CourseService.saveCourses(username, parsedCourses);
      }

      _closeLoadingDialog();
      showMessage('✅ $sourceName 导入成功！');
      onRescheduleReminders();
    } catch (e) {
      _closeLoadingDialog();
      showMessage('❌ 导入异常: $e');
    }
  }

  void _showLoadingDialog(String message) {
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
    if (Navigator.of(context, rootNavigator: true).canPop()) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }
}
