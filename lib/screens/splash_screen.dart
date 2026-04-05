import 'dart:io';
import 'package:flutter/material.dart';

class SplashScreen extends StatefulWidget {
  final VoidCallback onComplete;
  final Map<String, dynamic> content;

  const SplashScreen({
    super.key,
    required this.onComplete,
    required this.content,
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    final durationMs = widget.content['durationMs'] as int;
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: durationMs),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );

    _controller.forward();

    Future.delayed(Duration(milliseconds: durationMs), () {
      if (mounted) {
        widget.onComplete();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.content['title'] as String?;
    final subtitle = widget.content['subtitle'] as String?;
    final imagePath = widget.content['imagePath'] as String?;
    final bgColorTop = widget.content['bgColorTop'] as String?;
    final bgColorBottom = widget.content['bgColorBottom'] as String?;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    Color topColor;
    Color bottomColor;

    if (bgColorTop != null && bgColorBottom != null) {
      topColor = _parseColor(bgColorTop);
      bottomColor = _parseColor(bgColorBottom);
    } else {
      topColor = isDark ? const Color(0xFF1A1A2E) : const Color(0xFF4A90D9);
      bottomColor = isDark ? const Color(0xFF16213E) : const Color(0xFF357ABD);
    }

    return Scaffold(
      body: Stack(
        children: [
          Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [topColor, bottomColor],
              ),
            ),
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (imagePath != null && File(imagePath).existsSync())
                    ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Image.file(
                        File(imagePath),
                        width: 120,
                        height: 120,
                        fit: BoxFit.cover,
                      ),
                    )
                  else
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: const Icon(
                        Icons.image,
                        size: 60,
                        color: Colors.white70,
                      ),
                    ),
                  const SizedBox(height: 32),
                  if (title != null && title.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  if (subtitle != null && subtitle.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.8),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    'CountDownTodo',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 48,
            right: 16,
            child: SafeArea(
              child: TextButton(
                onPressed: _skip,
                child: Text(
                  '跳过',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white.withOpacity(0.8),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _skip() {
    _controller.stop();
    widget.onComplete();
  }

  Color _parseColor(String hex) {
    hex = hex.replaceAll('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    return Color(int.parse(hex, radix: 16));
  }
}
