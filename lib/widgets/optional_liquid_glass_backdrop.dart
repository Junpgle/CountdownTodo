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
  final ValueNotifier<ImageProvider<Object>?> _activeProviderNotifier =
      ValueNotifier<ImageProvider<Object>?>(null);

  ValueListenable<PreblurredWallpaperSnapshot?> get snapshotListenable =>
      _snapshotNotifier;

  ValueListenable<ImageProvider<Object>?> get activeProviderListenable =>
      _activeProviderNotifier;

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
    _activeProviderNotifier.value = provider;
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
    _activeProviderNotifier.value = null;
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
    _activeProviderNotifier.dispose();
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
    // ReorderableListView) also repaint their own 1-quad backdrop layer when
    // scrolled.
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
  int _debugPaintCount = 0;

  @override
  void paint(PaintingContext context, Offset offset) {
    final snapshot = _snapshotListenable.value;
    if (snapshot == null || size.isEmpty) return;

    final ancestor = _viewportKey?.currentContext?.findRenderObject();
    final ancestorBox = ancestor is RenderBox && ancestor.attached
        ? ancestor
        : null;
    final viewportSize = ancestorBox != null && ancestorBox.hasSize
        ? ancestorBox.size
        : snapshot.viewportSize;
    if (viewportSize.width <= 0 || viewportSize.height <= 0) return;

    _debugPaintCount++;
    final globalOrigin = localToGlobal(Offset.zero, ancestor: ancestorBox);
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

@visibleForTesting
int debugPreblurredWallpaperPaintCount(RenderObject renderObject) =>
    renderObject is _RenderPreblurredWallpaperFill
    ? renderObject._debugPaintCount
    : 0;

/// Renders the top wallpaper fade strip via a once-baked premultiplied top-cap
/// [ui.Image] so 120 Hz scroll frames pay only a single `drawImageRect` without
/// per-frame `ShaderMask` `saveLayer` passes or coordinate-space shader bugs.
class WallpaperTopFadeCap extends StatefulWidget {
  const WallpaperTopFadeCap({
    super.key,
    required this.imageProvider,
    required this.height,
    required this.dimFactor,
    required this.fallbackBuilder,
  });

  final ImageProvider<Object> imageProvider;
  final double height;
  final double dimFactor;
  final WidgetBuilder fallbackBuilder;

  @override
  State<WallpaperTopFadeCap> createState() => _WallpaperTopFadeCapState();
}

class _WallpaperTopFadeCapState extends State<WallpaperTopFadeCap> {
  ImageStream? _imageStream;
  ImageStreamListener? _imageStreamListener;
  ui.Image? _sourceImage;
  ImageConfiguration? _lastImageConfiguration;
  ui.Image? _bakedImage;
  Size _bakedViewportSize = Size.zero;
  double _bakedDevicePixelRatio = 0.0;
  int _bakedTargetHeightPx = 0;
  double _bakedDimFactor = -1.0;
  int _bakeGeneration = 0;
  bool _disposed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveImage();
    _scheduleBakeIfNeeded();
  }

  @override
  void didUpdateWidget(covariant WallpaperTopFadeCap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageProvider != widget.imageProvider) {
      _resolveImage();
    }
    if (oldWidget.height != widget.height ||
        oldWidget.dimFactor != widget.dimFactor ||
        oldWidget.imageProvider != widget.imageProvider) {
      _scheduleBakeIfNeeded();
    }
  }

  void _resolveImage() {
    final config = createLocalImageConfiguration(context);
    if (_imageStream != null &&
        _lastImageConfiguration == config &&
        _imageStreamListener != null) {
      return;
    }
    _lastImageConfiguration = config;
    final nextStream = widget.imageProvider.resolve(config);
    if (_imageStream?.key == nextStream.key && _imageStreamListener != null) {
      return;
    }
    _detachStream();
    _imageStream = nextStream;
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (ImageInfo info, bool synchronousCall) {
        if (!mounted || _disposed) {
          info.dispose();
          return;
        }
        final nextSource = info.image.clone();
        info.dispose();
        final previous = _sourceImage;
        _sourceImage = nextSource;
        _disposeImageAfterFrame(previous);
        _invalidateBakedKey();
        _scheduleBakeIfNeeded();
      },
      onError: (Object _, StackTrace? _) {
        if (!mounted || _disposed) return;
        final previousSource = _sourceImage;
        final previousBaked = _bakedImage;
        _sourceImage = null;
        _bakedImage = null;
        _invalidateBakedKey();
        _disposeImageAfterFrame(previousSource);
        _disposeImageAfterFrame(previousBaked);
        setState(() {});
      },
    );
    _imageStreamListener = listener;
    nextStream.addListener(listener);
  }

  void _invalidateBakedKey() {
    _bakedViewportSize = Size.zero;
    _bakedDevicePixelRatio = 0.0;
    _bakedTargetHeightPx = 0;
    _bakedDimFactor = -1.0;
  }

  void _scheduleBakeIfNeeded() {
    if (!mounted || _disposed) return;
    final src = _sourceImage;
    if (src == null) return;
    final viewportSize = MediaQuery.sizeOf(context);
    final rawDpr = MediaQuery.devicePixelRatioOf(context);
    final dpr = rawDpr > 0 ? rawDpr : 1.0;
    if (viewportSize.width <= 0 ||
        viewportSize.height <= 0 ||
        widget.height <= 0) {
      return;
    }
    final targetHeightPx = (widget.height * dpr).round().clamp(1, 2048);
    if (_bakedImage != null &&
        _bakedViewportSize == viewportSize &&
        (_bakedDevicePixelRatio - dpr).abs() <= 1e-3 &&
        _bakedTargetHeightPx == targetHeightPx &&
        (_bakedDimFactor - widget.dimFactor).abs() <= 1e-4) {
      return;
    }
    _bakedViewportSize = viewportSize;
    _bakedDevicePixelRatio = dpr;
    _bakedTargetHeightPx = targetHeightPx;
    _bakedDimFactor = widget.dimFactor;
    final generation = ++_bakeGeneration;
    unawaited(
      _bakeCapImage(
        src: src,
        viewportSize: viewportSize,
        dpr: dpr,
        targetHeightPx: targetHeightPx,
        dimFactor: widget.dimFactor,
        generation: generation,
      ),
    );
  }

  Future<void> _bakeCapImage({
    required ui.Image src,
    required Size viewportSize,
    required double dpr,
    required int targetHeightPx,
    required double dimFactor,
    required int generation,
  }) async {
    final targetW = (viewportSize.width * dpr).round().clamp(1, 4096);
    final targetH = targetHeightPx;
    final targetSize = Size(targetW.toDouble(), targetH.toDouble());
    final screenPhysical = Size(
      viewportSize.width * dpr,
      viewportSize.height * dpr,
    );
    final srcSize = Size(src.width.toDouble(), src.height.toDouble());
    if (srcSize.isEmpty || screenPhysical.isEmpty) return;

    final fitted = applyBoxFit(BoxFit.cover, srcSize, screenPhysical);
    final srcRect = Alignment.center.inscribe(
      fitted.source,
      Offset.zero & srcSize,
    );
    final fullDstRect = Alignment.center.inscribe(
      fitted.destination,
      Offset.zero & screenPhysical,
    );

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.clipRect(Offset.zero & targetSize);

    // Match HomeDashboard's wallpaper dim overlay (`Color(0x66000000)` srcOver).
    final dimAlpha = ((1.0 - dimFactor).clamp(0.0, 1.0) * 255).round();
    final imagePaint = Paint()..filterQuality = FilterQuality.medium;
    if (dimAlpha > 0) {
      imagePaint.colorFilter = ColorFilter.mode(
        Color.fromARGB(dimAlpha, 0, 0, 0),
        BlendMode.srcOver,
      );
    }
    canvas.drawImageRect(src, srcRect, fullDstRect, imagePaint);

    // Apply the exact vertical alpha fade [1.0, 1.0, 0x24/255, 0.0] once into
    // the cached strip so frame-by-frame draws need zero ShaderMask saveLayer.
    canvas.drawRect(
      Offset.zero & targetSize,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [0.0, 0.18, 0.78, 1.0],
          colors: [
            Colors.white,
            Colors.white,
            Color(0x24FFFFFF),
            Colors.transparent,
          ],
        ).createShader(Offset.zero & targetSize),
    );

    final picture = recorder.endRecording();
    final ui.Image baked;
    try {
      baked = await picture.toImage(targetW, targetH);
    } finally {
      picture.dispose();
    }

    if (_disposed || !mounted || generation != _bakeGeneration) {
      baked.dispose();
      return;
    }

    final previous = _bakedImage;
    setState(() {
      _bakedImage = baked;
    });
    _disposeImageAfterFrame(previous);
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

  @override
  void dispose() {
    _disposed = true;
    _bakeGeneration++;
    _detachStream();
    _sourceImage?.dispose();
    _sourceImage = null;
    _bakedImage?.dispose();
    _bakedImage = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baked = _bakedImage;
    if (baked == null) {
      return widget.fallbackBuilder(context);
    }
    return SizedBox(
      width: double.infinity,
      height: widget.height,
      child: _WallpaperTopFadeRenderWidget(image: baked),
    );
  }
}

class _WallpaperTopFadeRenderWidget extends LeafRenderObjectWidget {
  const _WallpaperTopFadeRenderWidget({required this.image});

  final ui.Image image;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderWallpaperTopFadeCap(image);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderWallpaperTopFadeCap renderObject,
  ) {
    renderObject.image = image;
  }
}

class _RenderWallpaperTopFadeCap extends RenderBox {
  _RenderWallpaperTopFadeCap(this._image);

  static final Paint _imagePaint = Paint()
    ..filterQuality = FilterQuality.medium;

  ui.Image _image;
  bool _debugDidPaint = false;

  set image(ui.Image value) {
    if (identical(_image, value)) return;
    _image = value;
    markNeedsPaint();
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (size.isEmpty) return;
    final srcRect = Rect.fromLTWH(
      0,
      0,
      _image.width.toDouble(),
      _image.height.toDouble(),
    );
    if (srcRect.isEmpty) return;
    _debugDidPaint = true;
    context.canvas.drawImageRect(_image, srcRect, offset & size, _imagePaint);
  }
}

@visibleForTesting
bool debugWallpaperTopFadeCapDidPaintBakedImage(RenderObject renderObject) =>
    renderObject is _RenderWallpaperTopFadeCap && renderObject._debugDidPaint;
