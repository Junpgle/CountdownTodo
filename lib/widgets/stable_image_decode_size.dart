import 'dart:async';

import 'package:flutter/widgets.dart';

/// Reuses an image's decode size during window resizing, then updates once the
/// viewport settles. Buckets also let nearby sizes reuse the same cache entry.
class StableImageDecodeSize extends StatefulWidget {
  const StableImageDecodeSize({
    super.key,
    required this.builder,
    this.settleDelay = const Duration(milliseconds: 300),
  });

  final Widget Function(BuildContext context, int width, int height) builder;
  final Duration settleDelay;

  @override
  State<StableImageDecodeSize> createState() => _StableImageDecodeSizeState();
}

class _StableImageDecodeSizeState extends State<StableImageDecodeSize> {
  (int, int)? _decodeSize;
  Timer? _resizeTimer;

  static int _dimension(double logicalSize, double pixelRatio) {
    final pixels = (logicalSize * pixelRatio).ceil().clamp(1, 4096);
    return (((pixels + 127) ~/ 128) * 128).clamp(1, 4096).toInt();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final viewport = MediaQuery.sizeOf(context);
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final target = (
      _dimension(viewport.width, pixelRatio),
      _dimension(viewport.height, pixelRatio),
    );
    if (_decodeSize == null) {
      _decodeSize = target;
      return;
    }
    if (target == _decodeSize) {
      _resizeTimer?.cancel();
      _resizeTimer = null;
      return;
    }
    _resizeTimer?.cancel();
    _resizeTimer = Timer(widget.settleDelay, () {
      if (!mounted) return;
      setState(() {
        _decodeSize = target;
        _resizeTimer = null;
      });
    });
  }

  @override
  void dispose() {
    _resizeTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (width, height) = _decodeSize!;
    return widget.builder(context, width, height);
  }
}
