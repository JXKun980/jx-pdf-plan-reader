import 'dart:typed_data';

import '../../models/detected_element.dart';
import '../geometry/arc_segment.dart';
import '../geometry/hatch_filter.dart';
import '../geometry/intersections.dart';
import '../geometry/line_segment.dart';
import '../geometry/point2d.dart';
import 'pdf_path_extractor.dart';

// Conditional import for web-specific PDF.js interop
import 'pdfjs_extractor_stub.dart'
    if (dart.library.js_interop) 'pdfjs_extractor_web.dart' as pdfjs;

/// Result of geometry detection for a single page.
class DetectionResult {
  final List<DetectedElement> elements;
  final List<Joint> joints;
  final bool isVectorPage;

  const DetectionResult({
    required this.elements,
    required this.joints,
    required this.isVectorPage,
  });

  static const empty = DetectionResult(
    elements: [],
    joints: [],
    isVectorPage: false,
  );
}

/// Detects vector geometry (lines, arcs, joints) from PDF page data.
class GeometryDetector {
  static Future<DetectionResult> detectPage(
    Uint8List pdfBytes,
    int pageNumber,
  ) async {
    final data = await pdfjs.extractPageData(pdfBytes, pageNumber);
    if (data.commands.isEmpty) return DetectionResult.empty;

    // PDF.js constructPath pre-applies the CTM to path coordinates,
    // placing them in the page's MediaBox coordinate system.
    final extracted = PdfPathExtractor.extractFromCommands(
      data.commands,
      preTransformed: true,
    );
    if (extracted.isEmpty) return DetectionResult.empty;

    // The MediaBox may not start at (0,0). Shift so the origin maps to (0,0).
    // view = [x0, y0, x1, y1], overlay expects [0..pageW] × [0..pageH].
    final ox = data.view[0];
    final oy = data.view[1];

    Point2D toOverlay(Point2D p) => Point2D(p.x - ox, p.y - oy);

    final lines = extracted.lines.map((seg) {
      return LineSegment(toOverlay(seg.start), toOverlay(seg.end));
    }).toList();
    final lineStyles = extracted.lineStyles;

    // Shift arc centers by the same MediaBox origin offset.
    final arcs = extracted.arcs.map((arc) {
      return ArcSegment(
        center: toOverlay(arc.center),
        radius: arc.radius,
        startAngle: arc.startAngle,
        endAngle: arc.endAngle,
        clockwise: arc.clockwise,
      );
    }).toList();

    // Filter out cross-hatching patterns (uses color grouping + spacing).
    final filteredLines = HatchFilter.removeHatchLines(
      lines,
      styles: lineStyles,
    );

    // Build detected elements
    final elements = <DetectedElement>[];
    var idx = 0;
    for (final line in filteredLines) {
      elements.add(DetectedElement.line('line_$idx', line));
      idx++;
    }
    for (final arc in arcs) {
      elements.add(DetectedElement.arc('arc_$idx', arc));
      idx++;
    }

    // Find joints
    final joints = IntersectionFinder.findAllJoints(
      filteredLines,
      arcs,
    );

    return DetectionResult(
      elements: elements,
      joints: joints,
      isVectorPage: elements.length >= 10,
    );
  }
}
