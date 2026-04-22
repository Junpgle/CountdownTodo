import 'package:flutter/material.dart';
import '../models.dart';
import 'package:intl/intl.dart';
import 'dart:ui';

class StickyAnnouncementBanner extends StatefulWidget {
  final TeamAnnouncement announcement;
  final VoidCallback onAcknowledge;

  const StickyAnnouncementBanner({
    super.key,
    required this.announcement,
    required this.onAcknowledge,
  });

  @override
  State<StickyAnnouncementBanner> createState() => _StickyAnnouncementBannerState();
}

class _StickyAnnouncementBannerState extends State<StickyAnnouncementBanner> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    // 优先级色彩方案
    final accentColor = widget.announcement.isPriority ? Colors.orange[400]! : Colors.blue[400]!;
    final bgColor = widget.announcement.isPriority 
        ? (isDark ? Colors.orange[900]!.withOpacity(0.15) : Colors.orange[50]!.withOpacity(0.7))
        : (isDark ? Colors.blueGrey[900]!.withOpacity(0.15) : Colors.blue[50]!.withOpacity(0.7));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: accentColor.withOpacity(0.3),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: accentColor.withOpacity(0.1),
                  blurRadius: 20,
                  spreadRadius: -5,
                ),
              ],
            ),
            child: Stack(
              children: [
                // 背景装饰气泡
                Positioned(
                  right: -20,
                  top: -20,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accentColor.withOpacity(0.05),
                    ),
                  ),
                ),
                
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          ScaleTransition(
                            scale: _pulseAnimation,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: accentColor,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: accentColor.withOpacity(0.4),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  )
                                ],
                              ),
                              child: Icon(
                                widget.announcement.isPriority ? Icons.bolt_rounded : Icons.campaign_rounded,
                                size: 14,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.announcement.isPriority ? "重要通知" : "团队公告",
                                  style: TextStyle(
                                    fontSize: 10,
                                    letterSpacing: 1.2,
                                    fontWeight: FontWeight.w900,
                                    color: accentColor.withOpacity(0.8),
                                  ),
                                ),
                                Text(
                                  widget.announcement.title,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? Colors.white : Colors.black87,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          _buildAcknowledgeButton(accentColor, isDark),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: (isDark ? Colors.black : Colors.white).withOpacity(0.3),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                widget.announcement.content,
                                style: TextStyle(
                                  fontSize: 13,
                                  height: 1.5,
                                  color: isDark ? Colors.white70 : Colors.black87,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 8,
                                backgroundColor: accentColor.withOpacity(0.2),
                                child: Icon(Icons.person, size: 10, color: accentColor),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                widget.announcement.creatorName ?? '管理员',
                                style: TextStyle(fontSize: 11, color: isDark ? Colors.white38 : Colors.black38),
                              ),
                            ],
                          ),
                          Text(
                            DateFormat('MM-dd HH:mm').format(DateTime.fromMillisecondsSinceEpoch(widget.announcement.createdAt)),
                            style: TextStyle(fontSize: 11, color: isDark ? Colors.white38 : Colors.black38),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAcknowledgeButton(Color color, bool isDark) {
    return InkWell(
      onTap: widget.onAcknowledge,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: const Text(
          "知道了",
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
