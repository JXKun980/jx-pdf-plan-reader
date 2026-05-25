import '../core/calibration/scale.dart';
import '../core/geometry/intersections.dart';
import 'detected_element.dart';
import 'measurement.dart';

class PageData {
  final int pageIndex;
  final bool isVectorPage;
  final List<DetectedElement> detectedElements;
  final List<Joint> detectedJoints;
  final List<Measurement> measurements;
  final CalibrationScale? calibration;

  const PageData({
    required this.pageIndex,
    this.isVectorPage = false,
    this.detectedElements = const [],
    this.detectedJoints = const [],
    this.measurements = const [],
    this.calibration,
  });

  PageData copyWith({
    int? pageIndex,
    bool? isVectorPage,
    List<DetectedElement>? detectedElements,
    List<Joint>? detectedJoints,
    List<Measurement>? measurements,
    CalibrationScale? calibration,
    bool clearCalibration = false,
  }) {
    return PageData(
      pageIndex: pageIndex ?? this.pageIndex,
      isVectorPage: isVectorPage ?? this.isVectorPage,
      detectedElements: detectedElements ?? this.detectedElements,
      detectedJoints: detectedJoints ?? this.detectedJoints,
      measurements: measurements ?? this.measurements,
      calibration: clearCalibration ? null : (calibration ?? this.calibration),
    );
  }
}
