import 'package:flutter/material.dart';
import '../models.dart';
import '../services/course_service.dart';
import 'home_sections.dart';

// 🚀 引入课程详情页所在的路径，如果你的详情页在别的处，请自行修改
import '../screens/course_screens.dart';

class CourseSectionWidget extends StatelessWidget {
  final Map<String, dynamic> dashboardCourseData;
  final bool isLight;

  const CourseSectionWidget({
    super.key,
    required this.dashboardCourseData,
    required this.isLight,
  });

  @override
  Widget build(BuildContext context) {
    // 🚀 安全提取课程列表，防止脏数据引发崩溃
    List<CourseItem> courses = [];
    try {
      if (dashboardCourseData['courses'] != null && dashboardCourseData['courses'] is List) {
        for (var item in dashboardCourseData['courses']) {
          if (item is CourseItem) {
            courses.add(item);
          }
        }
      }
    } catch (e) {
      debugPrint('解析主页课程数据失败: $e');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
            title: dashboardCourseData['title']?.toString() ?? '课程提醒',
            icon: Icons.class_outlined,
            isLight: isLight
        ),

        // 如果今天/明天没有课，就会显示这个 EmptyState
        if (courses.isEmpty)
          EmptyState(text: "近期没有需要上的课", isLight: isLight)
        else
          Card(
            elevation: 0,
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(isLight ? 0.8 : 0.4),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: courses.length,
              itemBuilder: (context, index) {
                final course = courses[index];

                // 1. 处理课程类型/标签的翻译映射
                String? displayType = course.lessonType;
                if (displayType == 'EXPERIMENT') {
                  displayType = '实验';
                } else if (displayType == 'THEORY') {
                  displayType = '理论';
                }

                return ListTile(
                  leading: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min, // 限制高度防溢出
                    children: [
                      Text(course.formattedStartTime, style: TextStyle(fontWeight: FontWeight.bold, color: isLight ? Colors.black87 : null)),
                      Text(course.formattedEndTime, style: TextStyle(fontSize: 10, color: isLight ? Colors.black54 : Colors.grey)),
                    ],
                  ),
                  title: Row(
                    children: [
                      // 2. 课程名称防溢出
                      Flexible(
                        child: Text(
                          course.courseName,
                          style: TextStyle(fontWeight: FontWeight.w600, color: isLight ? Colors.black87 : null),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // 3. 动态渲染课程类型标签
                      if (displayType != null && displayType.trim().isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(left: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            displayType.trim(),
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.onPrimaryContainer
                            ),
                          ),
                        ),
                    ],
                  ),
                  // 4. 教师与地点防溢出
                  subtitle: Text(
                    '${course.roomName} | ${course.teacherName}',
                    style: TextStyle(fontSize: 12, color: isLight ? Colors.black54 : null),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Icon(Icons.chevron_right, size: 20, color: isLight ? Colors.black54 : null),
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => CourseDetailScreen(course: course)));
                  },
                );
              },
            ),
          ),
      ],
    );
  }
}