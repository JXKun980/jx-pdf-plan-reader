import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_graph_app/core/geometry/point2d.dart';
import 'package:pdf_graph_app/core/geometry/line_segment.dart';
import 'package:pdf_graph_app/core/geometry/arc_segment.dart';
import 'package:pdf_graph_app/core/geometry/intersections.dart';
import 'package:pdf_graph_app/core/calibration/scale.dart';

void main() {
  // ─── Point2D ───────────────────────────────────────────────────────

  group('Point2D', () {
    group('distanceTo', () {
      test('returns correct distance between two points', () {
        final a = Point2D(0, 0);
        final b = Point2D(3, 4);
        expect(a.distanceTo(b), closeTo(5.0, 0.001));
      });

      test('returns 0 for same point', () {
        final p = Point2D(7, 11);
        expect(p.distanceTo(p), equals(0.0));
      });

      test('is symmetric', () {
        final a = Point2D(1, 2);
        final b = Point2D(4, 6);
        expect(a.distanceTo(b), closeTo(b.distanceTo(a), 0.001));
      });
    });

    group('operators', () {
      test('+ adds components', () {
        final result = Point2D(1, 2) + Point2D(3, 4);
        expect(result.x, closeTo(4, 0.001));
        expect(result.y, closeTo(6, 0.001));
      });

      test('- subtracts components', () {
        final result = Point2D(5, 7) - Point2D(2, 3);
        expect(result.x, closeTo(3, 0.001));
        expect(result.y, closeTo(4, 0.001));
      });

      test('* scales components', () {
        final result = Point2D(3, 4) * 2.0;
        expect(result.x, closeTo(6, 0.001));
        expect(result.y, closeTo(8, 0.001));
      });

      test('* by zero yields origin', () {
        final result = Point2D(3, 4) * 0.0;
        expect(result.x, closeTo(0, 0.001));
        expect(result.y, closeTo(0, 0.001));
      });
    });

    group('midpointTo', () {
      test('returns midpoint', () {
        final mid = Point2D(0, 0).midpointTo(Point2D(10, 10));
        expect(mid.x, closeTo(5, 0.001));
        expect(mid.y, closeTo(5, 0.001));
      });

      test('midpoint of same point is itself', () {
        final p = Point2D(3, 7);
        final mid = p.midpointTo(p);
        expect(mid.x, closeTo(3, 0.001));
        expect(mid.y, closeTo(7, 0.001));
      });
    });

    group('angleTo', () {
      test('horizontal right is 0', () {
        expect(Point2D(0, 0).angleTo(Point2D(1, 0)), closeTo(0, 0.001));
      });

      test('vertical down is pi/2', () {
        expect(Point2D(0, 0).angleTo(Point2D(0, 1)), closeTo(pi / 2, 0.001));
      });

      test('horizontal left is pi', () {
        expect(
          Point2D(0, 0).angleTo(Point2D(-1, 0)),
          closeTo(pi, 0.001),
        );
      });

      test('vertical up is -pi/2', () {
        expect(
          Point2D(0, 0).angleTo(Point2D(0, -1)),
          closeTo(-pi / 2, 0.001),
        );
      });

      test('diagonal 45 degrees is pi/4', () {
        expect(
          Point2D(0, 0).angleTo(Point2D(1, 1)),
          closeTo(pi / 4, 0.001),
        );
      });
    });

    group('equality and hashCode', () {
      test('equal points are ==', () {
        expect(Point2D(1, 2), equals(Point2D(1, 2)));
      });

      test('different points are not ==', () {
        expect(Point2D(1, 2) == Point2D(3, 4), isFalse);
      });

      test('equal points have same hashCode', () {
        expect(Point2D(1, 2).hashCode, equals(Point2D(1, 2).hashCode));
      });

      test('identical returns true', () {
        final p = Point2D(1, 2);
        expect(p == p, isTrue);
      });
    });

    group('JSON round-trip', () {
      test('serializes and deserializes', () {
        final original = Point2D(3.5, -7.25);
        final json = original.toJson();
        final restored = Point2D.fromJson(json);
        expect(restored.x, closeTo(original.x, 0.001));
        expect(restored.y, closeTo(original.y, 0.001));
      });

      test('handles integer values in JSON', () {
        final restored = Point2D.fromJson({'x': 10, 'y': 20});
        expect(restored.x, closeTo(10, 0.001));
        expect(restored.y, closeTo(20, 0.001));
      });
    });
  });

  // ─── LineSegment ───────────────────────────────────────────────────

  group('LineSegment', () {
    group('length', () {
      test('returns correct length', () {
        final seg = LineSegment(Point2D(0, 0), Point2D(3, 4));
        expect(seg.length, closeTo(5, 0.001));
      });

      test('zero-length degenerate segment', () {
        final seg = LineSegment(Point2D(5, 5), Point2D(5, 5));
        expect(seg.length, closeTo(0, 0.001));
      });
    });

    group('midpoint', () {
      test('returns midpoint of segment', () {
        final seg = LineSegment(Point2D(0, 0), Point2D(10, 6));
        final mid = seg.midpoint;
        expect(mid.x, closeTo(5, 0.001));
        expect(mid.y, closeTo(3, 0.001));
      });
    });

    group('closestPointTo', () {
      test('point projects onto segment interior', () {
        final seg = LineSegment(Point2D(0, 0), Point2D(10, 0));
        final closest = seg.closestPointTo(Point2D(5, 3));
        expect(closest.x, closeTo(5, 0.001));
        expect(closest.y, closeTo(0, 0.001));
      });

      test('point beyond start clamps to start', () {
        final seg = LineSegment(Point2D(0, 0), Point2D(10, 0));
        final closest = seg.closestPointTo(Point2D(-5, 3));
        expect(closest.x, closeTo(0, 0.001));
        expect(closest.y, closeTo(0, 0.001));
      });

      test('point beyond end clamps to end', () {
        final seg = LineSegment(Point2D(0, 0), Point2D(10, 0));
        final closest = seg.closestPointTo(Point2D(15, 3));
        expect(closest.x, closeTo(10, 0.001));
        expect(closest.y, closeTo(0, 0.001));
      });

      test('perpendicular projection from diagonal segment', () {
        final seg = LineSegment(Point2D(0, 0), Point2D(10, 10));
        final closest = seg.closestPointTo(Point2D(0, 10));
        expect(closest.x, closeTo(5, 0.001));
        expect(closest.y, closeTo(5, 0.001));
      });

      test('degenerate segment returns start', () {
        final seg = LineSegment(Point2D(3, 3), Point2D(3, 3));
        final closest = seg.closestPointTo(Point2D(7, 9));
        expect(closest.x, closeTo(3, 0.001));
        expect(closest.y, closeTo(3, 0.001));
      });
    });

    group('distanceToPoint', () {
      test('returns perpendicular distance', () {
        final seg = LineSegment(Point2D(0, 0), Point2D(10, 0));
        expect(seg.distanceToPoint(Point2D(5, 4)), closeTo(4, 0.001));
      });

      test('returns distance to nearest endpoint when beyond segment', () {
        final seg = LineSegment(Point2D(0, 0), Point2D(10, 0));
        expect(seg.distanceToPoint(Point2D(-3, 4)), closeTo(5, 0.001));
      });
    });

    group('intersectionWith', () {
      test('two crossing segments return intersection', () {
        final a = LineSegment(Point2D(0, 0), Point2D(10, 10));
        final b = LineSegment(Point2D(0, 10), Point2D(10, 0));
        final p = a.intersectionWith(b);
        expect(p, isNotNull);
        expect(p!.x, closeTo(5, 0.001));
        expect(p.y, closeTo(5, 0.001));
      });

      test('parallel segments return null', () {
        final a = LineSegment(Point2D(0, 0), Point2D(10, 0));
        final b = LineSegment(Point2D(0, 5), Point2D(10, 5));
        expect(a.intersectionWith(b), isNull);
      });

      test('T-junction at endpoint', () {
        final a = LineSegment(Point2D(0, 0), Point2D(10, 0));
        final b = LineSegment(Point2D(5, -5), Point2D(5, 5));
        final p = a.intersectionWith(b);
        expect(p, isNotNull);
        expect(p!.x, closeTo(5, 0.001));
        expect(p.y, closeTo(0, 0.001));
      });

      test('collinear overlapping segments return null (treated as parallel)', () {
        final a = LineSegment(Point2D(0, 0), Point2D(10, 0));
        final b = LineSegment(Point2D(5, 0), Point2D(15, 0));
        expect(a.intersectionWith(b), isNull);
      });

      test('non-intersecting segments return null', () {
        final a = LineSegment(Point2D(0, 0), Point2D(1, 0));
        final b = LineSegment(Point2D(5, 5), Point2D(6, 5));
        expect(a.intersectionWith(b), isNull);
      });
    });

    group('lineIntersectionWith', () {
      test('finds intersection of infinite lines beyond segment bounds', () {
        final a = LineSegment(Point2D(0, 0), Point2D(1, 1));
        final b = LineSegment(Point2D(10, 0), Point2D(10, 1));
        final p = a.lineIntersectionWith(b);
        expect(p, isNotNull);
        expect(p!.x, closeTo(10, 0.001));
        expect(p.y, closeTo(10, 0.001));
      });

      test('parallel infinite lines return null', () {
        final a = LineSegment(Point2D(0, 0), Point2D(10, 0));
        final b = LineSegment(Point2D(0, 5), Point2D(10, 5));
        expect(a.lineIntersectionWith(b), isNull);
      });
    });

    group('JSON round-trip', () {
      test('serializes and deserializes', () {
        final original = LineSegment(Point2D(1, 2), Point2D(3, 4));
        final json = original.toJson();
        final restored = LineSegment.fromJson(json);
        expect(restored.start.x, closeTo(1, 0.001));
        expect(restored.start.y, closeTo(2, 0.001));
        expect(restored.end.x, closeTo(3, 0.001));
        expect(restored.end.y, closeTo(4, 0.001));
      });
    });
  });

  // ─── ArcSegment ────────────────────────────────────────────────────

  group('ArcSegment', () {
    group('startPoint and endPoint', () {
      test('startPoint lies on circle at startAngle', () {
        final arc = ArcSegment(
          center: Point2D(0, 0),
          radius: 5,
          startAngle: 0,
          endAngle: pi / 2,
        );
        expect(arc.startPoint.x, closeTo(5, 0.001));
        expect(arc.startPoint.y, closeTo(0, 0.001));
      });

      test('endPoint lies on circle at endAngle', () {
        final arc = ArcSegment(
          center: Point2D(0, 0),
          radius: 5,
          startAngle: 0,
          endAngle: pi / 2,
        );
        expect(arc.endPoint.x, closeTo(0, 0.001));
        expect(arc.endPoint.y, closeTo(5, 0.001));
      });
    });

    group('sweepAngle', () {
      test('CCW quarter circle', () {
        final arc = ArcSegment(
          center: Point2D(0, 0),
          radius: 5,
          startAngle: 0,
          endAngle: pi / 2,
          clockwise: false,
        );
        expect(arc.sweepAngle, closeTo(pi / 2, 0.001));
      });

      test('CW quarter circle', () {
        final arc = ArcSegment(
          center: Point2D(0, 0),
          radius: 5,
          startAngle: 0,
          endAngle: pi / 2,
          clockwise: true,
        );
        // CW from 0 to pi/2: sweep should be negative, wrapping around
        expect(arc.sweepAngle, closeTo(-3 * pi / 2, 0.001));
      });

      test('CCW wrapping past 2*pi', () {
        final arc = ArcSegment(
          center: Point2D(0, 0),
          radius: 5,
          startAngle: 3 * pi / 2,
          endAngle: pi / 4,
          clockwise: false,
        );
        // From 3pi/2 to pi/4 CCW wraps forward
        final expected = pi / 4 - 3 * pi / 2 + 2 * pi;
        expect(arc.sweepAngle, closeTo(expected, 0.001));
      });
    });

    group('arcLength', () {
      test('quarter circle', () {
        final arc = ArcSegment(
          center: Point2D(0, 0),
          radius: 10,
          startAngle: 0,
          endAngle: pi / 2,
          clockwise: false,
        );
        expect(arc.arcLength, closeTo(10 * pi / 2, 0.001));
      });
    });

    group('closestPointTo', () {
      test('point radially outward from arc projects onto arc', () {
        final arc = ArcSegment(
          center: Point2D(0, 0),
          radius: 10,
          startAngle: 0,
          endAngle: pi / 2,
          clockwise: false,
        );
        // Point at angle pi/4 but radius 20 — should project to radius 10
        final p = Point2D(20 * cos(pi / 4), 20 * sin(pi / 4));
        final closest = arc.closestPointTo(p);
        expect(closest.x, closeTo(10 * cos(pi / 4), 0.001));
        expect(closest.y, closeTo(10 * sin(pi / 4), 0.001));
      });

      test('point outside arc span returns nearest endpoint', () {
        final arc = ArcSegment(
          center: Point2D(0, 0),
          radius: 10,
          startAngle: 0,
          endAngle: pi / 2,
          clockwise: false,
        );
        // Point at angle pi (180°) — outside the 0..pi/2 arc
        final p = Point2D(-20, 0);
        final closest = arc.closestPointTo(p);
        // Should be one of the endpoints; endPoint at (0,10) is closer to (-20,0)
        final dStart = p.distanceTo(arc.startPoint);
        final dEnd = p.distanceTo(arc.endPoint);
        if (dStart <= dEnd) {
          expect(closest.x, closeTo(arc.startPoint.x, 0.001));
          expect(closest.y, closeTo(arc.startPoint.y, 0.001));
        } else {
          expect(closest.x, closeTo(arc.endPoint.x, 0.001));
          expect(closest.y, closeTo(arc.endPoint.y, 0.001));
        }
      });
    });

    group('fromThreePoints', () {
      test('valid circle through three points', () {
        // Points on a unit circle centred at origin
        final p1 = Point2D(1, 0);
        final p2 = Point2D(0, 1);
        final p3 = Point2D(-1, 0);
        final arc = ArcSegment.fromThreePoints(p1, p2, p3);
        expect(arc.center.x, closeTo(0, 0.001));
        expect(arc.center.y, closeTo(0, 0.001));
        expect(arc.radius, closeTo(1, 0.001));
      });

      test('collinear points produce infinite radius', () {
        final arc = ArcSegment.fromThreePoints(
          Point2D(0, 0),
          Point2D(5, 0),
          Point2D(10, 0),
        );
        expect(arc.radius, equals(double.infinity));
      });
    });

    group('fromEndpointsAndRadius', () {
      test('creates arc with valid parameters', () {
        final arc = ArcSegment.fromEndpointsAndRadius(
          Point2D(0, 0),
          Point2D(10, 0),
          10,
        );
        expect(arc.radius, closeTo(10, 0.001));
        expect(arc.startPoint.x, closeTo(0, 0.001));
        expect(arc.startPoint.y, closeTo(0, 0.001));
        expect(arc.endPoint.x, closeTo(10, 0.001));
        expect(arc.endPoint.y, closeTo(0, 0.001));
      });

      test('minimum radius when points are too far apart', () {
        // Distance = 10, radius = 3 → radius is bumped to 5 (halfDist)
        final arc = ArcSegment.fromEndpointsAndRadius(
          Point2D(0, 0),
          Point2D(10, 0),
          3,
        );
        expect(arc.radius, closeTo(5, 0.001));
      });

      test('same point throws ArgumentError', () {
        expect(
          () => ArcSegment.fromEndpointsAndRadius(
            Point2D(5, 5),
            Point2D(5, 5),
            10,
          ),
          throwsArgumentError,
        );
      });

      test('zero radius throws ArgumentError', () {
        expect(
          () => ArcSegment.fromEndpointsAndRadius(
            Point2D(0, 0),
            Point2D(10, 0),
            0,
          ),
          throwsArgumentError,
        );
      });

      test('negative radius throws ArgumentError', () {
        expect(
          () => ArcSegment.fromEndpointsAndRadius(
            Point2D(0, 0),
            Point2D(10, 0),
            -5,
          ),
          throwsArgumentError,
        );
      });
    });

    group('JSON round-trip', () {
      test('serializes and deserializes', () {
        final original = ArcSegment(
          center: Point2D(1, 2),
          radius: 5,
          startAngle: 0.5,
          endAngle: 1.5,
          clockwise: true,
        );
        final json = original.toJson();
        final restored = ArcSegment.fromJson(json);
        expect(restored.center.x, closeTo(1, 0.001));
        expect(restored.center.y, closeTo(2, 0.001));
        expect(restored.radius, closeTo(5, 0.001));
        expect(restored.startAngle, closeTo(0.5, 0.001));
        expect(restored.endAngle, closeTo(1.5, 0.001));
        expect(restored.clockwise, isTrue);
      });

      test('defaults clockwise to false', () {
        final arc = ArcSegment(
          center: Point2D(0, 0),
          radius: 1,
          startAngle: 0,
          endAngle: 1,
        );
        final restored = ArcSegment.fromJson(arc.toJson());
        expect(restored.clockwise, isFalse);
      });
    });
  });

  // ─── IntersectionFinder ────────────────────────────────────────────

  group('IntersectionFinder', () {
    group('findLineJoints', () {
      test('two lines sharing an endpoint produce one joint', () {
        final lines = [
          LineSegment(Point2D(0, 0), Point2D(10, 0)),
          LineSegment(Point2D(10, 0), Point2D(10, 10)),
        ];
        final joints = IntersectionFinder.findLineJoints(lines);
        expect(joints.length, equals(1));
        expect(joints[0].point.x, closeTo(10, 1.5));
        expect(joints[0].point.y, closeTo(0, 1.5));
        expect(joints[0].connectedElementIndices, containsAll([0, 1]));
      });

      test('two crossing lines produce a joint at crossing', () {
        final lines = [
          LineSegment(Point2D(0, 0), Point2D(10, 10)),
          LineSegment(Point2D(0, 10), Point2D(10, 0)),
        ];
        final joints = IntersectionFinder.findLineJoints(lines);
        // Should have at least 1 joint at the crossing point (5,5)
        final crossingJoints = joints.where((j) =>
            j.point.distanceTo(Point2D(5, 5)) < 1.5 &&
            j.connectedElementIndices.contains(0) &&
            j.connectedElementIndices.contains(1));
        expect(crossingJoints, isNotEmpty);
      });

      test('three lines meeting at the same point produce one joint', () {
        final shared = Point2D(5, 5);
        final lines = [
          LineSegment(Point2D(0, 0), shared),
          LineSegment(shared, Point2D(10, 5)),
          LineSegment(shared, Point2D(5, 10)),
        ];
        final joints = IntersectionFinder.findLineJoints(lines);
        final sharedJoint = joints.where(
          (j) => j.point.distanceTo(shared) < 1.5,
        );
        expect(sharedJoint, isNotEmpty);
        expect(
          sharedJoint.first.connectedElementIndices,
          containsAll([0, 1, 2]),
        );
      });

      test('no intersections when lines are far apart', () {
        final lines = [
          LineSegment(Point2D(0, 0), Point2D(1, 0)),
          LineSegment(Point2D(100, 100), Point2D(101, 100)),
        ];
        final joints = IntersectionFinder.findLineJoints(lines);
        expect(joints, isEmpty);
      });
    });

    group('findAllJoints', () {
      test('two arcs sharing an endpoint produce a joint', () {
        // Two arcs meeting at (10, 0)
        final arc1 = ArcSegment(
          center: Point2D(0, 0),
          radius: 10,
          startAngle: -pi / 2,
          endAngle: 0,
          clockwise: false,
        );
        final arc2 = ArcSegment(
          center: Point2D(0, 0),
          radius: 10,
          startAngle: 0,
          endAngle: pi / 2,
          clockwise: false,
        );
        // No lines, two arcs — arc indices are 0 and 1
        final joints = IntersectionFinder.findAllJoints([], [arc1, arc2]);
        final matchingJoints = joints.where(
          (j) => j.point.distanceTo(Point2D(10, 0)) < 1.5,
        );
        expect(matchingJoints, isNotEmpty);
        expect(
          matchingJoints.first.connectedElementIndices,
          containsAll([0, 1]),
        );
      });

      test('no joints when elements do not meet', () {
        final arc = ArcSegment(
          center: Point2D(100, 100),
          radius: 5,
          startAngle: 0,
          endAngle: pi,
          clockwise: false,
        );
        final line = LineSegment(Point2D(0, 0), Point2D(1, 0));
        final joints = IntersectionFinder.findAllJoints([line], [arc]);
        expect(joints, isEmpty);
      });
    });
  });

  // ─── CalibrationScale ──────────────────────────────────────────────

  group('CalibrationScale', () {
    group('toMm and toPixels round-trip', () {
      test('converts pixels to mm and back', () {
        final scale = CalibrationScale(
          knownDistanceMm: 100,
          pixelDistance: 500,
        );
        // 500 px = 100 mm → 5 px/mm
        expect(scale.toMm(500), closeTo(100, 0.001));
        expect(scale.toPixels(100), closeTo(500, 0.001));
      });

      test('round-trip is identity', () {
        final scale = CalibrationScale(
          knownDistanceMm: 25.4,
          pixelDistance: 72,
        );
        final mm = 42.0;
        expect(scale.toMm(scale.toPixels(mm)), closeTo(mm, 0.001));
      });
    });

    group('fromPoints', () {
      test('creates valid scale from two points', () {
        final scale = CalibrationScale.fromPoints(
          Point2D(0, 0),
          Point2D(300, 400),
          100,
        );
        // pixelDistance should be 500
        expect(scale.pixelDistance, closeTo(500, 0.001));
        expect(scale.knownDistanceMm, closeTo(100, 0.001));
        expect(scale.pixelsPerMm, closeTo(5, 0.001));
      });

      test('coincident points throw ArgumentError', () {
        expect(
          () => CalibrationScale.fromPoints(
            Point2D(5, 5),
            Point2D(5, 5),
            100,
          ),
          throwsArgumentError,
        );
      });

      test('zero knownDistanceMm throws ArgumentError', () {
        expect(
          () => CalibrationScale.fromPoints(
            Point2D(0, 0),
            Point2D(10, 0),
            0,
          ),
          throwsArgumentError,
        );
      });

      test('negative knownDistanceMm throws ArgumentError', () {
        expect(
          () => CalibrationScale.fromPoints(
            Point2D(0, 0),
            Point2D(10, 0),
            -5,
          ),
          throwsArgumentError,
        );
      });
    });

    group('JSON round-trip', () {
      test('serializes and deserializes', () {
        final original = CalibrationScale(
          knownDistanceMm: 25.4,
          pixelDistance: 72,
        );
        final json = original.toJson();
        final restored = CalibrationScale.fromJson(json);
        expect(restored.knownDistanceMm, closeTo(25.4, 0.001));
        expect(restored.pixelDistance, closeTo(72, 0.001));
      });

      test('handles integer values in JSON', () {
        final restored = CalibrationScale.fromJson({
          'knownDistanceMm': 100,
          'pixelDistance': 500,
        });
        expect(restored.knownDistanceMm, closeTo(100, 0.001));
        expect(restored.pixelDistance, closeTo(500, 0.001));
      });
    });
  });
}
