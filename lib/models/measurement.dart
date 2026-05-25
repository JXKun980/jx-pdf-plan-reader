import '../core/geometry/point2d.dart';
import '../core/geometry/arc_segment.dart';

enum MeasurementType { linear, arc, circle, rectangle }

class Measurement {
  final String id;
  final MeasurementType type;
  final Point2D startPoint;
  final Point2D endPoint;
  final ArcSegment? arcSegment; // Only for arc measurements
  final double pixelLength;
  final bool startSnapped;
  final bool endSnapped;

  /// True when the measurement was auto-created from geometry detection.
  final bool autoDetected;

  const Measurement({
    required this.id,
    required this.type,
    required this.startPoint,
    required this.endPoint,
    this.arcSegment,
    required this.pixelLength,
    this.startSnapped = false,
    this.endSnapped = false,
    this.autoDetected = false,
  });

  /// Get the real-world length in mm using the provided scale factor (pixels per mm).
  double lengthInMm(double pixelsPerMm) => pixelLength / pixelsPerMm;

  /// Format the length string with unit.
  String formatLength(double pixelsPerMm) {
    final mm = lengthInMm(pixelsPerMm);
    if (mm >= 1000) {
      return '${(mm / 1000).toStringAsFixed(2)} m';
    } else if (mm >= 10) {
      return '${mm.toStringAsFixed(1)} mm';
    } else {
      return '${mm.toStringAsFixed(2)} mm';
    }
  }

  Measurement copyWith({
    String? id,
    MeasurementType? type,
    Point2D? startPoint,
    Point2D? endPoint,
    ArcSegment? arcSegment,
    bool clearArcSegment = false,
    double? pixelLength,
    bool? startSnapped,
    bool? endSnapped,
    bool? autoDetected,
  }) {
    return Measurement(
      id: id ?? this.id,
      type: type ?? this.type,
      startPoint: startPoint ?? this.startPoint,
      endPoint: endPoint ?? this.endPoint,
      arcSegment: clearArcSegment ? null : (arcSegment ?? this.arcSegment),
      pixelLength: pixelLength ?? this.pixelLength,
      startSnapped: startSnapped ?? this.startSnapped,
      endSnapped: endSnapped ?? this.endSnapped,
      autoDetected: autoDetected ?? this.autoDetected,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'startPoint': startPoint.toJson(),
        'endPoint': endPoint.toJson(),
        if (arcSegment != null) 'arcSegment': arcSegment!.toJson(),
        'pixelLength': pixelLength,
        'startSnapped': startSnapped,
        'endSnapped': endSnapped,
        'autoDetected': autoDetected,
      };

  factory Measurement.fromJson(Map<String, dynamic> json) => Measurement(
        id: json['id'] as String,
        type: MeasurementType.values.byName(json['type'] as String),
        startPoint: Point2D.fromJson(json['startPoint'] as Map<String, dynamic>),
        endPoint: Point2D.fromJson(json['endPoint'] as Map<String, dynamic>),
        arcSegment: json['arcSegment'] != null
            ? ArcSegment.fromJson(json['arcSegment'] as Map<String, dynamic>)
            : null,
        pixelLength: (json['pixelLength'] as num).toDouble(),
        startSnapped: json['startSnapped'] as bool? ?? false,
        endSnapped: json['endSnapped'] as bool? ?? false,
        autoDetected: json['autoDetected'] as bool? ?? false,
      );
}
