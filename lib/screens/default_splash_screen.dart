import 'package:flutter/material.dart';

class DefaultSplashScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const DefaultSplashScreen({super.key, required this.onComplete});

  @override
  State<DefaultSplashScreen> createState() => _DefaultSplashScreenState();
}

class _DefaultSplashScreenState extends State<DefaultSplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );

    _controller.forward();

    Future.delayed(const Duration(milliseconds: 300), () {
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
    final assetName =
        isWide ? 'assets/splash/default_pad.jpg' : 'assets/splash/default.jpg';

    return Scaffold(
      body: SizedBox(
        width: size.width,
        height: size.height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            FadeTransition(
              opacity: _fadeAnimation,
              child: Image.asset(
                assetName,
                width: size.width,
                height: size.height,
                fit: BoxFit.cover,
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

  void _skip() {
    _controller.stop();
    widget.onComplete();
  }
}
