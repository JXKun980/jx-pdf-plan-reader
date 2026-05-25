import 'dart:math' as math;

import '../geometry/arc_segment.dart';
import '../geometry/line_segment.dart';
import '../geometry/line_style.dart';
import '../geometry/point2d.dart';
import 'path_operators.dart';

class PdfPathExtractor {
  /// Extract paths from pre-parsed commands (e.g. from PDF.js operator list).
  ///
  /// When [preTransformed] is true (the default), path coordinates are assumed
  /// to already have the CTM baked in (as PDF.js `constructPath` does).
  /// CTM / save / restore commands are still consumed but NOT applied to
  /// path coordinates.  Set to false when feeding raw content-stream data
  /// where the CTM must be applied manually.
  static ExtractedPaths extractFromCommands(
    List<PathCommand> commands, {
    bool preTransformed = true,
  }) {
    final lines = <LineSegment>[];
    final lineStyles = <LineStyle>[];
    final arcs = <ArcSegment>[];

    Point2D? currentPoint;
    Point2D? subpathStart;

    // CTM transform stack – only used when !preTransformed.
    var ctm = <double>[1, 0, 0, 1, 0, 0];
    final ctmStack = <List<double>>[];

    // Graphics state tracking for style metadata.
    var style = LineStyle.defaultStyle;
    final styleStack = <LineStyle>[];

    Point2D pt(double x, double y) {
      final raw = Point2D(x, y);
      return preTransformed ? raw : _transformPoint(raw, ctm);
    }

    void addLine(LineSegment seg) {
      lines.add(seg);
      lineStyles.add(style);
    }

    for (final cmd in commands) {
      switch (cmd.type) {
        case PathCommandType.saveState:
          ctmStack.add(List<double>.from(ctm));
          styleStack.add(style);
          break;

        case PathCommandType.restoreState:
          if (ctmStack.isNotEmpty) {
            ctm = ctmStack.removeLast();
          }
          if (styleStack.isNotEmpty) {
            style = styleStack.removeLast();
          }
          break;

        case PathCommandType.setCTM:
          if (!preTransformed) {
            ctm = _multiplyMatrices(ctm, cmd.args);
          }
          break;

        // --- Graphics state: line width & colors ---
        case PathCommandType.setLineWidth:
          style = style.copyWith(lineWidth: cmd.args[0]);
          break;

        case PathCommandType.setStrokeRGBColor:
          style = style.copyWith(
            r: cmd.args[0], g: cmd.args[1], b: cmd.args[2],
          );
          break;

        case PathCommandType.setStrokeGray:
          final v = cmd.args[0];
          style = style.copyWith(r: v, g: v, b: v);
          break;

        case PathCommandType.setStrokeCMYKColor:
          final c = cmd.args[0], m = cmd.args[1];
          final y = cmd.args[2], k = cmd.args[3];
          style = style.copyWith(
            r: (1 - c) * (1 - k),
            g: (1 - m) * (1 - k),
            b: (1 - y) * (1 - k),
          );
          break;

        case PathCommandType.setDash:
          // args = [...dashArray, dashPhase]. Empty dashArray = solid.
          final isDashed = cmd.args.length > 1 ||
              (cmd.args.isNotEmpty && cmd.args[0] != 0);
          style = style.copyWith(isDashed: isDashed);
          break;

        case PathCommandType.setFillRGBColor:
        case PathCommandType.setFillGray:
        case PathCommandType.setFillCMYKColor:
          // Track fill color if needed later; skip for now.
          break;

        // --- Path construction ---
        case PathCommandType.moveTo:
          currentPoint = pt(cmd.args[0], cmd.args[1]);
          subpathStart = currentPoint;
          break;

        case PathCommandType.lineTo:
          if (currentPoint != null) {
            final endPoint = pt(cmd.args[0], cmd.args[1]);
            final length = currentPoint.distanceTo(endPoint);
            if (length > 0.5) {
              addLine(LineSegment(currentPoint, endPoint));
            }
            currentPoint = endPoint;
          }
          break;

        case PathCommandType.curveTo:
          if (currentPoint != null) {
            final cp1 = pt(cmd.args[0], cmd.args[1]);
            final cp2 = pt(cmd.args[2], cmd.args[3]);
            final endPoint = pt(cmd.args[4], cmd.args[5]);

            final arc = _cubicBezierToArc(currentPoint, cp1, cp2, endPoint);
            if (arc != null) {
              arcs.add(arc);
            } else {
              final segments = _approximateBezierWithLines(currentPoint, cp1, cp2, endPoint);
              for (final seg in segments) {
                addLine(seg);
              }
            }
            currentPoint = endPoint;
          }
          break;

        case PathCommandType.curveToV:
          if (currentPoint != null) {
            final cp1 = currentPoint;
            final cp2 = pt(cmd.args[0], cmd.args[1]);
            final endPoint = pt(cmd.args[2], cmd.args[3]);

            final arc = _cubicBezierToArc(currentPoint, cp1, cp2, endPoint);
            if (arc != null) {
              arcs.add(arc);
            } else {
              final segments = _approximateBezierWithLines(currentPoint, cp1, cp2, endPoint);
              for (final seg in segments) {
                addLine(seg);
              }
            }
            currentPoint = endPoint;
          }
          break;

        case PathCommandType.curveToY:
          if (currentPoint != null) {
            final cp1 = pt(cmd.args[0], cmd.args[1]);
            final endPoint = pt(cmd.args[2], cmd.args[3]);
            final cp2 = endPoint;

            final arc = _cubicBezierToArc(currentPoint, cp1, cp2, endPoint);
            if (arc != null) {
              arcs.add(arc);
            } else {
              final segments = _approximateBezierWithLines(currentPoint, cp1, cp2, endPoint);
              for (final seg in segments) {
                addLine(seg);
              }
            }
            currentPoint = endPoint;
          }
          break;

        case PathCommandType.closePath:
          if (currentPoint != null && subpathStart != null) {
            final length = currentPoint.distanceTo(subpathStart);
            if (length > 0.5) {
              addLine(LineSegment(currentPoint, subpathStart));
            }
            currentPoint = subpathStart;
          }
          break;

        case PathCommandType.rect:
          final x = cmd.args[0], y = cmd.args[1];
          final w = cmd.args[2], h = cmd.args[3];
          final p1 = pt(x, y);
          final p2 = pt(x + w, y);
          final p3 = pt(x + w, y + h);
          final p4 = pt(x, y + h);
          final rectEdges = [
            LineSegment(p1, p2),
            LineSegment(p2, p3),
            LineSegment(p3, p4),
            LineSegment(p4, p1),
          ];
          for (final edge in rectEdges) {
            if (edge.length > 0.5) {
              addLine(edge);
            }
          }
          currentPoint = p1;
          subpathStart = p1;
          break;
      }
    }

    // Post-process: merge collinear short segments into full lines.
    // This reconstructs dashed lines drawn as individual dash segments.
    final merged = _mergeCollinearSegments(lines, lineStyles);

    return ExtractedPaths(
      lines: merged.lines,
      lineStyles: merged.lineStyles,
      arcs: arcs,
    );
  }

  /// Merge consecutive short segments that are collinear (same angle, nearly
  /// touching endpoints) into a single long line.  This reconstructs dashed
  /// lines that CAD software exports as individual dash strokes.
  static ({List<LineSegment> lines, List<LineStyle> lineStyles})
      _mergeCollinearSegments(
    List<LineSegment> lines,
    List<LineStyle> styles, {
    double gapTolerance = 20.0,
    double angleTolerance = 0.05, // ~3°
    double collinearTolerance = 2.0, // max perpendicular offset
    double maxDashLength = 50.0,
  }) {
    if (lines.length < 2) return (lines: lines, lineStyles: styles);

    final outLines = <LineSegment>[];
    final outStyles = <LineStyle>[];
    final used = List.filled(lines.length, false);

    for (var i = 0; i < lines.length; i++) {
      if (used[i]) continue;

      var seg = lines[i];
      final style = styles[i];
      used[i] = true;

      // Only merge short segments (likely dash fragments).
      if (seg.length > maxDashLength) {
        outLines.add(seg);
        outStyles.add(style);
        continue;
      }

      // Collect collinear neighbours.
      bool merged;
      do {
        merged = false;
        for (var j = i + 1; j < lines.length; j++) {
          if (used[j]) continue;
          final candidate = lines[j];
          if (candidate.length > maxDashLength) continue;

          // Only merge segments with the same stroke color.
          final cs = styles[j];
          if ((style.r - cs.r).abs() > 0.05 ||
              (style.g - cs.g).abs() > 0.05 ||
              (style.b - cs.b).abs() > 0.05) {
            continue;
          }

          // Check angle similarity.
          final a1 = _normalizedAngle(seg);
          final a2 = _normalizedAngle(candidate);
          var da = (a1 - a2).abs();
          if (da > math.pi / 2) da = math.pi - da;
          if (da > angleTolerance) continue;

          // Check collinearity: candidate midpoint must lie close to the
          // infinite line through seg. Using perpendicular distance
          // (not finite-segment distance) so that distant-but-collinear
          // dashes are not rejected.
          final candidateMid = candidate.start.midpointTo(candidate.end);
          if (_perpendicularDistance(seg, candidateMid) > collinearTolerance) {
            continue;
          }

          // Check if endpoints are close (gap between dash segments).
          final d1 = seg.end.distanceTo(candidate.start);
          final d2 = seg.start.distanceTo(candidate.end);
          final d3 = seg.end.distanceTo(candidate.end);
          final d4 = seg.start.distanceTo(candidate.start);
          final minDist = [d1, d2, d3, d4].reduce((a, b) => a < b ? a : b);
          if (minDist > gapTolerance) continue;

          // Merge: project all four endpoints onto the line direction and
          // pick the two extremes.  This avoids the "furthest apart"
          // approach which can pick a diagonal when points are offset.
          final dx = seg.end.x - seg.start.x;
          final dy = seg.end.y - seg.start.y;
          final len = math.sqrt(dx * dx + dy * dy);
          final ux = len > 0 ? dx / len : 1.0;
          final uy = len > 0 ? dy / len : 0.0;
          // Use seg.start as projection origin.
          final ox = seg.start.x, oy = seg.start.y;

          double proj(Point2D p) => (p.x - ox) * ux + (p.y - oy) * uy;

          final points = [seg.start, seg.end, candidate.start, candidate.end];
          var minProj = double.infinity, maxProj = double.negativeInfinity;
          var minPt = points[0], maxPt = points[1];
          for (final p in points) {
            final t = proj(p);
            if (t < minProj) { minProj = t; minPt = p; }
            if (t > maxProj) { maxProj = t; maxPt = p; }
          }

          seg = LineSegment(minPt, maxPt);
          used[j] = true;
          merged = true;
        }
      } while (merged);

      outLines.add(seg);
      outStyles.add(style);
    }

    return (lines: outLines, lineStyles: outStyles);
  }

  /// Perpendicular distance from [point] to the infinite line through [seg].
  static double _perpendicularDistance(LineSegment seg, Point2D point) {
    final dx = seg.end.x - seg.start.x;
    final dy = seg.end.y - seg.start.y;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 1e-10) return point.distanceTo(seg.start);
    // |cross product| / length = perpendicular distance
    return ((point.x - seg.start.x) * dy - (point.y - seg.start.y) * dx).abs() / len;
  }

  /// Line angle normalised to [0, π) — direction-independent.
  static double _normalizedAngle(LineSegment line) {
    final dx = line.end.x - line.start.x;
    final dy = line.end.y - line.start.y;
    var a = math.atan2(dy, dx);
    if (a < 0) a += math.pi;
    if (a >= math.pi) a -= math.pi;
    return a;
  }

  static Point2D _transformPoint(Point2D p, List<double> ctm) {
    return Point2D(
      ctm[0] * p.x + ctm[2] * p.y + ctm[4],
      ctm[1] * p.x + ctm[3] * p.y + ctm[5],
    );
  }

  static List<double> _multiplyMatrices(List<double> a, List<double> b) {
    return [
      a[0] * b[0] + a[2] * b[1],
      a[1] * b[0] + a[3] * b[1],
      a[0] * b[2] + a[2] * b[3],
      a[1] * b[2] + a[3] * b[3],
      a[0] * b[4] + a[2] * b[5] + a[4],
      a[1] * b[4] + a[3] * b[5] + a[5],
    ];
  }

  /// Attempt to convert a cubic bezier curve to a circular arc.
  /// Returns null if the bezier is not close enough to circular.
  static ArcSegment? _cubicBezierToArc(
    Point2D p0, Point2D p1, Point2D p2, Point2D p3,
  ) {
    // Sample the bezier at several points and check if they lie on a circle
    const sampleCount = 8;
    final points = <Point2D>[];
    for (var i = 0; i <= sampleCount; i++) {
      final t = i / sampleCount;
      points.add(_evaluateCubicBezier(p0, p1, p2, p3, t));
    }

    // Try to find the circumscribed circle using three points
    final start = points.first;
    final mid = points[sampleCount ~/ 2];
    final end = points.last;

    final arc = ArcSegment.fromThreePoints(start, mid, end);

    if (arc.radius == double.infinity || arc.radius > 100000) {
      return null; // Essentially a straight line
    }

    // Check all sample points lie close to the circle
    const tolerance = 2.0;
    for (final point in points) {
      final distFromCenter = point.distanceTo(arc.center);
      if ((distFromCenter - arc.radius).abs() > tolerance) {
        return null; // Not circular enough
      }
    }

    return arc;
  }

  static Point2D _evaluateCubicBezier(
    Point2D p0, Point2D p1, Point2D p2, Point2D p3, double t,
  ) {
    final mt = 1 - t;
    final mt2 = mt * mt;
    final mt3 = mt2 * mt;
    final t2 = t * t;
    final t3 = t2 * t;

    return Point2D(
      mt3 * p0.x + 3 * mt2 * t * p1.x + 3 * mt * t2 * p2.x + t3 * p3.x,
      mt3 * p0.y + 3 * mt2 * t * p1.y + 3 * mt * t2 * p2.y + t3 * p3.y,
    );
  }

  static List<LineSegment> _approximateBezierWithLines(
    Point2D p0, Point2D p1, Point2D p2, Point2D p3, {
    double tolerance = 0.5,
  }) {
    final lines = <LineSegment>[];
    _subdivideBezier(p0, p1, p2, p3, lines, tolerance, 0);
    return lines;
  }

  static void _subdivideBezier(
    Point2D p0, Point2D p1, Point2D p2, Point2D p3,
    List<LineSegment> lines, double tolerance, int depth,
  ) {
    // Flatness test: check if control points are close to the line p0->p3
    final seg = LineSegment(p0, p3);
    final d1 = seg.distanceToPoint(p1);
    final d2 = seg.distanceToPoint(p2);

    if ((d1 + d2 < tolerance) || depth > 10) {
      if (p0.distanceTo(p3) > 0.1) {
        lines.add(LineSegment(p0, p3));
      }
      return;
    }

    // De Casteljau subdivision at t=0.5
    final p01 = p0.midpointTo(p1);
    final p12 = p1.midpointTo(p2);
    final p23 = p2.midpointTo(p3);
    final p012 = p01.midpointTo(p12);
    final p123 = p12.midpointTo(p23);
    final mid = p012.midpointTo(p123);

    _subdivideBezier(p0, p01, p012, mid, lines, tolerance, depth + 1);
    _subdivideBezier(mid, p123, p23, p3, lines, tolerance, depth + 1);
  }
}

class ExtractedPaths {
  final List<LineSegment> lines;

  /// Parallel list of styles, one per entry in [lines].
  final List<LineStyle> lineStyles;

  final List<ArcSegment> arcs;

  const ExtractedPaths({
    required this.lines,
    required this.lineStyles,
    required this.arcs,
  });

  bool get isEmpty => lines.isEmpty && arcs.isEmpty;
  bool get isNotEmpty => !isEmpty;
}
