import '../core/geometry/point2d.dart';
import '../core/geometry/line_segment.dart';
import '../core/geometry/arc_segment.dart';

enum DetectedElementType { line, arc }

class DetectedElement {
  final String id;
  final DetectedElementType type;
  final LineSegment? lineSegment;
  final ArcSegment? arcSegment;

  const DetectedElement._({
    required this.id,
    required this.type,
    this.lineSegment,
    this.arcSegment,
  });

  factory DetectedElement.line(String id, LineSegment segment) => DetectedElement._(
        id: id,
        type: DetectedElementType.line,
        lineSegment: segment,
      );

  factory DetectedElement.arc(String id, ArcSegment segment) => DetectedElement._(
        id: id,
        type: DetectedElementType.arc,
        arcSegment: segment,
      );

  double get length {
    switch (type) {
      case DetectedElementType.line:
        return lineSegment!.length;
      case DetectedElementType.arc:
        return arcSegment!.arcLength;
    }
  }

  /// Get the closest point on this element to the given point.
  Point2D closestPointTo(Point2D point) {
    switch (type) {
      case DetectedElementType.line:
        return lineSegment!.closestPointTo(point);
      case DetectedElementType.arc:
        return arcSegment!.closestPointTo(point);
    }
  }

  double distanceToPoint(Point2D point) {
    switch (type) {
      case DetectedElementType.line:
        return lineSegment!.distanceToPoint(point);
      case DetectedElementType.arc:
        return arcSegment!.distanceToPoint(point);
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        if (lineSegment != null) 'lineSegment': lineSegment!.toJson(),
        if (arcSegment != null) 'arcSegment': arcSegment!.toJson(),
      };

  factory DetectedElement.fromJson(Map<String, dynamic> json) {
    final type = DetectedElementType.values.byName(json['type'] as String);
    return DetectedElement._(
      id: json['id'] as String,
      type: type,
      lineSegment: json['lineSegment'] != null
          ? LineSegment.fromJson(json['lineSegment'] as Map<String, dynamic>)
          : null,
      arcSegment: json['arcSegment'] != null
          ? ArcSegment.fromJson(json['arcSegment'] as Map<String, dynamic>)
          : null,
    );
  }
}
