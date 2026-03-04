import 'package:flutter/material.dart';
import '../models.dart';
import '../screens/course_screens.dart';
import '../services/course_service.dart';
import 'home_sections.dart';

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
    List<CourseItem> courses = (dashboardCourseData['courses'] as List?)?.cast<CourseItem>() ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
            title: dashboardCourseData['title'] ?? '课程提醒',
            icon: Icons.class_outlined,
            isLight: isLight
        ),
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
                return ListTile(
                  leading: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(course.formattedStartTime, style: TextStyle(fontWeight: FontWeight.bold, color: isLight ? Colors.black87 : null)),
                      Text(course.formattedEndTime, style: TextStyle(fontSize: 10, color: isLight ? Colors.black54 : Colors.grey)),
                    ],
                  ),
                  title: Text(course.courseName, style: TextStyle(fontWeight: FontWeight.w600, color: isLight ? Colors.black87 : null)),
                  subtitle: Text('${course.roomName} | ${course.teacherName}', style: TextStyle(fontSize: 12, color: isLight ? Colors.black54 : null)),
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