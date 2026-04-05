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
      duration: const Duration(milliseconds: 200),
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
    final size = MediaQuery.of(context).size;
    final isWide = size.width > 600;
    final imagePath = widget.content['imagePath'] as String?;
    final hasImage = imagePath != null && File(imagePath).existsSync();

    return Scaffold(
      body: SizedBox(
        width: size.width,
        height: size.height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (hasImage)
              if (isWide)
                _buildWideLayout(imagePath!, size)
              else
                _buildNarrowLayout(imagePath!, size)
            else
              FadeTransition(
                opacity: _fadeAnimation,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFF4A90D9), Color(0xFF357ABD)],
                    ),
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
                      shadows: const [
                        Shadow(
                          color: Colors.black54,
                          blurRadius: 6,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNarrowLayout(String imagePath, Size size) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: size.height * 0.6,
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: ClipRect(
              child: Image.file(
                File(imagePath),
                width: size.width,
                height: size.height,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: size.height * 0.4,
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: ClipRect(
              child: Image.asset(
                'assets/splash/default.jpg',
                width: size.width,
                height: size.height,
                fit: BoxFit.cover,
                alignment: Alignment.bottomCenter,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWideLayout(String imagePath, Size size) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          top: 0,
          bottom: 0,
          left: 0,
          width: size.width * 0.6,
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: ClipRect(
              child: Image.file(
                File(imagePath),
                width: size.width,
                height: size.height,
                fit: BoxFit.cover,
                alignment: Alignment.centerLeft,
              ),
            ),
          ),
        ),
        Positioned(
          top: 0,
          bottom: 0,
          right: 0,
          width: size.width * 0.4,
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: ClipRect(
              child: Image.asset(
                'assets/splash/default_pad.jpg',
                width: size.width,
                height: size.height,
                fit: BoxFit.cover,
                alignment: Alignment.centerRight,
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _skip() {
    _controller.stop();
    widget.onComplete();
  }
}
