import '../geometry/point2d.dart';

class CalibrationScale {
  /// The known real-world distance in mm.
  final double knownDistanceMm;

  /// The corresponding pixel distance on the PDF.
  final double pixelDistance;

  const CalibrationScale({
    required this.knownDistanceMm,
    required this.pixelDistance,
  });

  /// Pixels per mm.
  double get pixelsPerMm {
    if (knownDistanceMm == 0) return double.infinity;
    return pixelDistance / knownDistanceMm;
  }

  /// Convert a pixel distance to mm.
  double toMm(double pixels) => pixels / pixelsPerMm;

  /// Convert mm to pixel distance.
  double toPixels(double mm) => mm * pixelsPerMm;

  /// Create a calibration from two points and a known distance.
  factory CalibrationScale.fromPoints(
    Point2D p1,
    Point2D p2,
    double knownDistanceMm,
  ) {
    if (knownDistanceMm <= 0) {
      throw ArgumentError('knownDistanceMm must be positive, got $knownDistanceMm');
    }
    final pixelDist = p1.distanceTo(p2);
    if (pixelDist < 0.001) {
      throw ArgumentError('Calibration points are too close together');
    }
    return CalibrationScale(
      knownDistanceMm: knownDistanceMm,
      pixelDistance: pixelDist,
    );
  }

  Map<String, dynamic> toJson() => {
        'knownDistanceMm': knownDistanceMm,
        'pixelDistance': pixelDistance,
      };

  factory CalibrationScale.fromJson(Map<String, dynamic> json) => CalibrationScale(
        knownDistanceMm: (json['knownDistanceMm'] as num).toDouble(),
        pixelDistance: (json['pixelDistance'] as num).toDouble(),
      );

  @override
  String toString() =>
      'CalibrationScale(${pixelsPerMm.toStringAsFixed(2)} px/mm)';
}
