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
  final ArcSegment? previewArc;

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
    this.previewArc,
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
            previewArc: previewArc,
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
  final ArcSegment? previewArc;

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
    this.previewArc,
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
    _drawPendingPoint(canvas);
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

    final selectedPaint = Paint()
      ..color = Colors.orange
      ..strokeWidth = 3.0
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

      final isSelected = m.id == selectedMeasurementId;
      final isHovered = m.id == hoveredMeasurementId;

      // Auto-detected measurements are invisible unless selected or hovered.
      if (m.autoDetected && !isSelected && !isHovered) continue;

      final paint = isSelected
          ? selectedPaint
          : isHovered
              ? hoveredPaint
              : manualPaint;

      if (m.type == MeasurementType.arc && m.arcSegment != null) {
        _drawArc(canvas, m.arcSegment!, paint);
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

  void _drawLabel(Canvas canvas, Offset position, String text) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Color(0xFF333333),
          fontSize: 11,
          fontWeight: FontWeight.w600,
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

    canvas.drawRRect(
      bgRect,
      Paint()..color = Colors.white.withValues(alpha: 0.9),
    );
    canvas.drawRRect(
      bgRect,
      Paint()
        ..color = Colors.grey.shade400
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5,
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

    final selectedPaint = Paint()
      ..color = Colors.orange
      ..strokeWidth = 3.0
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

      final isSelected = m.id == selectedMeasurementId;
      final isHovered = m.id == hoveredMeasurementId;

      final paint = isSelected
          ? selectedPaint
          : isHovered
              ? hoveredPaint
              : circlePaint;

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

    final selectedPaint = Paint()
      ..color = Colors.orange
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    final hoveredPaint = Paint()
      ..color = Colors.cyan
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    for (final m in measurements) {
      if (m.type != MeasurementType.rectangle) continue;
      if (m.autoDetected) continue;

      final isSelected = m.id == selectedMeasurementId;
      final isHovered = m.id == hoveredMeasurementId;

      final paint = isSelected
          ? selectedPaint
          : isHovered
              ? hoveredPaint
              : rectPaint;

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
    Paint paint,
  ) {
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
    );
    // Vertical label — right edge center
    _drawLabel(
      canvas,
      Offset(rect.right + 24, rect.center.dy),
      hLabel,
    );
  }

  void _drawPreviewArc(Canvas canvas) {
    if (previewArc == null) return;
    if (!previewArc!.radius.isFinite || previewArc!.radius <= 0) return;

    final paint = Paint()
      ..color = Colors.red.withValues(alpha: 0.5)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    _drawArc(canvas, previewArc!, paint);
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
      previewArc != oldDelegate.previewArc;
}
