import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/calibration/scale.dart';
import '../core/geometry/arc_segment.dart';
import '../core/geometry/intersections.dart';
import '../core/geometry/point2d.dart';
import '../models/detected_element.dart';
import '../models/measurement.dart';

class CanvasOverlay extends StatelessWidget {
  final List<DetectedElement> detectedElements;
  final List<Joint> joints;
  final List<Measurement> measurements;
  final CalibrationScale? calibration;
  final Point2D? pendingPoint;
  final Point2D? pendingSecondPoint;
  final Point2D? snapIndicator;
  final double snapRadius;
  final double pageWidth;
  final double pageHeight;
  final String? selectedMeasurementId;
  final String? hoveredMeasurementId;
  final Point2D? crosshairPosition;
  final Point2D? previewCircleCenter;
  final double? previewCircleRadius;
  final Point2D? previewRectEnd;
  final Point2D? previewLineEnd;
  final ArcSegment? previewArc;
  /// Control point of a Bezier preview curve (Free arc-tool mode).
  final Point2D? previewBezierControl;
  /// Apex point of the Bezier preview (= cursor in Free mode), shown as a
  /// small ring so the user can see exactly what the curve is pinned to.
  final Point2D? previewBezierApex;
  /// When true, draw a dashed line from the crosshair to
  /// [pendingSecondPoint] — used by the circular Arc mode of the arc tool
  /// to indicate that the cursor controls the arc's third point.
  final bool showArcBulgeGuide;

  const CanvasOverlay({
    super.key,
    this.detectedElements = const [],
    this.joints = const [],
    this.measurements = const [],
    this.calibration,
    this.pendingPoint,
    this.pendingSecondPoint,
    this.snapIndicator,
    this.snapRadius = 10.0,
    required this.pageWidth,
    required this.pageHeight,
    this.selectedMeasurementId,
    this.hoveredMeasurementId,
    this.crosshairPosition,
    this.previewCircleCenter,
    this.previewCircleRadius,
    this.previewRectEnd,
    this.previewLineEnd,
    this.previewArc,
    this.previewBezierControl,
    this.previewBezierApex,
    this.showArcBulgeGuide = false,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return CustomPaint(
          painter: _OverlayPainter(
            detectedElements: detectedElements,
            joints: joints,
            measurements: measurements,
            calibration: calibration,
            pendingPoint: pendingPoint,
            pendingSecondPoint: pendingSecondPoint,
            snapIndicator: snapIndicator,
            snapRadius: snapRadius,
            scaleX: constraints.maxWidth / pageWidth,
            scaleY: constraints.maxHeight / pageHeight,
            pageHeight: pageHeight,
            selectedMeasurementId: selectedMeasurementId,
            hoveredMeasurementId: hoveredMeasurementId,
            crosshairPosition: crosshairPosition,
            previewCircleCenter: previewCircleCenter,
            previewCircleRadius: previewCircleRadius,
            previewRectEnd: previewRectEnd,
            previewLineEnd: previewLineEnd,
            previewArc: previewArc,
            previewBezierControl: previewBezierControl,
            previewBezierApex: previewBezierApex,
            showArcBulgeGuide: showArcBulgeGuide,
          ),
          size: Size(constraints.maxWidth, constraints.maxHeight),
        );
      },
    );
  }
}

class _OverlayPainter extends CustomPainter {
  final List<DetectedElement> detectedElements;
  final List<Joint> joints;
  final List<Measurement> measurements;
  final CalibrationScale? calibration;
  final Point2D? pendingPoint;
  final Point2D? pendingSecondPoint;
  final Point2D? snapIndicator;
  final double snapRadius;
  final double scaleX;
  final double scaleY;
  final double pageHeight;
  final String? selectedMeasurementId;
  final String? hoveredMeasurementId;
  final Point2D? crosshairPosition;
  final Point2D? previewCircleCenter;
  final double? previewCircleRadius;
  final Point2D? previewRectEnd;
  final Point2D? previewLineEnd;
  final ArcSegment? previewArc;
  final Point2D? previewBezierControl;
  final Point2D? previewBezierApex;
  final bool showArcBulgeGuide;

  _OverlayPainter({
    required this.detectedElements,
    required this.joints,
    required this.measurements,
    required this.calibration,
    required this.pendingPoint,
    this.pendingSecondPoint,
    required this.snapIndicator,
    required this.snapRadius,
    required this.scaleX,
    required this.scaleY,
    required this.pageHeight,
    this.selectedMeasurementId,
    this.hoveredMeasurementId,
    this.crosshairPosition,
    this.previewCircleCenter,
    this.previewCircleRadius,
    this.previewRectEnd,
    this.previewLineEnd,
    this.previewArc,
    this.previewBezierControl,
    this.previewBezierApex,
    this.showArcBulgeGuide = false,
  });

  /// Convert PDF coordinates to widget-local (screen) coordinates.
  Offset _toLocal(Point2D p) => Offset(p.x * scaleX, (pageHeight - p.y) * scaleY);

  @override
  void paint(Canvas canvas, Size size) {
    _drawDetectedElements(canvas);
    _drawJoints(canvas);
    _drawMeasurementSnapPoints(canvas);
    _drawMeasurements(canvas);
    _drawCircleMeasurements(canvas);
    _drawPreviewCircle(canvas);
    _drawRectMeasurements(canvas);
    _drawPreviewRect(canvas);
    _drawPreviewArc(canvas);
    _drawPreviewBezier(canvas);
    _drawPreviewLine(canvas);
    _drawPendingPoint(canvas);
    // Selected measurement is drawn on top of all other measurements/labels
    // so the user's current focus is never obscured.
    _drawSelectedMeasurement(canvas);
    _drawSnapIndicator(canvas);
    _drawCrosshair(canvas, size);
  }

  void _drawDetectedElements(Canvas canvas) {
    final paint = Paint()
      ..color = Colors.blue.withValues(alpha: 0.4)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    for (final element in detectedElements) {
      switch (element.type) {
        case DetectedElementType.line:
          final seg = element.lineSegment!;
          canvas.drawLine(_toLocal(seg.start), _toLocal(seg.end), paint);
        case DetectedElementType.arc:
          _drawArc(canvas, element.arcSegment!, paint);
      }
    }
  }

  void _drawArc(Canvas canvas, ArcSegment arc, Paint paint) {
    final center = _toLocal(arc.center);
    final rx = arc.radius * scaleX;
    final ry = arc.radius * scaleY;
    final rect = Rect.fromCenter(center: center, width: rx * 2, height: ry * 2);
    canvas.drawArc(rect, -arc.startAngle, -arc.sweepAngle, false, paint);
  }

  /// Draws an arc-type measurement, choosing the correct underlying shape:
  /// a quadratic Bezier when [Measurement.bezierControl] is set, otherwise
  /// a circular arc from [Measurement.arcSegment]. Falls back to a chord
  /// line if neither is present.
  void _drawArcOrBezierMeasurement(
    Canvas canvas,
    Measurement m,
    Paint paint,
  ) {
    if (m.bezierControl != null) {
      final path = Path()
        ..moveTo(_toLocal(m.startPoint).dx, _toLocal(m.startPoint).dy)
        ..quadraticBezierTo(
          _toLocal(m.bezierControl!).dx,
          _toLocal(m.bezierControl!).dy,
          _toLocal(m.endPoint).dx,
          _toLocal(m.endPoint).dy,
        );
      canvas.drawPath(path, paint);
      return;
    }
    if (m.arcSegment != null) {
      _drawArc(canvas, m.arcSegment!, paint);
      return;
    }
    canvas.drawLine(
      _toLocal(m.startPoint),
      _toLocal(m.endPoint),
      paint,
    );
  }

  void _drawJoints(Canvas canvas) {
    final paint = Paint()
      ..color = Colors.green
      ..style = PaintingStyle.fill;

    for (final joint in joints) {
      canvas.drawCircle(_toLocal(joint.point), 4.0, paint);
    }
  }

  void _drawMeasurementSnapPoints(Canvas canvas) {
    final paint = Paint()
      ..color = Colors.redAccent
      ..style = PaintingStyle.fill;

    void dot(Point2D p) => canvas.drawCircle(_toLocal(p), 3.0, paint);

    for (final m in measurements) {
      if (m.autoDetected) continue;
      switch (m.type) {
        case MeasurementType.linear:
          dot(m.startPoint);
          dot(m.endPoint);
        case MeasurementType.circle:
          dot(m.startPoint); // center
        case MeasurementType.rectangle:
          dot(m.startPoint);
          dot(m.endPoint);
          dot(Point2D(m.startPoint.x, m.endPoint.y));
          dot(Point2D(m.endPoint.x, m.startPoint.y));
        case MeasurementType.arc:
          dot(m.startPoint);
          dot(m.endPoint);
      }
    }
  }

  void _drawMeasurements(Canvas canvas) {
    final manualPaint = Paint()
      ..color = Colors.red
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final hoveredPaint = Paint()
      ..color = Colors.cyan
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    for (final m in measurements) {
      // Circle and rectangle have their own draw methods.
      if (m.type == MeasurementType.circle ||
          m.type == MeasurementType.rectangle) {
        continue;
      }

      // The selected measurement is drawn last (on top of everything) by
      // _drawSelectedMeasurement so its label is never covered.
      if (m.id == selectedMeasurementId) continue;

      final isHovered = m.id == hoveredMeasurementId;

      // Auto-detected measurements are invisible unless hovered.
      if (m.autoDetected && !isHovered) continue;

      final paint = isHovered ? hoveredPaint : manualPaint;

      if (m.type == MeasurementType.arc) {
        _drawArcOrBezierMeasurement(canvas, m, paint);
      } else {
        canvas.drawLine(
          _toLocal(m.startPoint),
          _toLocal(m.endPoint),
          paint,
        );
      }

      // Label
      final label = _formatMeasurement(m);
      final mid = m.startPoint.midpointTo(m.endPoint);
      _drawLabel(canvas, _toLocal(mid), label);
    }
  }

  String _formatMeasurement(Measurement m) {
    if (calibration != null) {
      final mm = calibration!.toMm(m.pixelLength);
      if (mm >= 1000) {
        return '${(mm / 1000).toStringAsFixed(2)} m';
      } else if (mm >= 10) {
        return '${mm.toStringAsFixed(1)} mm';
      } else {
        return '${mm.toStringAsFixed(2)} mm';
      }
    }
    return '${m.pixelLength.toStringAsFixed(1)} px';
  }

  void _drawLabel(Canvas canvas, Offset position, String text,
      {bool highlighted = false}) {
    final textColor =
        highlighted ? const Color(0xFF8B3D00) : const Color(0xFF333333);
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: textColor,
          fontSize: 11,
          fontWeight: highlighted ? FontWeight.w700 : FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final padding = const EdgeInsets.symmetric(horizontal: 6, vertical: 3);
    final bgRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: position,
        width: textPainter.width + padding.horizontal,
        height: textPainter.height + padding.vertical,
      ),
      const Radius.circular(4),
    );

    final bgColor = highlighted
        ? Colors.orange.shade100.withValues(alpha: 0.95)
        : Colors.white.withValues(alpha: 0.9);
    final borderColor = highlighted ? Colors.orange.shade700 : Colors.grey.shade400;
    final borderWidth = highlighted ? 1.5 : 0.5;

    canvas.drawRRect(bgRect, Paint()..color = bgColor);
    canvas.drawRRect(
      bgRect,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth,
    );

    textPainter.paint(
      canvas,
      Offset(
        position.dx - textPainter.width / 2,
        position.dy - textPainter.height / 2,
      ),
    );
  }

  void _drawPendingPoint(Canvas canvas) {
    void drawDot(Point2D p) {
      final center = _toLocal(p);
      canvas.drawCircle(
        center,
        7.0,
        Paint()..color = Colors.orange.withValues(alpha: 0.3),
      );
      canvas.drawCircle(
        center,
        4.0,
        Paint()..color = Colors.orange,
      );
    }

    if (pendingPoint != null) drawDot(pendingPoint!);
    if (pendingSecondPoint != null) drawDot(pendingSecondPoint!);
  }

  void _drawSnapIndicator(Canvas canvas) {
    if (snapIndicator == null) return;

    final center = _toLocal(snapIndicator!);
    final scaledRadius = snapRadius * scaleX;
    canvas.drawCircle(
      center,
      scaledRadius,
      Paint()
        ..color = Colors.yellow.withValues(alpha: 0.25)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      center,
      scaledRadius,
      Paint()
        ..color = Colors.yellow.shade700
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );
  }

  void _drawCircleMeasurements(Canvas canvas) {
    final circlePaint = Paint()
      ..color = Colors.red
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final hoveredPaint = Paint()
      ..color = Colors.cyan
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final radiusLinePaint = Paint()
      ..color = Colors.red.withValues(alpha: 0.5)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    for (final m in measurements) {
      if (m.type != MeasurementType.circle) continue;
      if (m.autoDetected) continue;

      // Selected is drawn last by _drawSelectedMeasurement.
      if (m.id == selectedMeasurementId) continue;

      final isHovered = m.id == hoveredMeasurementId;
      final paint = isHovered ? hoveredPaint : circlePaint;

      final center = _toLocal(m.startPoint);
      final radius = m.pixelLength; // pixelLength stores the radius
      final rx = radius * scaleX;
      final ry = radius * scaleY;
      canvas.drawOval(
        Rect.fromCenter(center: center, width: rx * 2, height: ry * 2),
        paint,
      );

      // Radius line from center to the right
      final edgePoint = _toLocal(Point2D(m.startPoint.x + radius, m.startPoint.y));
      canvas.drawLine(center, edgePoint, radiusLinePaint);

      // Center dot
      canvas.drawCircle(center, 3.0, Paint()..color = Colors.red);

      // Radius label at midpoint of the radius line
      final labelPos = Offset(
        (center.dx + edgePoint.dx) / 2,
        (center.dy + edgePoint.dy) / 2 - 12,
      );
      final label = 'R=${_formatMeasurement(m)}';
      _drawLabel(canvas, labelPos, label);
    }
  }

  void _drawPreviewCircle(Canvas canvas) {
    if (previewCircleCenter == null || previewCircleRadius == null) return;
    if (previewCircleRadius! <= 0) return;

    final center = _toLocal(previewCircleCenter!);
    final rx = previewCircleRadius! * scaleX;
    final ry = previewCircleRadius! * scaleY;

    // Dashed-style preview circle
    final previewPaint = Paint()
      ..color = Colors.red.withValues(alpha: 0.5)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    canvas.drawOval(
      Rect.fromCenter(center: center, width: rx * 2, height: ry * 2),
      previewPaint,
    );

    // Radius line
    final edgePoint = _toLocal(
      Point2D(previewCircleCenter!.x + previewCircleRadius!, previewCircleCenter!.y),
    );
    final radiusLinePaint = Paint()
      ..color = Colors.red.withValues(alpha: 0.4)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    canvas.drawLine(center, edgePoint, radiusLinePaint);

    // Center dot
    canvas.drawCircle(
      center,
      3.0,
      Paint()..color = Colors.orange.withValues(alpha: 0.7),
    );

    // Preview radius label
    final labelPos = Offset(
      (center.dx + edgePoint.dx) / 2,
      (center.dy + edgePoint.dy) / 2 - 12,
    );
    final label = 'R=${_formatRadius(previewCircleRadius!)}';
    _drawLabel(canvas, labelPos, label);
  }

  String _formatRadius(double radiusPx) {
    if (calibration != null) {
      final mm = radiusPx / calibration!.pixelsPerMm;
      if (mm >= 1000) {
        return '${(mm / 1000).toStringAsFixed(2)} m';
      } else if (mm >= 10) {
        return '${mm.toStringAsFixed(1)} mm';
      } else {
        return '${mm.toStringAsFixed(2)} mm';
      }
    }
    return '${radiusPx.toStringAsFixed(1)} px';
  }

  void _drawRectMeasurements(Canvas canvas) {
    final rectPaint = Paint()
      ..color = Colors.red
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final hoveredPaint = Paint()
      ..color = Colors.cyan
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    for (final m in measurements) {
      if (m.type != MeasurementType.rectangle) continue;
      if (m.autoDetected) continue;

      // Selected is drawn last by _drawSelectedMeasurement.
      if (m.id == selectedMeasurementId) continue;

      final isHovered = m.id == hoveredMeasurementId;
      final paint = isHovered ? hoveredPaint : rectPaint;

      _drawRectWithLabels(canvas, m.startPoint, m.endPoint, paint);
    }
  }

  void _drawPreviewRect(Canvas canvas) {
    if (pendingPoint == null || previewRectEnd == null) return;

    final paint = Paint()
      ..color = Colors.red.withValues(alpha: 0.5)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    _drawRectWithLabels(canvas, pendingPoint!, previewRectEnd!, paint);
  }

  void _drawRectWithLabels(
    Canvas canvas,
    Point2D corner1,
    Point2D corner2,
    Paint paint, {
    bool highlightedLabel = false,
  }) {
    final tl = _toLocal(Point2D(
      corner1.x < corner2.x ? corner1.x : corner2.x,
      corner1.y > corner2.y ? corner1.y : corner2.y,
    ));
    final br = _toLocal(Point2D(
      corner1.x > corner2.x ? corner1.x : corner2.x,
      corner1.y < corner2.y ? corner1.y : corner2.y,
    ));
    final rect = Rect.fromPoints(tl, br);
    canvas.drawRect(rect, paint);

    // Dimension labels
    final w = (corner2.x - corner1.x).abs();
    final h = (corner2.y - corner1.y).abs();
    final wLabel = _formatRadius(w);
    final hLabel = _formatRadius(h);

    // Horizontal label — bottom edge center
    _drawLabel(
      canvas,
      Offset(rect.center.dx, rect.bottom + 14),
      wLabel,
      highlighted: highlightedLabel,
    );
    // Vertical label — right edge center
    _drawLabel(
      canvas,
      Offset(rect.right + 24, rect.center.dy),
      hLabel,
      highlighted: highlightedLabel,
    );
  }

  /// Draw the currently-selected measurement on top of everything else, with
  /// a highlighted (orange) stroke and a highlighted label so it can't be
  /// covered by other overlapping measurement labels.
  void _drawSelectedMeasurement(Canvas canvas) {
    if (selectedMeasurementId == null) return;

    Measurement? m;
    for (final candidate in measurements) {
      if (candidate.id == selectedMeasurementId) {
        m = candidate;
        break;
      }
    }
    if (m == null) return;

    final paint = Paint()
      ..color = Colors.orange
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    switch (m.type) {
      case MeasurementType.linear:
        canvas.drawLine(
          _toLocal(m.startPoint),
          _toLocal(m.endPoint),
          paint,
        );
        final label = _formatMeasurement(m);
        final mid = m.startPoint.midpointTo(m.endPoint);
        _drawLabel(canvas, _toLocal(mid), label, highlighted: true);

      case MeasurementType.arc:
        _drawArcOrBezierMeasurement(canvas, m, paint);
        final label = _formatMeasurement(m);
        final mid = m.startPoint.midpointTo(m.endPoint);
        _drawLabel(canvas, _toLocal(mid), label, highlighted: true);

      case MeasurementType.circle:
        final center = _toLocal(m.startPoint);
        final radius = m.pixelLength;
        final rx = radius * scaleX;
        final ry = radius * scaleY;
        canvas.drawOval(
          Rect.fromCenter(center: center, width: rx * 2, height: ry * 2),
          paint,
        );

        // Radius line
        final radiusLinePaint = Paint()
          ..color = Colors.orange.withValues(alpha: 0.7)
          ..strokeWidth = 1.0
          ..style = PaintingStyle.stroke;
        final edgePoint =
            _toLocal(Point2D(m.startPoint.x + radius, m.startPoint.y));
        canvas.drawLine(center, edgePoint, radiusLinePaint);
        canvas.drawCircle(center, 3.0, Paint()..color = Colors.orange);

        final labelPos = Offset(
          (center.dx + edgePoint.dx) / 2,
          (center.dy + edgePoint.dy) / 2 - 12,
        );
        final label = 'R=${_formatMeasurement(m)}';
        _drawLabel(canvas, labelPos, label, highlighted: true);

      case MeasurementType.rectangle:
        _drawRectWithLabels(
          canvas,
          m.startPoint,
          m.endPoint,
          paint,
          highlightedLabel: true,
        );
    }
  }

  void _drawPreviewArc(Canvas canvas) {
    // Only active when both arc endpoints are set (i.e. the arc tool's
    // "pick midpoint" phase).
    if (pendingPoint == null || pendingSecondPoint == null) return;

    final paint = Paint()
      ..color = Colors.red.withValues(alpha: 0.5)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    if (previewArc != null &&
        previewArc!.radius.isFinite &&
        previewArc!.radius > 0) {
      _drawArc(canvas, previewArc!, paint);
    } else {
      // Fallback: cursor coincides with an endpoint or all three points are
      // collinear — show the chord between the endpoints so the user still
      // sees a continuous preview between clicks.
      canvas.drawLine(
        _toLocal(pendingPoint!),
        _toLocal(pendingSecondPoint!),
        paint,
      );
    }

    // Arc-mode bulge guide: dashed line from the cursor to the second
    // endpoint, hinting that the cursor controls the third arc point.
    if (showArcBulgeGuide && crosshairPosition != null) {
      final guidePaint = Paint()
        ..color = Colors.red.withValues(alpha: 0.6)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke;
      _drawDashedLine(
        canvas,
        _toLocal(crosshairPosition!),
        _toLocal(pendingSecondPoint!),
        guidePaint,
        dashLength: 6,
        gapLength: 4,
      );
    }
  }

  /// Free-mode (Bezier) preview: draws the quadratic Bezier curve through
  /// pendingPoint → previewBezierControl → pendingSecondPoint, plus a
  /// small ring at the apex (the cursor / curve peak at t=0.5).
  void _drawPreviewBezier(Canvas canvas) {
    if (pendingPoint == null || pendingSecondPoint == null) return;
    if (previewBezierControl == null) return;

    final curvePaint = Paint()
      ..color = Colors.red.withValues(alpha: 0.5)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final start = _toLocal(pendingPoint!);
    final end = _toLocal(pendingSecondPoint!);
    final control = _toLocal(previewBezierControl!);

    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..quadraticBezierTo(control.dx, control.dy, end.dx, end.dy);
    canvas.drawPath(path, curvePaint);

    // Apex indicator at the cursor position (= curve peak).
    if (previewBezierApex != null) {
      final apex = _toLocal(previewBezierApex!);
      canvas.drawCircle(
        apex,
        4.5,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.9)
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        apex,
        4.5,
        Paint()
          ..color = Colors.red.withValues(alpha: 0.9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  /// Draws a dashed straight line between two screen-space points.
  void _drawDashedLine(
    Canvas canvas,
    Offset from,
    Offset to,
    Paint paint, {
    double dashLength = 6,
    double gapLength = 4,
  }) {
    final dx = to.dx - from.dx;
    final dy = to.dy - from.dy;
    final distance = math.sqrt(dx * dx + dy * dy);
    if (distance == 0) return;
    final stepX = dx / distance;
    final stepY = dy / distance;
    double drawn = 0;
    while (drawn < distance) {
      final segEnd = math.min(drawn + dashLength, distance);
      canvas.drawLine(
        Offset(from.dx + stepX * drawn, from.dy + stepY * drawn),
        Offset(from.dx + stepX * segEnd, from.dy + stepY * segEnd),
        paint,
      );
      drawn = segEnd + gapLength;
    }
  }

  void _drawPreviewLine(Canvas canvas) {
    if (pendingPoint == null || previewLineEnd == null) return;

    final paint = Paint()
      ..color = Colors.red.withValues(alpha: 0.5)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    canvas.drawLine(
      _toLocal(pendingPoint!),
      _toLocal(previewLineEnd!),
      paint,
    );

    // Length label at the midpoint.
    final pixelLength = pendingPoint!.distanceTo(previewLineEnd!);
    if (pixelLength < 0.5) return;

    final label = calibration != null
        ? _formatCalibratedLength(pixelLength)
        : '${pixelLength.toStringAsFixed(1)} px';

    final mid = pendingPoint!.midpointTo(previewLineEnd!);
    _drawLabel(canvas, _toLocal(mid), label);
  }

  String _formatCalibratedLength(double pixelLength) {
    final mm = calibration!.toMm(pixelLength);
    if (mm >= 1000) {
      return '${(mm / 1000).toStringAsFixed(2)} m';
    } else if (mm >= 10) {
      return '${mm.toStringAsFixed(1)} mm';
    } else {
      return '${mm.toStringAsFixed(2)} mm';
    }
  }

  void _drawCrosshair(Canvas canvas, Size size) {
    if (crosshairPosition == null) return;

    final center = _toLocal(crosshairPosition!);
    final paint = Paint()
      ..color = const Color(0x99000000)
      ..strokeWidth = 0.5;

    // Horizontal line spanning full width
    canvas.drawLine(Offset(0, center.dy), Offset(size.width, center.dy), paint);
    // Vertical line spanning full height
    canvas.drawLine(Offset(center.dx, 0), Offset(center.dx, size.height), paint);
  }

  @override
  bool shouldRepaint(covariant _OverlayPainter oldDelegate) =>
      detectedElements != oldDelegate.detectedElements ||
      joints != oldDelegate.joints ||
      measurements != oldDelegate.measurements ||
      calibration != oldDelegate.calibration ||
      pendingPoint != oldDelegate.pendingPoint ||
      pendingSecondPoint != oldDelegate.pendingSecondPoint ||
      snapIndicator != oldDelegate.snapIndicator ||
      snapRadius != oldDelegate.snapRadius ||
      scaleX != oldDelegate.scaleX ||
      scaleY != oldDelegate.scaleY ||
      pageHeight != oldDelegate.pageHeight ||
      selectedMeasurementId != oldDelegate.selectedMeasurementId ||
      hoveredMeasurementId != oldDelegate.hoveredMeasurementId ||
      crosshairPosition != oldDelegate.crosshairPosition ||
      previewCircleCenter != oldDelegate.previewCircleCenter ||
      previewCircleRadius != oldDelegate.previewCircleRadius ||
      previewRectEnd != oldDelegate.previewRectEnd ||
      previewLineEnd != oldDelegate.previewLineEnd ||
      previewArc != oldDelegate.previewArc ||
      previewBezierControl != oldDelegate.previewBezierControl ||
      previewBezierApex != oldDelegate.previewBezierApex ||
      showArcBulgeGuide != oldDelegate.showArcBulgeGuide;
}
