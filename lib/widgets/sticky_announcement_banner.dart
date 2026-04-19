import 'package:flutter/material.dart';
import '../models.dart';
import 'package:intl/intl.dart';

class StickyAnnouncementBanner extends StatelessWidget {
  final TeamAnnouncement announcement;
  final VoidCallback onAcknowledge;

  const StickyAnnouncementBanner({
    super.key,
    required this.announcement,
    required this.onAcknowledge,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: announcement.isPriority 
            ? (isDark ? Colors.blueGrey[900] : Colors.blue[50])
            : (isDark ? Colors.grey[850] : Colors.grey[50]),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: announcement.isPriority ? Colors.blue[400]! : Colors.grey[300]!,
          width: announcement.isPriority ? 1.5 : 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 优先级标识条
              Container(
                width: 6,
                color: announcement.isPriority ? Colors.blue[500] : Colors.grey[400],
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            announcement.isPriority ? Icons.campaign : Icons.info_outline,
                            size: 14,
                            color: announcement.isPriority ? Colors.blue[700] : Colors.grey[600],
                          ),
                          const SizedBox(width: 6),
                          Text(
                            announcement.isPriority ? "重要公告" : "团队通知",
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: announcement.isPriority ? Colors.blue[800] : Colors.grey[700],
                            ),
                          ),
                          const Spacer(),
                          Text(
                            DateFormat('MM-dd HH:mm').format(DateTime.fromMillisecondsSinceEpoch(announcement.timestamp)),
                            style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        announcement.content,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: isDark ? Colors.white70 : Colors.black87,
                          fontWeight: announcement.isPriority ? FontWeight.w500 : FontWeight.normal,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: onAcknowledge,
                          style: TextButton.styleFrom(
                            backgroundColor: announcement.isPriority ? Colors.blue[600] : Colors.transparent,
                            foregroundColor: announcement.isPriority ? Colors.white : Colors.blue[700],
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                            minimumSize: const Size(60, 28),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                          child: const Text("我知道了", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
