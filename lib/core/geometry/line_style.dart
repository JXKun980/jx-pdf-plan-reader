/// Style metadata extracted from the PDF graphics state.
class LineStyle {
  /// Stroke line width in PDF user-space units.
  final double lineWidth;

  /// Stroke color as RGB, each component 0.0–1.0.
  final double r;
  final double g;
  final double b;

  /// Whether the stroke uses a dash pattern.
  final bool isDashed;

  const LineStyle({
    this.lineWidth = 1.0,
    this.r = 0.0,
    this.g = 0.0,
    this.b = 0.0,
    this.isDashed = false,
  });

  /// Default black, 1pt width, solid.
  static const defaultStyle = LineStyle();

  LineStyle copyWith({
    double? lineWidth,
    double? r,
    double? g,
    double? b,
    bool? isDashed,
  }) =>
      LineStyle(
        lineWidth: lineWidth ?? this.lineWidth,
        r: r ?? this.r,
        g: g ?? this.g,
        b: b ?? this.b,
        isDashed: isDashed ?? this.isDashed,
      );

  @override
  String toString() =>
      'LineStyle(w=$lineWidth, rgb=($r, $g, $b), dashed=$isDashed)';
}
