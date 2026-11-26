import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Baked blurred wallpaper snapshot used to paint static-backdrop glass cards
/// without triggering per-card offscreen `Canvas::saveLayer` passes.
@immutable
class PreblurredWallpaperSnapshot {
  const PreblurredWallpaperSnapshot({
    required this.image,
    required this.viewportSize,
    required this.blurSigma,
  });

  final ui.Image image;
  final Size viewportSize;
  final double blurSigma;
}

/// Manages a single downscaled, pre-blurred wallpaper [ui.Image] for the
/// current screen so scrolling glass cards sample the static wallpaper once
/// instead of allocating an offscreen backdrop texture per card per frame.
class PreblurredWallpaperController {
  final ValueNotifier<PreblurredWallpaperSnapshot?> _snapshotNotifier =
      ValueNotifier<PreblurredWallpaperSnapshot?>(null);

  ValueListenable<PreblurredWallpaperSnapshot?> get snapshotListenable =>
      _snapshotNotifier;

  PreblurredWallpaperSnapshot? get snapshot => _snapshotNotifier.value;

  Object? _sourceKey;
  ImageProvider<Object>? _activeProvider;
  Size _lastViewportSize = Size.zero;
  Size? _quantizedViewportSize;
  double? _quantizedSigma;
  ImageStream? _imageStream;
  ImageStreamListener? _imageStreamListener;
  Timer? _pendingBlurUpdateTimer;
  int _bakeGeneration = 0;
  bool _disposed = false;

  void update({
    required ImageProvider<Object>? provider,
    required Object? sourceKey,
    required Size viewportSize,
    required double blurSigma,
    required bool active,
  }) {
    if (_disposed) return;
    if (!active ||
        provider == null ||
        viewportSize.width <= 0 ||
        viewportSize.height <= 0) {
      clear();
      return;
    }

    final quantizedSize = Size(
      ((viewportSize.width / 16).round() * 16.0).clamp(16.0, 8192.0),
      ((viewportSize.height / 16).round() * 16.0).clamp(16.0, 8192.0),
    );
    final quantizedSigma = ((blurSigma.clamp(0.5, 30.0) * 2).round()) / 2.0;

    if (sourceKey == _sourceKey &&
        quantizedSize == _quantizedViewportSize &&
        quantizedSigma == _quantizedSigma &&
        (_snapshotNotifier.value != null || _imageStreamListener != null)) {
      return;
    }

    _pendingBlurUpdateTimer?.cancel();
    _pendingBlurUpdateTimer = null;
    _sourceKey = sourceKey;
    _activeProvider = provider;
    _lastViewportSize = viewportSize;
    _quantizedViewportSize = quantizedSize;
    _quantizedSigma = quantizedSigma;

    final generation = ++_bakeGeneration;
    _detachStream();

    final stream = provider.resolve(ImageConfiguration.empty);
    _imageStream = stream;
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (ImageInfo info, bool _) {
        if (_imageStreamListener == listener) {
          _detachStream();
        }
        unawaited(_bake(info, viewportSize, quantizedSigma, generation));
      },
      onError: (Object _, StackTrace? _) {
        if (_imageStreamListener == listener) {
          _detachStream();
        }
      },
    );
    _imageStreamListener = listener;
    stream.addListener(listener);
  }

  /// Re-bakes the cached wallpaper when the user adjusts the Liquid Glass blur
  /// sigma, debounced when a snapshot already exists so slider drags stay fluid.
  void updateBlurSigma(double blurSigma, {required bool active}) {
    if (_disposed) return;
    if (!active) {
      clear();
      return;
    }
    final provider = _activeProvider;
    final sourceKey = _sourceKey;
    final viewportSize = _lastViewportSize;
    if (provider == null ||
        viewportSize.width <= 0 ||
        viewportSize.height <= 0) {
      return;
    }

    if (_snapshotNotifier.value == null) {
      update(
        provider: provider,
        sourceKey: sourceKey,
        viewportSize: viewportSize,
        blurSigma: blurSigma,
        active: true,
      );
      return;
    }

    _pendingBlurUpdateTimer?.cancel();
    _pendingBlurUpdateTimer = Timer(const Duration(milliseconds: 60), () {
      if (_disposed) return;
      update(
        provider: _activeProvider,
        sourceKey: _sourceKey,
        viewportSize: _lastViewportSize,
        blurSigma: blurSigma,
        active: true,
      );
    });
  }

  Future<void> _bake(
    ImageInfo info,
    Size viewportSize,
    double blurSigma,
    int generation,
  ) async {
    try {
      if (_disposed || generation != _bakeGeneration) return;
      final src = info.image;
      const maxLongEdge = 480.0;
      final longEdge = math.max(viewportSize.width, viewportSize.height);
      final scale = longEdge > maxLongEdge ? maxLongEdge / longEdge : 1.0;
      final targetW = (viewportSize.width * scale).round().clamp(32, 480);
      final targetH = (viewportSize.height * scale).round().clamp(32, 480);
      final targetSize = Size(targetW.toDouble(), targetH.toDouble());
      final effectiveSigma = (blurSigma * scale).clamp(0.5, 25.0);

      final srcSize = Size(src.width.toDouble(), src.height.toDouble());
      final fitted = applyBoxFit(BoxFit.cover, srcSize, targetSize);
      final srcRect = Alignment.center.inscribe(
        fitted.source,
        Offset.zero & srcSize,
      );
      final dstRect = Alignment.center.inscribe(
        fitted.destination,
        Offset.zero & targetSize,
      );

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImageRect(
        src,
        srcRect,
        dstRect,
        Paint()
          ..filterQuality = FilterQuality.medium
          ..imageFilter = ui.ImageFilter.blur(
            sigmaX: effectiveSigma,
            sigmaY: effectiveSigma,
            tileMode: ui.TileMode.clamp,
          ),
      );
      // Match HomeDashboard's wallpaper dim overlay (`0x66000000`).
      canvas.drawRect(
        Offset.zero & targetSize,
        Paint()..color = const Color(0x66000000),
      );

      final picture = recorder.endRecording();
      final ui.Image baked;
      try {
        baked = await picture.toImage(targetW, targetH);
      } finally {
        picture.dispose();
      }

      if (_disposed || generation != _bakeGeneration) {
        baked.dispose();
        return;
      }

      final oldImage = _snapshotNotifier.value?.image;
      _snapshotNotifier.value = PreblurredWallpaperSnapshot(
        image: baked,
        viewportSize: viewportSize,
        blurSigma: blurSigma,
      );
      _disposeImageAfterFrame(oldImage);
    } finally {
      info.dispose();
    }
  }

  void clear() {
    _pendingBlurUpdateTimer?.cancel();
    _pendingBlurUpdateTimer = null;
    _detachStream();
    _bakeGeneration++;
    _sourceKey = null;
    _activeProvider = null;
    _lastViewportSize = Size.zero;
    _quantizedViewportSize = null;
    _quantizedSigma = null;
    final oldImage = _snapshotNotifier.value?.image;
    if (_snapshotNotifier.value != null) {
      _snapshotNotifier.value = null;
    }
    _disposeImageAfterFrame(oldImage);
  }

  void _detachStream() {
    final listener = _imageStreamListener;
    if (listener != null) {
      _imageStream?.removeListener(listener);
    }
    _imageStream = null;
    _imageStreamListener = null;
  }

  static void _disposeImageAfterFrame(ui.Image? image) {
    if (image == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      image.dispose();
    });
  }

  void dispose() {
    _disposed = true;
    clear();
    _snapshotNotifier.dispose();
  }
}

/// Provides static-backdrop optimization context to glass panels inside a
/// page whose background does not move with the scrollable content.
class OptionalLiquidGlassBackdropScope extends InheritedWidget {
  const OptionalLiquidGlassBackdropScope({
    super.key,
    required this.isSolidBackground,
    this.blurredWallpaperListenable,
    this.viewportKey,
    required super.child,
  });

  final bool isSolidBackground;
  final ValueListenable<PreblurredWallpaperSnapshot?>?
  blurredWallpaperListenable;
  final GlobalKey? viewportKey;

  static OptionalLiquidGlassBackdropScope? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<OptionalLiquidGlassBackdropScope>();
  }

  @override
  bool updateShouldNotify(OptionalLiquidGlassBackdropScope oldWidget) =>
      isSolidBackground != oldWidget.isSolidBackground ||
      blurredWallpaperListenable != oldWidget.blurredWallpaperListenable ||
      viewportKey != oldWidget.viewportKey;
}

/// Paints the window-aligned region of a [PreblurredWallpaperSnapshot] inside
/// a clipped glass panel, shifting cleanly on scroll via `markNeedsPaint()`
/// without triggering widget rebuilds or `BackdropFilter` `saveLayer` passes.
class PreblurredWallpaperFill extends StatefulWidget {
  const PreblurredWallpaperFill({
    super.key,
    required this.snapshotListenable,
    this.viewportKey,
  });

  final ValueListenable<PreblurredWallpaperSnapshot?> snapshotListenable;
  final GlobalKey? viewportKey;

  @override
  State<PreblurredWallpaperFill> createState() =>
      _PreblurredWallpaperFillState();
}

class _PreblurredRepaintNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}

class _PreblurredWallpaperFillState extends State<PreblurredWallpaperFill> {
  final _PreblurredRepaintNotifier _repaintTrigger =
      _PreblurredRepaintNotifier();
  final Set<ScrollPosition> _scrollPositions = <ScrollPosition>{};

  @override
  void initState() {
    super.initState();
    widget.snapshotListenable.addListener(_notifyRepaint);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncScrollPositions();
  }

  void _syncScrollPositions() {
    // Register with the nearest ScrollableScope and walk all ancestors so cards
    // inside nested scrollables (e.g. Countdown horizontal list, Todo
    // ReorderableListView) also repaint when the outer dashboard scrolls.
    Scrollable.maybeOf(context);
    final nextPositions = <ScrollPosition>{};
    context.visitAncestorElements((element) {
      if (element is StatefulElement) {
        final state = element.state;
        if (state is ScrollableState && state.mounted) {
          nextPositions.add(state.position);
        }
      }
      return true;
    });

    for (final existing in _scrollPositions.toList(growable: false)) {
      if (!nextPositions.contains(existing)) {
        existing.removeListener(_notifyRepaint);
        _scrollPositions.remove(existing);
      }
    }
    for (final next in nextPositions) {
      if (_scrollPositions.add(next)) {
        next.addListener(_notifyRepaint);
      }
    }
  }

  @override
  void didUpdateWidget(covariant PreblurredWallpaperFill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.snapshotListenable != widget.snapshotListenable) {
      oldWidget.snapshotListenable.removeListener(_notifyRepaint);
      widget.snapshotListenable.addListener(_notifyRepaint);
    }
  }

  void _notifyRepaint() {
    if (!mounted) return;
    _repaintTrigger.notify();
  }

  @override
  void dispose() {
    for (final position in _scrollPositions) {
      position.removeListener(_notifyRepaint);
    }
    _scrollPositions.clear();
    widget.snapshotListenable.removeListener(_notifyRepaint);
    _repaintTrigger.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _PreblurredWallpaperFillRenderWidget(
      snapshotListenable: widget.snapshotListenable,
      viewportKey: widget.viewportKey,
      repaint: _repaintTrigger,
    );
  }
}

class _PreblurredWallpaperFillRenderWidget extends LeafRenderObjectWidget {
  const _PreblurredWallpaperFillRenderWidget({
    required this.snapshotListenable,
    required this.viewportKey,
    required this.repaint,
  });

  final ValueListenable<PreblurredWallpaperSnapshot?> snapshotListenable;
  final GlobalKey? viewportKey;
  final Listenable repaint;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPreblurredWallpaperFill(snapshotListenable, viewportKey, repaint);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderPreblurredWallpaperFill renderObject,
  ) {
    renderObject
      ..snapshotListenable = snapshotListenable
      ..viewportKey = viewportKey
      ..repaint = repaint;
  }
}

class _RenderPreblurredWallpaperFill extends RenderBox {
  _RenderPreblurredWallpaperFill(
    this._snapshotListenable,
    this._viewportKey,
    this._repaint,
  );

  static final Paint _imagePaint = Paint()
    ..filterQuality = FilterQuality.medium;

  ValueListenable<PreblurredWallpaperSnapshot?> _snapshotListenable;
  GlobalKey? _viewportKey;
  Listenable _repaint;

  set snapshotListenable(ValueListenable<PreblurredWallpaperSnapshot?> value) {
    if (_snapshotListenable == value) return;
    _snapshotListenable = value;
    markNeedsPaint();
  }

  set viewportKey(GlobalKey? value) {
    if (_viewportKey == value) return;
    _viewportKey = value;
    markNeedsPaint();
  }

  set repaint(Listenable value) {
    if (identical(_repaint, value)) return;
    if (attached) _repaint.removeListener(markNeedsPaint);
    _repaint = value;
    if (attached) _repaint.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _repaint.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _repaint.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  Rect? _lastPaintedDstRect;

  @override
  void paint(PaintingContext context, Offset offset) {
    final snapshot = _snapshotListenable.value;
    if (snapshot == null || size.isEmpty) return;

    final ancestor = _viewportKey?.currentContext?.findRenderObject();
    final ancestorBox = ancestor is RenderBox && ancestor.attached
        ? ancestor
        : null;
    final globalOrigin = localToGlobal(Offset.zero, ancestor: ancestorBox);
    final viewportSize = ancestorBox != null && ancestorBox.hasSize
        ? ancestorBox.size
        : snapshot.viewportSize;
    if (viewportSize.width <= 0 || viewportSize.height <= 0) return;

    final srcRect = Rect.fromLTWH(
      0,
      0,
      snapshot.image.width.toDouble(),
      snapshot.image.height.toDouble(),
    );
    final dstRect = Rect.fromLTWH(
      offset.dx - globalOrigin.dx,
      offset.dy - globalOrigin.dy,
      viewportSize.width,
      viewportSize.height,
    );
    _lastPaintedDstRect = dstRect;
    context.canvas.drawImageRect(snapshot.image, srcRect, dstRect, _imagePaint);
  }
}

@visibleForTesting
Rect? debugPreblurredWallpaperLastDstRect(RenderObject renderObject) =>
    renderObject is _RenderPreblurredWallpaperFill
    ? renderObject._lastPaintedDstRect
    : null;
