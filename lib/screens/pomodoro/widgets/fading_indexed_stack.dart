import 'package:flutter/material.dart';

class FadingIndexedStack extends StatefulWidget {
  final int index;
  final List<Widget> children;
  const FadingIndexedStack({super.key, required this.index, required this.children});

  @override
  State<FadingIndexedStack> createState() => _FadingIndexedStackState();
}

class _FadingIndexedStackState extends State<FadingIndexedStack>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;
  int _displayIndex = 0;

  @override
  void initState() {
    super.initState();
    _displayIndex = widget.index;
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 280));
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
    _ctrl.forward();
  }

  @override
  void didUpdateWidget(FadingIndexedStack old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
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
    return FadeTransition(
      opacity: _anim,
      child: IndexedStack(
        index: _displayIndex,
        children: widget.children,
      ),
    );
  }
}
