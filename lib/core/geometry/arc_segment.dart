import 'dart:math';
import 'point2d.dart';

class ArcSegment {
  final Point2D center;
  final double radius;
  final double startAngle; // in radians
  final double endAngle;   // in radians
  final bool clockwise;

  const ArcSegment({
    required this.center,
    required this.radius,
    required this.startAngle,
    required this.endAngle,
    this.clockwise = false,
  });

  Point2D get startPoint => Point2D(
        center.x + radius * cos(startAngle),
        center.y + radius * sin(startAngle),
      );

  Point2D get endPoint => Point2D(
        center.x + radius * cos(endAngle),
        center.y + radius * sin(endAngle),
      );

  double get sweepAngle {
    var sweep = endAngle - startAngle;
    if (clockwise) {
      if (sweep > 0) sweep -= 2 * pi;
    } else {
      if (sweep < 0) sweep += 2 * pi;
    }
    return sweep;
  }

  double get arcLength => radius * sweepAngle.abs();

  /// Returns the closest point on this arc to the given point.
  Point2D closestPointTo(Point2D point) {
    final angle = atan2(point.y - center.y, point.x - center.x);
    if (_isAngleInArc(angle)) {
      return Point2D(
        center.x + radius * cos(angle),
        center.y + radius * sin(angle),
      );
    }
    // Return whichever endpoint is closer
    final dStart = point.distanceTo(startPoint);
    final dEnd = point.distanceTo(endPoint);
    return dStart <= dEnd ? startPoint : endPoint;
  }

  double distanceToPoint(Point2D point) {
    return closestPointTo(point).distanceTo(point);
  }

  bool _isAngleInArc(double angle) {
    var a = _normalizeAngle(angle);
    var s = _normalizeAngle(startAngle);
    var e = _normalizeAngle(endAngle);

    if (clockwise) {
      if (s >= e) return a <= s && a >= e;
      return a <= s || a >= e;
    } else {
      if (s <= e) return a >= s && a <= e;
      return a >= s || a <= e;
    }
  }

  static double _normalizeAngle(double angle) {
    angle = angle % (2 * pi);
    if (angle < 0) angle += 2 * pi;
    return angle;
  }

  /// Create an arc from three points (start, mid, end) on the arc.
  factory ArcSegment.fromThreePoints(Point2D p1, Point2D p2, Point2D p3) {
    final ax = p1.x, ay = p1.y;
    final bx = p2.x, by = p2.y;
    final cx = p3.x, cy = p3.y;

    final d = 2 * (ax * (by - cy) + bx * (cy - ay) + cx * (ay - by));
    if (d.abs() < 1e-10) {
      // Points are collinear, return a large-radius arc approximation
      return ArcSegment(
        center: p1.midpointTo(p3),
        radius: double.infinity,
        startAngle: 0,
        endAngle: 0,
      );
    }

    final ux = ((ax * ax + ay * ay) * (by - cy) +
            (bx * bx + by * by) * (cy - ay) +
            (cx * cx + cy * cy) * (ay - by)) /
        d;
    final uy = ((ax * ax + ay * ay) * (cx - bx) +
            (bx * bx + by * by) * (ax - cx) +
            (cx * cx + cy * cy) * (bx - ax)) /
        d;

    final center = Point2D(ux, uy);
    final radius = center.distanceTo(p1);
    final startAngle = atan2(ay - uy, ax - ux);
    final endAngle = atan2(cy - uy, cx - ux);

    // Determine direction from cross product
    final cross = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
    final clockwise = cross > 0;

    return ArcSegment(
      center: center,
      radius: radius,
      startAngle: startAngle,
      endAngle: endAngle,
      clockwise: clockwise,
    );
  }

  /// Create a circular arc from two endpoints and a radius.
  factory ArcSegment.fromEndpointsAndRadius(
    Point2D start,
    Point2D end,
    double radius, {
    bool largeArc = false,
    bool clockwise = false,
  }) {
    if (!radius.isFinite || radius <= 0) {
      throw ArgumentError('radius must be positive and finite, got $radius');
    }
    final dist = start.distanceTo(end);
    if (dist < 0.001) {
      throw ArgumentError('start and end points are the same (or nearly so)');
    }

    final mid = start.midpointTo(end);
    final halfDist = dist / 2;

    if (halfDist > radius) {
      // Points are too far apart for the given radius; use minimum radius
      radius = halfDist;
    }

    final h = sqrt(radius * radius - halfDist * halfDist);
    final dx = end.x - start.x;
    final dy = end.y - start.y;
    final len = dist;

    final sign = (largeArc == clockwise) ? -1.0 : 1.0;
    final center = Point2D(
      mid.x + sign * h * (-dy / len),
      mid.y + sign * h * (dx / len),
    );

    final startAngle = atan2(start.y - center.y, start.x - center.x);
    final endAngle = atan2(end.y - center.y, end.x - center.x);

    return ArcSegment(
      center: center,
      radius: radius,
      startAngle: startAngle,
      endAngle: endAngle,
      clockwise: clockwise,
    );
  }

  Map<String, dynamic> toJson() => {
        'center': center.toJson(),
        'radius': radius,
        'startAngle': startAngle,
        'endAngle': endAngle,
        'clockwise': clockwise,
      };

  factory ArcSegment.fromJson(Map<String, dynamic> json) => ArcSegment(
        center: Point2D.fromJson(json['center'] as Map<String, dynamic>),
        radius: (json['radius'] as num).toDouble(),
        startAngle: (json['startAngle'] as num).toDouble(),
        endAngle: (json['endAngle'] as num).toDouble(),
        clockwise: json['clockwise'] as bool,
      );

  @override
  String toString() =>
      'ArcSegment(center: $center, r: $radius, ${startAngle.toStringAsFixed(2)}..${endAngle.toStringAsFixed(2)})';
}
