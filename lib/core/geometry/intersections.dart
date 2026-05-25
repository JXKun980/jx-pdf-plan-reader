import 'point2d.dart';
import 'line_segment.dart';
import 'arc_segment.dart';

class Joint {
  final Point2D point;
  final List<int> connectedElementIndices;

  const Joint(this.point, this.connectedElementIndices);

  @override
  String toString() => 'Joint($point, elements: $connectedElementIndices)';
}

class IntersectionFinder {
  static const double _tolerance = 1.5;

  /// Find all joints (intersection points) among a list of line segments.
  static List<Joint> findLineJoints(List<LineSegment> lines) {
    final joints = <_MergeableJoint>[];

    for (var i = 0; i < lines.length; i++) {
      // Add line endpoints as potential joints
      _addOrMergeJoint(joints, lines[i].start, i);
      _addOrMergeJoint(joints, lines[i].end, i);

      // Find intersections with other lines
      for (var j = i + 1; j < lines.length; j++) {
        final intersection = lines[i].intersectionWith(lines[j]);
        if (intersection != null) {
          _addOrMergeJoint(joints, intersection, i);
          _addOrMergeJoint(joints, intersection, j);
        }
      }
    }

    return joints
        .where((j) => j.elementIndices.length >= 2)
        .map((j) => Joint(j.point, List.unmodifiable(j.elementIndices)))
        .toList();
  }

  /// Find joints among line segments and arc segments.
  ///
  /// Finds line-line intersections and connects elements that share
  /// endpoints (within tolerance). Does not compute line-arc or
  /// arc-arc geometric intersections.
  static List<Joint> findAllJoints(
    List<LineSegment> lines,
    List<ArcSegment> arcs,
  ) {
    final joints = findLineJoints(lines);
    final mergeableJoints = joints
        .map((j) => _MergeableJoint(j.point, j.connectedElementIndices.toList()))
        .toList();

    final arcOffset = lines.length;

    // Add arc endpoints
    for (var i = 0; i < arcs.length; i++) {
      _addOrMergeJoint(mergeableJoints, arcs[i].startPoint, arcOffset + i);
      _addOrMergeJoint(mergeableJoints, arcs[i].endPoint, arcOffset + i);
    }

    return mergeableJoints
        .where((j) => j.elementIndices.length >= 2)
        .map((j) => Joint(j.point, List.unmodifiable(j.elementIndices)))
        .toList();
  }

  static void _addOrMergeJoint(
    List<_MergeableJoint> joints,
    Point2D point,
    int elementIndex,
  ) {
    for (final joint in joints) {
      if (joint.point.distanceTo(point) < _tolerance) {
        if (!joint.elementIndices.contains(elementIndex)) {
          joint.elementIndices.add(elementIndex);
        }
        return;
      }
    }
    joints.add(_MergeableJoint(point, [elementIndex]));
  }
}

class _MergeableJoint {
  final Point2D point;
  final List<int> elementIndices;

  _MergeableJoint(this.point, this.elementIndices);
}
