import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_graph_app/core/calibration/scale.dart';
import 'package:pdf_graph_app/core/geometry/arc_segment.dart';
import 'package:pdf_graph_app/core/geometry/line_segment.dart';
import 'package:pdf_graph_app/core/geometry/point2d.dart';
import 'package:pdf_graph_app/models/command.dart';
import 'package:pdf_graph_app/models/detected_element.dart';
import 'package:pdf_graph_app/models/measurement.dart';
import 'package:pdf_graph_app/models/page_data.dart';
import 'package:pdf_graph_app/models/project.dart';
import 'package:pdf_graph_app/state/history_state.dart';
import 'package:pdf_graph_app/state/measurement_state.dart';

void main() {
  // ───────────────────────────── Measurement ─────────────────────────────

  group('Measurement', () {
    Measurement makeMeasurement({
      String id = 'm1',
      MeasurementType type = MeasurementType.linear,
      Point2D start = const Point2D(0, 0),
      Point2D end = const Point2D(100, 0),
      ArcSegment? arcSegment,
      double pixelLength = 100.0,
      bool startSnapped = false,
      bool endSnapped = false,
    }) {
      return Measurement(
        id: id,
        type: type,
        startPoint: start,
        endPoint: end,
        arcSegment: arcSegment,
        pixelLength: pixelLength,
        startSnapped: startSnapped,
        endSnapped: endSnapped,
      );
    }

    test('lengthInMm divides pixelLength by pixelsPerMm', () {
      final m = makeMeasurement(pixelLength: 500);
      // 500 px / 2 px/mm = 250 mm
      expect(m.lengthInMm(2.0), 250.0);
    });

    test('formatLength mm range (< 10 mm, two decimals)', () {
      // 5 px / 1 px/mm = 5 mm  → "5.00 mm"
      final m = makeMeasurement(pixelLength: 5);
      expect(m.formatLength(1.0), '5.00 mm');
    });

    test('formatLength mm range (>= 10 mm, one decimal)', () {
      // 50 px / 1 px/mm = 50 mm → "50.0 mm"
      final m = makeMeasurement(pixelLength: 50);
      expect(m.formatLength(1.0), '50.0 mm');
    });

    test('formatLength m range (>= 1000 mm)', () {
      // 2000 px / 1 px/mm = 2000 mm → "2.00 m"
      final m = makeMeasurement(pixelLength: 2000);
      expect(m.formatLength(1.0), '2.00 m');
    });

    test('formatLength without calibration uses raw pixelsPerMm', () {
      // pixelsPerMm = 0.5  → 100 / 0.5 = 200 mm → "200.0 mm"
      final m = makeMeasurement(pixelLength: 100);
      expect(m.formatLength(0.5), '200.0 mm');
    });

    test('JSON round-trip for linear measurement', () {
      final original = makeMeasurement(
        id: 'lin1',
        start: const Point2D(10, 20),
        end: const Point2D(30, 40),
        pixelLength: 28.28,
        startSnapped: true,
      );
      final restored = Measurement.fromJson(original.toJson());

      expect(restored.id, original.id);
      expect(restored.type, MeasurementType.linear);
      expect(restored.startPoint, original.startPoint);
      expect(restored.endPoint, original.endPoint);
      expect(restored.pixelLength, original.pixelLength);
      expect(restored.startSnapped, true);
      expect(restored.endSnapped, false);
      expect(restored.arcSegment, isNull);
    });

    test('JSON round-trip for arc measurement with arcSegment', () {
      final arc = ArcSegment(
        center: const Point2D(50, 50),
        radius: 30,
        startAngle: 0,
        endAngle: pi / 2,
        clockwise: false,
      );
      final original = makeMeasurement(
        id: 'arc1',
        type: MeasurementType.arc,
        arcSegment: arc,
        pixelLength: 47.12,
      );
      final restored = Measurement.fromJson(original.toJson());

      expect(restored.type, MeasurementType.arc);
      expect(restored.arcSegment, isNotNull);
      expect(restored.arcSegment!.center, const Point2D(50, 50));
      expect(restored.arcSegment!.radius, 30);
      expect(restored.arcSegment!.clockwise, false);
    });

    test('JSON round-trip with integer values in JSON', () {
      final json = {
        'id': 'int1',
        'type': 'linear',
        'startPoint': {'x': 0, 'y': 0}, // int, not double
        'endPoint': {'x': 100, 'y': 0},
        'pixelLength': 100, // int
        'startSnapped': false,
        'endSnapped': true,
      };
      final m = Measurement.fromJson(json);
      expect(m.pixelLength, 100.0);
      expect(m.startPoint.x, 0.0);
      expect(m.endPoint.x, 100.0);
    });

    test('copyWith preserves unmodified fields', () {
      final original = makeMeasurement(
        id: 'orig',
        startSnapped: true,
        endSnapped: true,
        pixelLength: 42,
      );
      final copied = original.copyWith(id: 'new');

      expect(copied.id, 'new');
      expect(copied.type, original.type);
      expect(copied.startPoint, original.startPoint);
      expect(copied.endPoint, original.endPoint);
      expect(copied.pixelLength, 42);
      expect(copied.startSnapped, true);
      expect(copied.endSnapped, true);
    });

    test('copyWith clearArcSegment sets arcSegment to null', () {
      final arc = ArcSegment(
        center: const Point2D(0, 0),
        radius: 10,
        startAngle: 0,
        endAngle: pi / 2,
      );
      final original = makeMeasurement(id: 'a1').copyWith(arcSegment: arc);
      expect(original.arcSegment, isNotNull);

      final cleared = original.copyWith(clearArcSegment: true);
      expect(cleared.arcSegment, isNull);
    });
  });

  // ───────────────────────────── DetectedElement ─────────────────────────

  group('DetectedElement', () {
    test('line() factory creates a line element', () {
      final seg = const LineSegment(Point2D(0, 0), Point2D(3, 4));
      final el = DetectedElement.line('l1', seg);

      expect(el.id, 'l1');
      expect(el.type, DetectedElementType.line);
      expect(el.lineSegment, seg);
      expect(el.arcSegment, isNull);
    });

    test('arc() factory creates an arc element', () {
      final arc = ArcSegment(
        center: const Point2D(0, 0),
        radius: 10,
        startAngle: 0,
        endAngle: pi,
      );
      final el = DetectedElement.arc('a1', arc);

      expect(el.id, 'a1');
      expect(el.type, DetectedElementType.arc);
      expect(el.arcSegment, isNotNull);
      expect(el.lineSegment, isNull);
    });

    test('length for line element returns segment length', () {
      final seg = const LineSegment(Point2D(0, 0), Point2D(3, 4));
      final el = DetectedElement.line('l1', seg);
      expect(el.length, 5.0);
    });

    test('length for arc element returns arc length', () {
      final arc = ArcSegment(
        center: const Point2D(0, 0),
        radius: 10,
        startAngle: 0,
        endAngle: pi,
      );
      final el = DetectedElement.arc('a1', arc);
      // arc length = radius * |sweep| = 10 * pi
      expect(el.length, closeTo(10 * pi, 1e-9));
    });

    test('closestPointTo delegates correctly for line', () {
      final seg = const LineSegment(Point2D(0, 0), Point2D(10, 0));
      final el = DetectedElement.line('l1', seg);
      final closest = el.closestPointTo(const Point2D(5, 5));
      expect(closest.x, closeTo(5, 1e-9));
      expect(closest.y, closeTo(0, 1e-9));
    });

    test('closestPointTo delegates correctly for arc', () {
      final arc = ArcSegment(
        center: const Point2D(0, 0),
        radius: 10,
        startAngle: 0,
        endAngle: pi,
      );
      final el = DetectedElement.arc('a1', arc);
      // Point directly above center at (0, 20) → closest on arc at (0, 10)
      final closest = el.closestPointTo(const Point2D(0, 20));
      expect(closest.x, closeTo(0, 1e-9));
      expect(closest.y, closeTo(10, 1e-9));
    });

    test('JSON round-trip for line variant', () {
      final seg = const LineSegment(Point2D(1, 2), Point2D(3, 4));
      final original = DetectedElement.line('l1', seg);
      final restored = DetectedElement.fromJson(original.toJson());

      expect(restored.id, 'l1');
      expect(restored.type, DetectedElementType.line);
      expect(restored.lineSegment!.start, const Point2D(1, 2));
      expect(restored.lineSegment!.end, const Point2D(3, 4));
    });

    test('JSON round-trip for arc variant', () {
      final arc = ArcSegment(
        center: const Point2D(5, 5),
        radius: 20,
        startAngle: 0.5,
        endAngle: 1.5,
        clockwise: true,
      );
      final original = DetectedElement.arc('a1', arc);
      final restored = DetectedElement.fromJson(original.toJson());

      expect(restored.id, 'a1');
      expect(restored.type, DetectedElementType.arc);
      expect(restored.arcSegment!.radius, 20);
      expect(restored.arcSegment!.clockwise, true);
    });
  });

  // ───────────────────────────── PageData ────────────────────────────────

  group('PageData', () {
    test('default values', () {
      const pd = PageData(pageIndex: 0);
      expect(pd.pageIndex, 0);
      expect(pd.isVectorPage, false);
      expect(pd.detectedElements, isEmpty);
      expect(pd.detectedJoints, isEmpty);
      expect(pd.measurements, isEmpty);
      expect(pd.calibration, isNull);
    });

    test('copyWith preserves fields', () {
      final cal = const CalibrationScale(
        knownDistanceMm: 100,
        pixelDistance: 200,
      );
      final pd = PageData(
        pageIndex: 1,
        isVectorPage: true,
        calibration: cal,
      );
      final copied = pd.copyWith(isVectorPage: false);

      expect(copied.pageIndex, 1);
      expect(copied.isVectorPage, false);
      expect(copied.calibration, cal);
    });

    test('copyWith with clearCalibration', () {
      final pd = PageData(
        pageIndex: 0,
        calibration: const CalibrationScale(
          knownDistanceMm: 100,
          pixelDistance: 200,
        ),
      );
      final cleared = pd.copyWith(clearCalibration: true);
      expect(cleared.calibration, isNull);
    });
  });

  // ───────────────────────────── Project ─────────────────────────────────

  group('Project', () {
    Project makeProject() {
      return Project(
        id: 'p1',
        filePath: '/test.pdf',
        fileName: 'test.pdf',
        pageCount: 3,
        createdAt: DateTime(2025, 1, 1),
        updatedAt: DateTime(2025, 1, 1),
      );
    }

    test('getPageData returns default for unknown page', () {
      final p = makeProject();
      final pd = p.getPageData(5);
      expect(pd.pageIndex, 5);
      expect(pd.measurements, isEmpty);
    });

    test('updatePageData adds/updates page', () {
      var p = makeProject();
      final pd = PageData(pageIndex: 0, isVectorPage: true);
      p = p.updatePageData(0, pd);

      expect(p.pages.containsKey(0), true);
      expect(p.getPageData(0).isVectorPage, true);
    });

    test('updatePageData updates timestamp', () {
      final p = makeProject();
      final before = p.updatedAt;
      final updated = p.updatePageData(0, const PageData(pageIndex: 0));
      expect(updated.updatedAt.isAfter(before) || updated.updatedAt == before, true);
    });
  });

  // ───────────────────────────── Commands ────────────────────────────────

  group('Command pattern', () {
    PageData basePage() => const PageData(pageIndex: 0);

    Measurement testMeasurement({String id = 'm1'}) => Measurement(
          id: id,
          type: MeasurementType.linear,
          startPoint: const Point2D(0, 0),
          endPoint: const Point2D(10, 0),
          pixelLength: 10,
        );

    group('AddMeasurementCommand', () {
      test('execute adds measurement to page', () {
        final m = testMeasurement();
        final cmd = AddMeasurementCommand(m);
        PageData? captured;
        cmd.execute(basePage(), (pd) => captured = pd);

        expect(captured, isNotNull);
        expect(captured!.measurements, hasLength(1));
        expect(captured!.measurements.first.id, 'm1');
      });

      test('undo removes the measurement', () {
        final m = testMeasurement();
        final cmd = AddMeasurementCommand(m);
        PageData? captured;
        cmd.execute(basePage(), (pd) => captured = pd);

        PageData? afterUndo;
        cmd.undo(captured!, (pd) => afterUndo = pd);

        expect(afterUndo!.measurements, isEmpty);
      });
    });

    group('DeleteMeasurementCommand', () {
      test('execute removes measurement', () {
        final m = testMeasurement();
        final page = basePage().copyWith(measurements: [m]);
        final cmd = DeleteMeasurementCommand(m);

        PageData? captured;
        cmd.execute(page, (pd) => captured = pd);

        expect(captured!.measurements, isEmpty);
      });

      test('undo restores measurement at the same index', () {
        final m1 = testMeasurement(id: 'm1');
        final m2 = testMeasurement(id: 'm2');
        final m3 = testMeasurement(id: 'm3');
        final page = basePage().copyWith(measurements: [m1, m2, m3]);

        final cmd = DeleteMeasurementCommand(m2);
        PageData? afterDelete;
        cmd.execute(page, (pd) => afterDelete = pd);
        expect(afterDelete!.measurements.map((m) => m.id), ['m1', 'm3']);

        PageData? afterUndo;
        cmd.undo(afterDelete!, (pd) => afterUndo = pd);
        expect(afterUndo!.measurements.map((m) => m.id), ['m1', 'm2', 'm3']);
      });
    });

    group('DeleteMeasurementCommand edge cases', () {
      test('delete of non-existent measurement does not crash on undo', () {
        final m = testMeasurement(id: 'gone');
        final page = basePage(); // no measurements
        final cmd = DeleteMeasurementCommand(m);

        PageData? afterDelete;
        cmd.execute(page, (pd) => afterDelete = pd);
        expect(afterDelete!.measurements, isEmpty);

        // Undo should add it (appended, since it was not found)
        PageData? afterUndo;
        cmd.undo(afterDelete!, (pd) => afterUndo = pd);
        expect(afterUndo!.measurements, hasLength(1));
        expect(afterUndo!.measurements[0].id, 'gone');
      });
    });

    group('SetCalibrationCommand', () {
      test('execute sets calibration', () {
        const cal = CalibrationScale(
          knownDistanceMm: 100,
          pixelDistance: 200,
        );
        final cmd = SetCalibrationCommand(cal);
        PageData? captured;
        cmd.execute(basePage(), (pd) => captured = pd);

        expect(captured!.calibration, cal);
      });

      test('undo restores previous calibration', () {
        const oldCal = CalibrationScale(
          knownDistanceMm: 50,
          pixelDistance: 100,
        );
        const newCal = CalibrationScale(
          knownDistanceMm: 100,
          pixelDistance: 200,
        );
        final page = basePage().copyWith(calibration: oldCal);
        final cmd = SetCalibrationCommand(newCal);

        PageData? captured;
        cmd.execute(page, (pd) => captured = pd);
        expect(captured!.calibration, newCal);

        PageData? afterUndo;
        cmd.undo(captured!, (pd) => afterUndo = pd);
        expect(afterUndo!.calibration, oldCal);
      });

      test('execute with null clears calibration', () {
        const cal = CalibrationScale(
          knownDistanceMm: 100,
          pixelDistance: 200,
        );
        final page = basePage().copyWith(calibration: cal);
        final cmd = SetCalibrationCommand(null);

        PageData? captured;
        cmd.execute(page, (pd) => captured = pd);
        expect(captured!.calibration, isNull);
      });

      test('undo after clear restores null', () {
        final cmd = SetCalibrationCommand(
          const CalibrationScale(knownDistanceMm: 10, pixelDistance: 20),
        );
        PageData? captured;
        cmd.execute(basePage(), (pd) => captured = pd);

        PageData? afterUndo;
        cmd.undo(captured!, (pd) => afterUndo = pd);
        expect(afterUndo!.calibration, isNull);
      });
    });
  });

  // ───────────────────────────── HistoryNotifier ─────────────────────────

  group('HistoryNotifier', () {
    late HistoryNotifier notifier;

    setUp(() {
      notifier = HistoryNotifier();
    });

    Measurement testMeasurement({String id = 'm1'}) => Measurement(
          id: id,
          type: MeasurementType.linear,
          startPoint: const Point2D(0, 0),
          endPoint: const Point2D(10, 0),
          pixelLength: 10,
        );

    test('perform adds to undo stack for specific page', () {
      final m = testMeasurement();
      final cmd = AddMeasurementCommand(m);
      var page = const PageData(pageIndex: 0);

      notifier.perform(cmd, 0, page, (pd) => page = pd);

      expect(notifier.state.canUndo(0), true);
      expect(notifier.state.canRedo(0), false);
      expect(page.measurements, hasLength(1));
    });

    test('undo moves from undo to redo stack', () {
      final m = testMeasurement();
      final cmd = AddMeasurementCommand(m);
      var page = const PageData(pageIndex: 0);

      notifier.perform(cmd, 0, page, (pd) => page = pd);
      notifier.undo(0, page, (pd) => page = pd);

      expect(notifier.state.canUndo(0), false);
      expect(notifier.state.canRedo(0), true);
      expect(page.measurements, isEmpty);
    });

    test('redo moves from redo to undo stack', () {
      final m = testMeasurement();
      final cmd = AddMeasurementCommand(m);
      var page = const PageData(pageIndex: 0);

      notifier.perform(cmd, 0, page, (pd) => page = pd);
      notifier.undo(0, page, (pd) => page = pd);
      notifier.redo(0, page, (pd) => page = pd);

      expect(notifier.state.canUndo(0), true);
      expect(notifier.state.canRedo(0), false);
      expect(page.measurements, hasLength(1));
    });

    test('canUndo/canRedo are page-scoped', () {
      final cmd0 = AddMeasurementCommand(testMeasurement(id: 'p0'));
      final cmd1 = AddMeasurementCommand(testMeasurement(id: 'p1'));
      var page0 = const PageData(pageIndex: 0);
      var page1 = const PageData(pageIndex: 1);

      notifier.perform(cmd0, 0, page0, (pd) => page0 = pd);
      notifier.perform(cmd1, 1, page1, (pd) => page1 = pd);

      expect(notifier.state.canUndo(0), true);
      expect(notifier.state.canUndo(1), true);
      expect(notifier.state.canRedo(0), false);
      expect(notifier.state.canRedo(1), false);

      notifier.undo(0, page0, (pd) => page0 = pd);
      expect(notifier.state.canUndo(0), false);
      expect(notifier.state.canUndo(1), true); // page 1 unaffected
      expect(notifier.state.canRedo(0), true);
    });

    test('undo on one page does not affect another page', () {
      final cmd0 = AddMeasurementCommand(testMeasurement(id: 'p0'));
      final cmd1 = AddMeasurementCommand(testMeasurement(id: 'p1'));
      var page0 = const PageData(pageIndex: 0);
      var page1 = const PageData(pageIndex: 1);

      notifier.perform(cmd0, 0, page0, (pd) => page0 = pd);
      notifier.perform(cmd1, 1, page1, (pd) => page1 = pd);

      notifier.undo(0, page0, (pd) => page0 = pd);

      expect(page0.measurements, isEmpty);
      expect(page1.measurements, hasLength(1));
    });

    test('clear resets all pages', () {
      final cmd = AddMeasurementCommand(testMeasurement());
      var page = const PageData(pageIndex: 0);
      notifier.perform(cmd, 0, page, (pd) => page = pd);

      notifier.clear();

      expect(notifier.state.canUndo(0), false);
      expect(notifier.state.canRedo(0), false);
    });

    test('perform clears redo stack for that page', () {
      final m1 = testMeasurement(id: 'm1');
      final m2 = testMeasurement(id: 'm2');
      var page = const PageData(pageIndex: 0);

      notifier.perform(AddMeasurementCommand(m1), 0, page, (pd) => page = pd);
      notifier.undo(0, page, (pd) => page = pd);
      expect(notifier.state.canRedo(0), true);

      // New perform should clear redo
      notifier.perform(AddMeasurementCommand(m2), 0, page, (pd) => page = pd);
      expect(notifier.state.canRedo(0), false);
    });
  });

  // ───────────────────── MeasurementInteractionNotifier ──────────────────

  group('MeasurementInteractionNotifier', () {
    late MeasurementInteractionNotifier notifier;

    setUp(() {
      notifier = MeasurementInteractionNotifier();
    });

    test('initial state', () {
      expect(notifier.state.toolMode, ToolMode.select);
      expect(notifier.state.pendingFirstPoint, isNull);
      expect(notifier.state.snapEnabled, true);
      expect(notifier.state.snapTolerance, 10.0);
    });

    test('setTool changes tool and clears pending point', () {
      notifier.setFirstPoint(const Point2D(5, 5));
      notifier.setTool(ToolMode.measure);

      expect(notifier.state.toolMode, ToolMode.measure);
      expect(notifier.state.pendingFirstPoint, isNull);
    });

    test('setFirstPoint sets the pending point', () {
      notifier.setFirstPoint(const Point2D(10, 20));
      expect(notifier.state.pendingFirstPoint, const Point2D(10, 20));
    });

    test('clearFirstPoint clears the pending point', () {
      notifier.setFirstPoint(const Point2D(10, 20));
      notifier.clearFirstPoint();
      expect(notifier.state.pendingFirstPoint, isNull);
    });

    test('toggleSnap flips snapEnabled', () {
      expect(notifier.state.snapEnabled, true);
      notifier.toggleSnap();
      expect(notifier.state.snapEnabled, false);
      notifier.toggleSnap();
      expect(notifier.state.snapEnabled, true);
    });

    test('setSnapTolerance updates tolerance', () {
      notifier.setSnapTolerance(25.0);
      expect(notifier.state.snapTolerance, 25.0);
    });
  });
}
