import 'package:flutter/material.dart';

/// 单条版本更新日志条目。
class ChangelogEntry {
  final String versionName;
  final String date;
  final List<String> items;

  const ChangelogEntry({
    required this.versionName,
    required this.date,
    required this.items,
  });

  factory ChangelogEntry.fromJson(Map<String, dynamic> json) => ChangelogEntry(
    versionName: json['version_name']?.toString() ?? '',
    date: json['date']?.toString() ?? '',
    items: (json['items'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .toList(),
  );
}

/// 历史更新日志归档配置。
class ChangelogArchiveConfig {
  final String url;
  final int count;
  final String latestVersion;
  final String oldestVersion;

  const ChangelogArchiveConfig({
    required this.url,
    this.count = 0,
    this.latestVersion = '',
    this.oldestVersion = '',
  });

  bool get isAvailable => url.isNotEmpty && count > 0;

  factory ChangelogArchiveConfig.fromJson(Map<String, dynamic> json) =>
      ChangelogArchiveConfig(
        url: json['url']?.toString() ?? '',
        count: int.tryParse(json['count']?.toString() ?? '0') ?? 0,
        latestVersion: json['latest_version']?.toString() ?? '',
        oldestVersion: json['oldest_version']?.toString() ?? '',
      );
}

/// 远程公告配置。
class Announcement {
  final bool show;
  final String id;
  final String title;
  final String content;
  final String remindMode;
  final List<String> targetVersions; // 空列表=所有版本, 非空=仅指定版本可见

  Announcement.fromJson(Map<String, dynamic> json)
    : show = json['show'] == true,
      id = json['id']?.toString() ?? '',
      title = json['title']?.toString() ?? '',
      content = json['content']?.toString() ?? '',
      remindMode = json['remind_mode']?.toString() ?? 'once',
      targetVersions =
          (json['target_versions'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [];
}

/// 远程默认壁纸配置。
class WallpaperConfig {
  final bool show;
  final String imageUrl;

  WallpaperConfig.fromJson(Map<String, dynamic> json)
    : show = json['show'] == true,
      imageUrl = json['image_url']?.toString() ?? '';
}

/// 多条公告轮播弹窗，使用 Material 3 动态配色。
class AnnouncementCarouselDialog extends StatefulWidget {
  final List<Announcement> announcements;
  final Future<void> Function(String announcementId) onMarkAsRead;

  const AnnouncementCarouselDialog({
    super.key,
    required this.announcements,
    required this.onMarkAsRead,
  });

  @override
  State<AnnouncementCarouselDialog> createState() =>
      _AnnouncementCarouselDialogState();
}

class _AnnouncementCarouselDialogState
    extends State<AnnouncementCarouselDialog> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final announcement = widget.announcements[_currentIndex];
    final isLast = _currentIndex == widget.announcements.length - 1;
    final isFirst = _currentIndex == 0;
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.campaign, color: colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(announcement.title)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(announcement.content),
          if (widget.announcements.length > 1) ...[
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                widget.announcements.length,
                (index) => Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _currentIndex == index
                        ? colorScheme.primary
                        : colorScheme.outlineVariant,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
      actions: [
        if (!isFirst)
          TextButton(
            onPressed: () => setState(() => _currentIndex--),
            child: const Text('上一条'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
        if (!isLast)
          ElevatedButton(
            onPressed: () => setState(() => _currentIndex++),
            child: const Text('下一条'),
          )
        else
          ElevatedButton(
            onPressed: () async {
              for (final ann in widget.announcements) {
                if (ann.remindMode == 'once') {
                  await widget.onMarkAsRead(ann.id);
                }
              }
              if (context.mounted) {
                Navigator.pop(context);
              }
            },
            child: const Text('全部已读'),
          ),
      ],
    );
  }
}
