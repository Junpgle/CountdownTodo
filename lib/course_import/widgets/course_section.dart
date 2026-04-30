import 'package:flutter/material.dart';
import '../../utils/page_transitions.dart';
import 'course_adaptation_screen.dart';

/// 课表设置板块组件
class CourseSection extends StatelessWidget {
  final String? highlightTarget;
  final Map<String, GlobalKey>? itemKeys;
  final VoidCallback onUploadCourses;
  final VoidCallback onSmartImport;
  final VoidCallback? onWebViewImport;
  final VoidCallback onFetchFromCloud;
  final VoidCallback onCalendarAdjustment;
  final String noCourseBehavior;
  final ValueChanged<String?> onNoCourseBehaviorChanged;

  const CourseSection({
    super.key,
    this.highlightTarget,
    this.itemKeys,
    required this.onUploadCourses,
    required this.onSmartImport,
    this.onWebViewImport,
    required this.onFetchFromCloud,
    required this.onCalendarAdjustment,
    required this.noCourseBehavior,
    required this.onNoCourseBehaviorChanged,
  });

  Widget _buildTile({
    required BuildContext context,
    required String targetId,
    required Widget child,
  }) {
    final bool isHighlighted = highlightTarget == targetId;
    return Container(
      key: itemKeys?[targetId],
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: isHighlighted
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 8.0, bottom: 8.0, top: 16.0),
          child: Text('课程设置',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey)),
        ),
        Card(
          elevation: 2,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Column(
            children: [
              // 1. 首页板块相关
              _buildTile(
                context: context,
                targetId: 'no_course_behavior',
                child: ListTile(
                  leading: const Icon(Icons.layers_clear_outlined,
                      color: Colors.blueGrey),
                  title: const Text('无课时板块行为'),
                  trailing: DropdownButton<String>(
                    value: noCourseBehavior,
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(value: 'keep', child: Text('保持位置')),
                      DropdownMenuItem(value: 'bottom', child: Text('排到最后')),
                      DropdownMenuItem(value: 'hide', child: Text('自动隐藏')),
                    ],
                    onChanged: onNoCourseBehaviorChanged,
                  ),
                ),
              ),
              const Divider(height: 1, indent: 56),
              _buildTile(
                context: context,
                targetId: 'course_calendar_adjustment',
                child: ListTile(
                  leading: const Icon(Icons.event_repeat_outlined,
                      color: Colors.deepPurple),
                  title: const Text('放假与调休'),
                  subtitle: const Text('设置停课日期，以及补哪一天的课'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: onCalendarAdjustment,
                ),
              ),
              const Divider(height: 1, indent: 56),

              // 2. 导入
              if (onWebViewImport != null) ...[
                _buildTile(
                  context: context,
                  targetId: 'webview_import',
                  child: ListTile(
                    leading:
                        const Icon(Icons.language_outlined, color: Colors.teal),
                    title: const Text('在线登录并导入 (推荐)'),
                    subtitle: const Text('从应用内浏览器登录教务系统直接抓取'),
                    trailing: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.teal.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text('NEW',
                          style: TextStyle(
                              color: Colors.teal,
                              fontSize: 10,
                              fontWeight: FontWeight.bold)),
                    ),
                    onTap: onWebViewImport,
                  ),
                ),
                const Divider(height: 1, indent: 56),
              ],
              _buildTile(
                context: context,
                targetId: 'smart_import',
                child: ListTile(
                  leading: const Icon(Icons.file_upload_outlined,
                      color: Colors.indigo),
                  title: const Text('智能导入本地课表'),
                  subtitle: const Text('自动嗅探文件格式 (工大/厦大/西电/HUEL)'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: onSmartImport,
                ),
              ),
              const Divider(height: 1, indent: 56),
              _buildTile(
                context: context,
                targetId: 'course_sync',
                child: ListTile(
                  leading: const Icon(Icons.cloud_download_outlined,
                      color: Colors.green),
                  title: const Text('从云端获取课表'),
                  subtitle: const Text('将云端课表同步到本机，覆盖本地数据'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: onFetchFromCloud,
                ),
              ),
              const Divider(height: 1, indent: 56),

              // 3. 上传
              _buildTile(
                context: context,
                targetId: 'course_upload',
                child: ListTile(
                  leading:
                      const Icon(Icons.cloud_upload_outlined, color: Colors.blue),
                  title: const Text('上传课表到云端'),
                  subtitle: const Text('用于与电脑或其他设备同步'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: onUploadCourses,
                ),
              ),
              const Divider(height: 1, indent: 56),

              // 4. 适配申请
              _buildTile(
                context: context,
                targetId: 'course_adapt',
                child: ListTile(
                  leading: const Icon(Icons.auto_awesome, color: Colors.orange),
                  title: const Text('我要请求开发者适配！'),
                  subtitle: const Text('如果没有你的学校，点此申请'),
                  trailing: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text('推荐',
                        style: TextStyle(
                            color: Colors.orange,
                            fontSize: 10,
                            fontWeight: FontWeight.bold)),
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      PageTransitions.slideHorizontal(
                          const CourseAdaptationScreen()),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
