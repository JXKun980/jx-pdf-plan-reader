import 'dart:math' as math;

import 'line_segment.dart';
import 'line_style.dart';

/// Detects and removes cross-hatching patterns from extracted line segments.
///
/// Cross-hatching consists of groups of parallel, uniformly-spaced lines used
/// to fill/highlight areas in construction drawings. These are noise for
/// measurement purposes.
class HatchFilter {
  /// Remove lines that form cross-hatching patterns.
  ///
  /// Groups lines by angle, then checks for uniform spacing within each group.
  /// Groups of [minGroupSize]+ parallel, evenly-spaced lines are removed.
  ///
  /// When [styles] is provided (parallel list to [lines]), the filter also
  /// groups by stroke color and uses thin line width as an additional signal.
  static List<int> findHatchIndices(
    List<LineSegment> lines, {
    List<LineStyle>? styles,
    double angleToleranceDeg = 3.0,
    int minGroupSize = 5,
    double spacingCvThreshold = 0.35,
  }) {
    if (lines.length < minGroupSize) return [];

    final angles = List.generate(lines.length, (i) => _normalizedAngle(lines[i]));

    // Build candidate indices, optionally sub-grouped by color.
    // Dashed segments are never considered hatch — they are intentional
    // drawing elements (dimension lines, hidden edges, etc.).
    final colorGroups = <_ColorKey, List<int>>{};
    for (var i = 0; i < lines.length; i++) {
      if (styles != null && styles[i].isDashed) continue;
      final key = styles != null
          ? _ColorKey.fromStyle(styles[i])
          : const _ColorKey(0, 0, 0);
      (colorGroups[key] ??= []).add(i);
    }

    final hatchIndices = <int>{};

    for (final indices in colorGroups.values) {
      if (indices.length < minGroupSize) continue;

      // Sort this color-group's indices by angle.
      final sorted = List<int>.from(indices)
        ..sort((a, b) => angles[a].compareTo(angles[b]));

      final toleranceRad = angleToleranceDeg * math.pi / 180;
      var groupStart = 0;

      while (groupStart < sorted.length) {
        final refAngle = angles[sorted[groupStart]];

        var groupEnd = groupStart + 1;
        while (groupEnd < sorted.length) {
          final diff = _angleDiff(angles[sorted[groupEnd]], refAngle);
          if (diff > toleranceRad) break;
          groupEnd++;
        }

        final groupSize = groupEnd - groupStart;
        if (groupSize >= minGroupSize) {
          final group = sorted.sublist(groupStart, groupEnd);
          if (_isUniformlySpaced(group, lines, angles, spacingCvThreshold)) {
            hatchIndices.addAll(group);
          }
        }

        groupStart = groupEnd;
      }
    }

    return hatchIndices.toList();
  }

  /// Convenience: return filtered lines with hatch lines removed.
  static List<LineSegment> removeHatchLines(
    List<LineSegment> lines, {
    List<LineStyle>? styles,
    double angleToleranceDeg = 3.0,
    int minGroupSize = 5,
    double spacingCvThreshold = 0.35,
  }) {
    final hatch = findHatchIndices(
      lines,
      styles: styles,
      angleToleranceDeg: angleToleranceDeg,
      minGroupSize: minGroupSize,
      spacingCvThreshold: spacingCvThreshold,
    );
    if (hatch.isEmpty) return lines;
    final hatchSet = hatch.toSet();
    return [
      for (var i = 0; i < lines.length; i++)
        if (!hatchSet.contains(i)) lines[i],
    ];
  }

  /// Line angle normalised to [0, π) — direction-independent.
  static double _normalizedAngle(LineSegment line) {
    final dx = line.end.x - line.start.x;
    final dy = line.end.y - line.start.y;
    var a = math.atan2(dy, dx);
    if (a < 0) a += math.pi;
    if (a >= math.pi) a -= math.pi;
    return a;
  }

  /// Smallest angular difference, accounting for wrap-around at π.
  static double _angleDiff(double a, double b) {
    var d = (a - b).abs();
    if (d > math.pi / 2) d = math.pi - d;
    return d;
  }

  /// Check whether lines in [group] are uniformly spaced (low coefficient of
  /// variation of the gaps between consecutive line projections).
  static bool _isUniformlySpaced(
    List<int> group,
    List<LineSegment> lines,
    List<double> angles,
    double cvThreshold,
  ) {
    // Average angle → perpendicular direction for projection.
    final avgAngle = angles[group[0]];
    final perpX = -math.sin(avgAngle);
    final perpY = math.cos(avgAngle);

    // Project each line's midpoint onto the perpendicular axis.
    final projections = <double>[];
    for (final idx in group) {
      final seg = lines[idx];
      final mx = (seg.start.x + seg.end.x) / 2;
      final my = (seg.start.y + seg.end.y) / 2;
      projections.add(mx * perpX + my * perpY);
    }
    projections.sort();

    // Compute gaps between consecutive projections.
    final gaps = <double>[];
    for (var i = 1; i < projections.length; i++) {
      final g = projections[i] - projections[i - 1];
      if (g > 0.5) gaps.add(g); // skip near-overlapping lines
    }

    if (gaps.length < 2) return false;

    // Coefficient of variation = stddev / mean.
    final mean = gaps.reduce((a, b) => a + b) / gaps.length;
    if (mean < 0.1) return false;

    final variance =
        gaps.map((g) => (g - mean) * (g - mean)).reduce((a, b) => a + b) /
            gaps.length;
    final cv = math.sqrt(variance) / mean;

    return cv < cvThreshold;
  }
}

/// Quantised RGB key for grouping lines by color.
/// Rounds to nearest 0.05 to tolerate minor color rounding.
class _ColorKey {
  final int r, g, b;
  const _ColorKey(this.r, this.g, this.b);

  factory _ColorKey.fromStyle(LineStyle s) => _ColorKey(
        (s.r * 20).round(),
        (s.g * 20).round(),
        (s.b * 20).round(),
      );

  @override
  bool operator ==(Object other) =>
      other is _ColorKey && r == other.r && g == other.g && b == other.b;

  @override
  int get hashCode => Object.hash(r, g, b);
}
