import 'point2d.dart';

class LineSegment {
  final Point2D start;
  final Point2D end;

  const LineSegment(this.start, this.end);

  double get length => start.distanceTo(end);

  Point2D get midpoint => start.midpointTo(end);

  double get angle => start.angleTo(end);

  /// Returns the closest point on this line segment to the given point.
  Point2D closestPointTo(Point2D point) {
    final dx = end.x - start.x;
    final dy = end.y - start.y;
    final lengthSquared = dx * dx + dy * dy;

    if (lengthSquared == 0) return start;

    var t = ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared;
    t = t.clamp(0.0, 1.0);

    return Point2D(start.x + t * dx, start.y + t * dy);
  }

  /// Returns the distance from the given point to this line segment.
  double distanceToPoint(Point2D point) {
    return closestPointTo(point).distanceTo(point);
  }

  /// Returns the intersection point with another line segment, or null if they don't intersect.
  Point2D? intersectionWith(LineSegment other) {
    final x1 = start.x, y1 = start.y;
    final x2 = end.x, y2 = end.y;
    final x3 = other.start.x, y3 = other.start.y;
    final x4 = other.end.x, y4 = other.end.y;

    final denom = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4);
    if (denom.abs() < 1e-10) return null; // Parallel or coincident

    final t = ((x1 - x3) * (y3 - y4) - (y1 - y3) * (x3 - x4)) / denom;
    final u = -((x1 - x2) * (y1 - y3) - (y1 - y2) * (x1 - x3)) / denom;

    if (t >= -1e-10 && t <= 1 + 1e-10 && u >= -1e-10 && u <= 1 + 1e-10) {
      return Point2D(x1 + t * (x2 - x1), y1 + t * (y2 - y1));
    }
    return null;
  }

  /// Returns the intersection point treating both as infinite lines, or null if parallel.
  Point2D? lineIntersectionWith(LineSegment other) {
    final x1 = start.x, y1 = start.y;
    final x2 = end.x, y2 = end.y;
    final x3 = other.start.x, y3 = other.start.y;
    final x4 = other.end.x, y4 = other.end.y;

    final denom = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4);
    if (denom.abs() < 1e-10) return null;

    final t = ((x1 - x3) * (y3 - y4) - (y1 - y3) * (x3 - x4)) / denom;
    return Point2D(x1 + t * (x2 - x1), y1 + t * (y2 - y1));
  }

  Map<String, dynamic> toJson() => {
        'start': start.toJson(),
        'end': end.toJson(),
      };

  factory LineSegment.fromJson(Map<String, dynamic> json) => LineSegment(
        Point2D.fromJson(json['start'] as Map<String, dynamic>),
        Point2D.fromJson(json['end'] as Map<String, dynamic>),
      );

  @override
  String toString() => 'LineSegment($start -> $end)';
}
