part of '../screen_time_detail_screen.dart';

// ─────────────────────────────────────────────
// LineChartPainter（不变，优化细节）
// ─────────────────────────────────────────────
class LineChartPainter extends CustomPainter {
  final List<int> data;
  final List<String> labels;
  final Color primaryColor;
  final Color textColor;

  static final Paint _dashedPaint = Paint()
    ..strokeWidth = 1
    ..style = PaintingStyle.stroke;
  static final Paint _areaPaint = Paint();
  static final Paint _linePaint = Paint()
    ..strokeWidth = 2.5
    ..style = PaintingStyle.stroke
    ..strokeJoin = StrokeJoin.round
    ..strokeCap = StrokeCap.round;
  static final Paint _dotOuterPaint = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.fill;
  static final Paint _dotInnerPaint = Paint()..style = PaintingStyle.fill;
  static final Path _linePath = Path();
  static final Path _areaPath = Path();

  LineChartPainter({
    required this.data,
    required this.labels,
    required this.primaryColor,
    required this.textColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty || size.width == 0) return;
    const double bottomPadding = 30.0,
        topPadding = 25.0,
        horizontalPadding = 20.0;
    final double chartHeight = size.height - bottomPadding - topPadding;
    final double drawWidth = size.width - horizontalPadding * 2;
    var maxVal = data.first;
    var totalVal = 0;
    for (final value in data) {
      if (value > maxVal) maxVal = value;
      totalVal += value;
    }
    if (maxVal == 0) maxVal = 1;

    final average = totalVal / data.length;
    final double yAvg =
        size.height - bottomPadding - (average / maxVal) * chartHeight;
    if (maxVal > 1) {
      _dashedPaint.color = textColor.withValues(alpha: 0.15);
      _drawDashedLine(
        canvas,
        Offset(horizontalPadding, yAvg),
        Offset(size.width - horizontalPadding, yAvg),
        _dashedPaint,
      );
    }

    final double stepX = drawWidth / (data.length - 1);
    final List<Offset> points = List.generate(
      data.length,
      (i) => Offset(
        horizontalPadding + i * stepX,
        size.height - bottomPadding - (data[i] / maxVal) * chartHeight,
      ),
      growable: false,
    );

    _linePath
      ..reset()
      ..moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      _linePath.lineTo(points[i].dx, points[i].dy);
    }

    _areaPath
      ..reset()
      ..addPath(_linePath, Offset.zero)
      ..lineTo(points.last.dx, size.height - bottomPadding)
      ..lineTo(points.first.dx, size.height - bottomPadding)
      ..close();

    _areaPaint.shader = ui.Gradient.linear(
      const Offset(0, topPadding),
      Offset(0, size.height - bottomPadding),
      [
        primaryColor.withValues(alpha: 0.3),
        primaryColor.withValues(alpha: 0.0),
      ],
    );
    canvas.drawPath(_areaPath, _areaPaint);

    _linePaint.color = primaryColor;
    canvas.drawPath(_linePath, _linePaint);

    _dotInnerPaint.color = primaryColor;
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    try {
      for (int i = 0; i < points.length; i++) {
        canvas.drawCircle(points[i], 4.5, _dotOuterPaint);
        canvas.drawCircle(points[i], 3.0, _dotInnerPaint);
        if (data[i] == maxVal && maxVal > 1) {
          _drawText(
            textPainter,
            canvas,
            _stFormatShortHM(data[i]),
            Offset(points[i].dx, points[i].dy - 16),
            fontSize: 10,
            color: primaryColor,
            bold: true,
          );
        }
        _drawText(
          textPainter,
          canvas,
          labels[i],
          Offset(points[i].dx, size.height - 12),
          fontSize: 11,
          color: textColor,
          bold: i == data.length - 1,
        );
      }
    } finally {
      textPainter.dispose();
    }
  }

  void _drawText(
    TextPainter textPainter,
    Canvas canvas,
    String text,
    Offset center, {
    double fontSize = 12,
    Color color = Colors.black,
    bool bold = false,
  }) {
    textPainter
      ..text = TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
        ),
      )
      ..layout();
    textPainter.paint(
      canvas,
      Offset(
        center.dx - textPainter.width / 2,
        center.dy - textPainter.height / 2,
      ),
    );
  }

  void _drawDashedLine(Canvas canvas, Offset p1, Offset p2, Paint paint) {
    const double dw = 5, ds = 5;
    double dist = (p2 - p1).distance,
        dx = (p2.dx - p1.dx) / dist,
        dy = (p2.dy - p1.dy) / dist;
    double sx = p1.dx, sy = p1.dy;
    while (dist >= 0) {
      double dl = math.min(dw, dist);
      canvas.drawLine(
        Offset(sx, sy),
        Offset(sx + dx * dl, sy + dy * dl),
        paint,
      );
      sx += dx * (dw + ds);
      sy += dy * (dw + ds);
      dist -= (dw + ds);
    }
  }

  @override
  bool shouldRepaint(covariant LineChartPainter oldDelegate) =>
      !identical(oldDelegate.data, data) ||
      !identical(oldDelegate.labels, labels) ||
      oldDelegate.primaryColor != primaryColor ||
      oldDelegate.textColor != textColor;
}

// ─────────────────────────────────────────────
// BarChartPainter（不变，字体权重统一）
// ─────────────────────────────────────────────
class BarChartPainter extends CustomPainter {
  final List<int> data;
  final List<String> labels;
  final Color primaryColor;
  final Color textColor;
  final int selectedIndex;

  static final Paint _barPaint = Paint()..style = PaintingStyle.fill;
  static final Paint _avgDashedPaint = Paint()
    ..color = Colors.orangeAccent.shade400
    ..strokeWidth = 1.5
    ..style = PaintingStyle.stroke;

  BarChartPainter({
    required this.data,
    required this.labels,
    required this.primaryColor,
    required this.textColor,
    required this.selectedIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty || size.width == 0) return;
    const double bottomPadding = 30.0, topPadding = 25.0;
    final double chartHeight = size.height - bottomPadding - topPadding;
    var maxVal = data.first;
    var totalVal = 0;
    for (final value in data) {
      if (value > maxVal) maxVal = value;
      totalVal += value;
    }
    if (maxVal == 0) maxVal = 1;
    final avgVal = totalVal / data.length;
    final double barWidth = (size.width / data.length) * 0.35;
    final double spacing = size.width / data.length;

    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    try {
      for (int i = 0; i < data.length; i++) {
        double xc = i * spacing + spacing / 2;
        double barH = (data[i] / maxVal) * chartHeight;
        _barPaint.color = (i == selectedIndex)
            ? primaryColor
            : primaryColor.withValues(alpha: 0.22);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              xc - barWidth / 2,
              size.height - bottomPadding - barH,
              barWidth,
              barH,
            ),
            const Radius.circular(6),
          ),
          _barPaint,
        );
        if (data[i] == maxVal && maxVal > 1) {
          _drawText(
            textPainter,
            canvas,
            _stFormatShortHM(data[i]),
            Offset(xc, size.height - bottomPadding - barH - 12),
            fontSize: 10,
            color: primaryColor,
            bold: true,
          );
        }
        _drawText(
          textPainter,
          canvas,
          labels[i],
          Offset(xc, size.height - 12),
          fontSize: 11,
          color: textColor,
          bold: i == selectedIndex,
        );
      }
      if (avgVal > 0) {
        double avgY =
            size.height - bottomPadding - (avgVal / maxVal) * chartHeight;
        _drawDashedLine(
          canvas,
          Offset(0, avgY),
          Offset(size.width, avgY),
          _avgDashedPaint,
        );
        _drawText(
          textPainter,
          canvas,
          "平均 ${_stFormatShortHM(avgVal.toInt())}",
          Offset(size.width - 25, avgY - 10),
          fontSize: 10,
          color: Colors.orange.shade800,
          bold: true,
        );
      }
    } finally {
      textPainter.dispose();
    }
  }

  void _drawText(
    TextPainter textPainter,
    Canvas canvas,
    String text,
    Offset center, {
    double fontSize = 12,
    Color color = Colors.black,
    bool bold = false,
  }) {
    textPainter
      ..text = TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
        ),
      )
      ..layout();
    textPainter.paint(
      canvas,
      Offset(
        center.dx - textPainter.width / 2,
        center.dy - textPainter.height / 2,
      ),
    );
  }

  void _drawDashedLine(Canvas canvas, Offset p1, Offset p2, Paint paint) {
    const double dw = 5, ds = 5;
    double dist = (p2 - p1).distance,
        dx = (p2.dx - p1.dx) / dist,
        dy = (p2.dy - p1.dy) / dist;
    double sx = p1.dx, sy = p1.dy;
    while (dist >= 0) {
      double dl = math.min(dw, dist);
      canvas.drawLine(
        Offset(sx, sy),
        Offset(sx + dx * dl, sy + dy * dl),
        paint,
      );
      sx += dx * (dw + ds);
      sy += dy * (dw + ds);
      dist -= (dw + ds);
    }
  }

  @override
  bool shouldRepaint(covariant BarChartPainter oldDelegate) =>
      !identical(oldDelegate.data, data) ||
      !identical(oldDelegate.labels, labels) ||
      oldDelegate.primaryColor != primaryColor ||
      oldDelegate.textColor != textColor ||
      oldDelegate.selectedIndex != selectedIndex;
}
