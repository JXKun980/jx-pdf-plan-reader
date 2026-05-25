import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/geometry/point2d.dart';

enum ToolMode { select, line, arc, circle, rectangle, calibrate }

class MeasurementInteractionState {
  final ToolMode toolMode;
  final Point2D? pendingFirstPoint;
  final Point2D? pendingSecondPoint;
  final bool snapEnabled;
  final double snapTolerance;

  const MeasurementInteractionState({
    this.toolMode = ToolMode.select,
    this.pendingFirstPoint,
    this.pendingSecondPoint,
    this.snapEnabled = true,
    this.snapTolerance = 10.0,
  });

  MeasurementInteractionState copyWith({
    ToolMode? toolMode,
    Point2D? pendingFirstPoint,
    Point2D? pendingSecondPoint,
    bool clearPendingPoint = false,
    bool clearSecondPoint = false,
    bool? snapEnabled,
    double? snapTolerance,
  }) {
    return MeasurementInteractionState(
      toolMode: toolMode ?? this.toolMode,
      pendingFirstPoint:
          clearPendingPoint ? null : (pendingFirstPoint ?? this.pendingFirstPoint),
      pendingSecondPoint:
          clearSecondPoint ? null : (pendingSecondPoint ?? this.pendingSecondPoint),
      snapEnabled: snapEnabled ?? this.snapEnabled,
      snapTolerance: snapTolerance ?? this.snapTolerance,
    );
  }
}

final measurementInteractionProvider = StateNotifierProvider<
    MeasurementInteractionNotifier, MeasurementInteractionState>((ref) {
  return MeasurementInteractionNotifier();
});

class MeasurementInteractionNotifier
    extends StateNotifier<MeasurementInteractionState> {
  MeasurementInteractionNotifier()
      : super(const MeasurementInteractionState());

  void setTool(ToolMode mode) {
    state = state.copyWith(toolMode: mode, clearPendingPoint: true);
  }

  void setFirstPoint(Point2D point) {
    state = state.copyWith(pendingFirstPoint: point);
  }

  void setSecondPoint(Point2D point) {
    state = state.copyWith(pendingSecondPoint: point);
  }

  void clearFirstPoint() {
    state = state.copyWith(clearPendingPoint: true, clearSecondPoint: true);
  }

  void toggleSnap() {
    state = state.copyWith(snapEnabled: !state.snapEnabled);
  }

  void setSnapTolerance(double tolerance) {
    state = state.copyWith(snapTolerance: tolerance);
  }
}
