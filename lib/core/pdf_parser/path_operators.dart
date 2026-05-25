/// Represents a parsed PDF path command.
enum PathCommandType {
  moveTo,       // m
  lineTo,       // l
  curveTo,      // c (cubic bezier, 6 args)
  curveToV,     // v (cubic bezier, cp1=current, 4 args: cp2x, cp2y, endx, endy)
  curveToY,     // y (cubic bezier, cp2=end, 4 args: cp1x, cp1y, endx, endy)
  closePath,    // h
  rect,         // re
  saveState,    // q
  restoreState, // Q
  setCTM,       // cm (6 args: a, b, c, d, e, f)
  setLineWidth,       // w (1 arg: lineWidth)
  setStrokeRGBColor,  // RG (3 args: r, g, b  each 0..1)
  setStrokeGray,      // G (1 arg: gray 0..1)
  setStrokeCMYKColor, // K (4 args: c, m, y, k  each 0..1)
  setFillRGBColor,    // rg (3 args: r, g, b  each 0..1)
  setFillGray,        // g (1 arg: gray 0..1)
  setFillCMYKColor,   // k (4 args: c, m, y, k  each 0..1)
  setDash,            // d (args: dashArray..., dashPhase)
}

class PathCommand {
  final PathCommandType type;
  final List<double> args;

  const PathCommand(this.type, this.args);

  @override
  String toString() => 'PathCommand(${type.name}, $args)';
}

