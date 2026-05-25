import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/calibration/scale.dart';
import 'page_state.dart';

/// Derived provider that exposes the current page's [CalibrationScale], or
/// `null` if no calibration has been set.
final currentCalibrationProvider = Provider<CalibrationScale?>((ref) {
  final pageData = ref.watch(currentPageDataProvider);
  return pageData.calibration;
});
