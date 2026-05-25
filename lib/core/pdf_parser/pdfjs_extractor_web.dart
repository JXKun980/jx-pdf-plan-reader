import 'dart:js_interop';
import 'dart:typed_data';

import 'page_extract_result.dart';
import 'path_operators.dart';

@JS('extractPdfPageOps')
external JSPromise<JSAny> _extractPdfPageOps(
  JSArrayBuffer bytes,
  JSNumber pageNumber,
);

/// Extract commands + page metadata.
Future<PageExtractResult> extractPageData(
  Uint8List pdfBytes,
  int pageNumber,
) async {
  final jsBuffer = Uint8List.fromList(pdfBytes).buffer.toJS;
  final jsAny = await _extractPdfPageOps(jsBuffer, pageNumber.toJS).toDart;
  final result = jsAny.dartify() as Map;

  final view = (result['view'] as List).map((v) => (v as num).toDouble()).toList();
  final jsOps = result['ops'] as List;

  final commands = <PathCommand>[];
  for (var i = 0; i < jsOps.length; i++) {
    final item = jsOps[i] as Map;
    final op = item['op'] as String;
    final rawArgs = item['args'] as List;
    final args = rawArgs.map((a) => (a as num).toDouble()).toList();

    final type = _mapOp(op);
    if (type != null) {
      commands.add(PathCommand(type, args));
    }
  }

  return PageExtractResult(commands, view);
}

PathCommandType? _mapOp(String op) {
  return switch (op) {
    'm'  => PathCommandType.moveTo,
    'l'  => PathCommandType.lineTo,
    'c'  => PathCommandType.curveTo,
    'v'  => PathCommandType.curveToV,
    'y'  => PathCommandType.curveToY,
    'h'  => PathCommandType.closePath,
    're' => PathCommandType.rect,
    'q'  => PathCommandType.saveState,
    'Q'  => PathCommandType.restoreState,
    'cm' => PathCommandType.setCTM,
    'w'  => PathCommandType.setLineWidth,
    'RG' => PathCommandType.setStrokeRGBColor,
    'G'  => PathCommandType.setStrokeGray,
    'K'  => PathCommandType.setStrokeCMYKColor,
    'rg' => PathCommandType.setFillRGBColor,
    'fg' => PathCommandType.setFillGray,
    'fk' => PathCommandType.setFillCMYKColor,
    'd'  => PathCommandType.setDash,
    _    => null,
  };
}
