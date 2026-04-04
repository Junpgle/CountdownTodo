import 'package:flutter/material.dart';

class FadingIndexedStack extends StatefulWidget {
  final int index;
  final List<Widget> children;
  final Duration duration;
  final Curve curve;

  const FadingIndexedStack({
    super.key,
    required this.index,
    required this.children,
    this.duration = const Duration(milliseconds: 280),
    this.curve = Curves.easeInOut,
  });

  @override
  State<FadingIndexedStack> createState() => _FadingIndexedStackState();
}

class _FadingIndexedStackState extends State<FadingIndexedStack>
    with TickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;
  int _displayIndex = 0;
  int _prevIndex = 0;

  @override
  void initState() {
    super.initState();
    _displayIndex = widget.index;
    _prevIndex = widget.index;
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    _fadeAnim = CurvedAnimation(parent: _ctrl, curve: widget.curve);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0.15, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: widget.curve));
    _ctrl.forward();
  }

  @override
  void didUpdateWidget(FadingIndexedStack old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
      _prevIndex = _displayIndex;
      _ctrl.reverse().then((_) {
        if (mounted) {
          setState(() => _displayIndex = widget.index);
          _ctrl.forward();
        }
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        return Stack(
          children: [
            if (_ctrl.status == AnimationStatus.reverse ||
                _ctrl.status == AnimationStatus.dismissed)
              IndexedStack(
                index: _prevIndex,
                children: widget.children,
              ),
            FadeTransition(
              opacity: _fadeAnim,
              child: SlideTransition(
                position: _slideAnim,
                child: IndexedStack(
                  index: _displayIndex,
                  children: widget.children,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
