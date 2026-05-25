import 'path_operators.dart';

/// Extraction result: commands + page info from PDF.js.
class PageExtractResult {
  final List<PathCommand> commands;

  /// The page view [x0, y0, x1, y1] — the MediaBox/CropBox bounding box.
  final List<double> view;

  PageExtractResult(this.commands, this.view);

  double get pageWidth => view[2] - view[0];
  double get pageHeight => view[3] - view[1];
}
