import 'measurement.dart';
import 'page_data.dart';
import '../core/calibration/scale.dart';

/// Base class for undoable commands (Command Pattern).
abstract class Command {
  String get description;
  void execute(PageData page, void Function(PageData) updatePage);
  void undo(PageData page, void Function(PageData) updatePage);
}

class AddMeasurementCommand extends Command {
  final Measurement measurement;

  AddMeasurementCommand(this.measurement);

  @override
  String get description => 'Add measurement';

  @override
  void execute(PageData page, void Function(PageData) updatePage) {
    updatePage(page.copyWith(
      measurements: [...page.measurements, measurement],
    ));
  }

  @override
  void undo(PageData page, void Function(PageData) updatePage) {
    updatePage(page.copyWith(
      measurements: page.measurements.where((m) => m.id != measurement.id).toList(),
    ));
  }
}

class DeleteMeasurementCommand extends Command {
  final Measurement measurement;
  int? _previousIndex;

  DeleteMeasurementCommand(this.measurement);

  @override
  String get description => 'Delete measurement';

  @override
  void execute(PageData page, void Function(PageData) updatePage) {
    final idx = page.measurements.indexWhere((m) => m.id == measurement.id);
    _previousIndex = idx >= 0 ? idx : null;
    updatePage(page.copyWith(
      measurements: page.measurements.where((m) => m.id != measurement.id).toList(),
    ));
  }

  @override
  void undo(PageData page, void Function(PageData) updatePage) {
    final measurements = List<Measurement>.from(page.measurements);
    final index = _previousIndex ?? measurements.length;
    measurements.insert(index.clamp(0, measurements.length), measurement);
    updatePage(page.copyWith(measurements: measurements));
  }
}

class SetCalibrationCommand extends Command {
  final CalibrationScale? newCalibration;
  CalibrationScale? _previousCalibration;

  SetCalibrationCommand(this.newCalibration);

  @override
  String get description => newCalibration != null ? 'Set calibration' : 'Clear calibration';

  @override
  void execute(PageData page, void Function(PageData) updatePage) {
    _previousCalibration = page.calibration;
    updatePage(page.copyWith(
      calibration: newCalibration,
      clearCalibration: newCalibration == null,
    ));
  }

  @override
  void undo(PageData page, void Function(PageData) updatePage) {
    updatePage(page.copyWith(
      calibration: _previousCalibration,
      clearCalibration: _previousCalibration == null,
    ));
  }
}
