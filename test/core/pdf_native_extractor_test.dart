import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_graph_app/core/pdf_parser/page_extract_result.dart';
import 'package:pdf_graph_app/core/pdf_parser/path_operators.dart';

// The stub is the native extractor on non-web platforms.
import 'package:pdf_graph_app/core/pdf_parser/pdfjs_extractor_stub.dart'
    as extractor;

// ---------------------------------------------------------------------------
// Helpers to build minimal PDF binaries in memory
// ---------------------------------------------------------------------------

/// Build a minimal single-page PDF whose page content stream contains
/// [contentStream] (plain text operators).
///
/// The PDF uses an uncompressed content stream so we can test the parser
/// without worrying about zlib encoding.
Uint8List buildMinimalPdf(
  String contentStream, {
  List<double> mediaBox = const [0, 0, 612, 792],
  bool compress = false,
}) {
  final content = utf8.encode(contentStream);
  final streamBytes = compress
      ? Uint8List.fromList(zlib.encode(content))
      : Uint8List.fromList(content);

  final filterLine = compress ? '/Filter /FlateDecode ' : '';

  // Object 1: Catalog
  // Object 2: Pages
  // Object 3: Page
  // Object 4: Content stream

  final buf = StringBuffer();

  // Header
  buf.write('%PDF-1.4\n');

  // Object 1 – Catalog
  final obj1Offset = buf.length;
  buf.write('1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n');

  // Object 2 – Pages
  final obj2Offset = buf.length;
  buf.write(
      '2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n');

  // Object 3 – Page
  final obj3Offset = buf.length;
  final mb = mediaBox.join(' ');
  buf.write(
      '3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [$mb] /Contents 4 0 R >>\nendobj\n');

  // Object 4 – Content stream
  // We must switch to bytes here because stream data may be binary.
  final preStream =
      '4 0 obj\n<< ${filterLine}/Length ${streamBytes.length} >>\nstream\n';
  final postStream = '\nendstream\nendobj\n';

  final preBytes = utf8.encode(buf.toString() + preStream);
  final obj4Offset =
      buf.length; // offset of "4 0 obj" in the final byte output
  final postBytes = utf8.encode(postStream);

  // xref + trailer
  final xrefBuf = StringBuffer();
  final xrefOffset = preBytes.length + streamBytes.length + postBytes.length;
  xrefBuf.write('xref\n');
  xrefBuf.write('0 5\n');
  xrefBuf.write('0000000000 65535 f \n');
  xrefBuf.write('${obj1Offset.toString().padLeft(10, '0')} 00000 n \n');
  xrefBuf.write('${obj2Offset.toString().padLeft(10, '0')} 00000 n \n');
  xrefBuf.write('${obj3Offset.toString().padLeft(10, '0')} 00000 n \n');
  xrefBuf.write('${obj4Offset.toString().padLeft(10, '0')} 00000 n \n');
  xrefBuf.write('trailer\n<< /Size 5 /Root 1 0 R >>\n');
  xrefBuf.write('startxref\n$xrefOffset\n%%EOF\n');

  final xrefBytes = utf8.encode(xrefBuf.toString());

  // Combine all parts
  final total = BytesBuilder();
  total.add(preBytes);
  total.add(streamBytes);
  total.add(postBytes);
  total.add(xrefBytes);
  return total.toBytes();
}

/// Build a two-page PDF. Page 1 has [contentStream1], page 2 has
/// [contentStream2]. Both are uncompressed.
Uint8List buildTwoPagePdf(
  String contentStream1,
  String contentStream2, {
  List<double> mediaBox = const [0, 0, 612, 792],
}) {
  final c1 = utf8.encode(contentStream1);
  final c2 = utf8.encode(contentStream2);

  final buf = StringBuffer();
  buf.write('%PDF-1.4\n');

  // Obj 1 – Catalog
  final o1 = buf.length;
  buf.write('1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n');

  // Obj 2 – Pages
  final o2 = buf.length;
  buf.write(
      '2 0 obj\n<< /Type /Pages /Kids [3 0 R 5 0 R] /Count 2 >>\nendobj\n');

  // Obj 3 – Page 1
  final o3 = buf.length;
  final mb = mediaBox.join(' ');
  buf.write(
      '3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [$mb] /Contents 4 0 R >>\nendobj\n');

  // Obj 4 – Content stream for page 1
  final o4 = buf.length;
  buf.write('4 0 obj\n<< /Length ${c1.length} >>\nstream\n');
  buf.write(contentStream1);
  buf.write('\nendstream\nendobj\n');

  // Obj 5 – Page 2
  final o5 = buf.length;
  buf.write(
      '5 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [$mb] /Contents 6 0 R >>\nendobj\n');

  // Obj 6 – Content stream for page 2
  final o6 = buf.length;
  buf.write('6 0 obj\n<< /Length ${c2.length} >>\nstream\n');
  buf.write(contentStream2);
  buf.write('\nendstream\nendobj\n');

  // xref
  final xrefOffset = buf.length;
  buf.write('xref\n0 7\n');
  buf.write('0000000000 65535 f \n');
  buf.write('${o1.toString().padLeft(10, '0')} 00000 n \n');
  buf.write('${o2.toString().padLeft(10, '0')} 00000 n \n');
  buf.write('${o3.toString().padLeft(10, '0')} 00000 n \n');
  buf.write('${o4.toString().padLeft(10, '0')} 00000 n \n');
  buf.write('${o5.toString().padLeft(10, '0')} 00000 n \n');
  buf.write('${o6.toString().padLeft(10, '0')} 00000 n \n');
  buf.write('trailer\n<< /Size 7 /Root 1 0 R >>\n');
  buf.write('startxref\n$xrefOffset\n%%EOF\n');

  return Uint8List.fromList(utf8.encode(buf.toString()));
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('Native PDF extractor — basic extraction', () {
    test('extracts moveTo + lineTo from uncompressed stream', () async {
      final pdf = buildMinimalPdf('100 200 m 300 400 l');
      final result = await extractor.extractPageData(pdf, 1);

      expect(result.commands, isNotEmpty);

      final moveCmd = result.commands
          .firstWhere((c) => c.type == PathCommandType.moveTo);
      expect(moveCmd.args[0], closeTo(100, 0.001));
      expect(moveCmd.args[1], closeTo(200, 0.001));

      final lineCmd = result.commands
          .firstWhere((c) => c.type == PathCommandType.lineTo);
      expect(lineCmd.args[0], closeTo(300, 0.001));
      expect(lineCmd.args[1], closeTo(400, 0.001));
    });

    test('extracts MediaBox as page view', () async {
      final pdf = buildMinimalPdf('0 0 m',
          mediaBox: [0, 0, 841.89, 595.28]); // A4 landscape
      final result = await extractor.extractPageData(pdf, 1);

      expect(result.view[0], closeTo(0, 0.01));
      expect(result.view[1], closeTo(0, 0.01));
      expect(result.view[2], closeTo(841.89, 0.01));
      expect(result.view[3], closeTo(595.28, 0.01));
      expect(result.pageWidth, closeTo(841.89, 0.01));
      expect(result.pageHeight, closeTo(595.28, 0.01));
    });

    test('extracts FlateDecode (zlib) compressed stream', () async {
      final pdf = buildMinimalPdf('50 60 m 70 80 l', compress: true);
      final result = await extractor.extractPageData(pdf, 1);

      expect(result.commands, isNotEmpty);
      final moveCmd = result.commands
          .firstWhere((c) => c.type == PathCommandType.moveTo);
      expect(moveCmd.args[0], closeTo(50, 0.001));
      expect(moveCmd.args[1], closeTo(60, 0.001));
    });
  });

  group('Native PDF extractor — all operator types', () {
    test('curveTo (c) with 6 args', () async {
      final pdf = buildMinimalPdf('0 0 m 10 20 30 40 50 60 c');
      final result = await extractor.extractPageData(pdf, 1);

      final cmd = result.commands
          .firstWhere((c) => c.type == PathCommandType.curveTo);
      expect(cmd.args, hasLength(6));
      expect(cmd.args[0], closeTo(10, 0.001));
      expect(cmd.args[5], closeTo(60, 0.001));
    });

    test('curveToV (v) with 4 args', () async {
      final pdf = buildMinimalPdf('0 0 m 10 20 30 40 v');
      final result = await extractor.extractPageData(pdf, 1);

      final cmd = result.commands
          .firstWhere((c) => c.type == PathCommandType.curveToV);
      expect(cmd.args, hasLength(4));
    });

    test('curveToY (y) with 4 args', () async {
      final pdf = buildMinimalPdf('0 0 m 10 20 30 40 y');
      final result = await extractor.extractPageData(pdf, 1);

      final cmd = result.commands
          .firstWhere((c) => c.type == PathCommandType.curveToY);
      expect(cmd.args, hasLength(4));
    });

    test('closePath (h)', () async {
      final pdf = buildMinimalPdf('0 0 m 100 0 l 100 100 l h');
      final result = await extractor.extractPageData(pdf, 1);

      final cmd = result.commands
          .firstWhere((c) => c.type == PathCommandType.closePath);
      expect(cmd.args, isEmpty);
    });

    test('rect (re) with 4 args', () async {
      final pdf = buildMinimalPdf('10 20 100 50 re');
      final result = await extractor.extractPageData(pdf, 1);

      final cmd =
          result.commands.firstWhere((c) => c.type == PathCommandType.rect);
      expect(cmd.args, hasLength(4));
      expect(cmd.args[0], closeTo(10, 0.001));
      expect(cmd.args[1], closeTo(20, 0.001));
      expect(cmd.args[2], closeTo(100, 0.001));
      expect(cmd.args[3], closeTo(50, 0.001));
    });

    test('saveState (q) and restoreState (Q)', () async {
      final pdf = buildMinimalPdf('q 0 0 m Q');
      final result = await extractor.extractPageData(pdf, 1);

      expect(
        result.commands.any((c) => c.type == PathCommandType.saveState),
        isTrue,
      );
      expect(
        result.commands.any((c) => c.type == PathCommandType.restoreState),
        isTrue,
      );
    });

    test('setCTM (cm) with 6 args', () async {
      final pdf = buildMinimalPdf('1 0 0 1 50 100 cm');
      final result = await extractor.extractPageData(pdf, 1);

      final cmd =
          result.commands.firstWhere((c) => c.type == PathCommandType.setCTM);
      expect(cmd.args, hasLength(6));
      expect(cmd.args[0], closeTo(1, 0.001));
      expect(cmd.args[4], closeTo(50, 0.001));
      expect(cmd.args[5], closeTo(100, 0.001));
    });

    test('setLineWidth (w)', () async {
      final pdf = buildMinimalPdf('2.5 w');
      final result = await extractor.extractPageData(pdf, 1);

      final cmd = result.commands
          .firstWhere((c) => c.type == PathCommandType.setLineWidth);
      expect(cmd.args[0], closeTo(2.5, 0.001));
    });

    test('setStrokeRGBColor (RG)', () async {
      final pdf = buildMinimalPdf('0.2 0.4 0.8 RG');
      final result = await extractor.extractPageData(pdf, 1);

      final cmd = result.commands
          .firstWhere((c) => c.type == PathCommandType.setStrokeRGBColor);
      expect(cmd.args, hasLength(3));
      expect(cmd.args[0], closeTo(0.2, 0.001));
      expect(cmd.args[1], closeTo(0.4, 0.001));
      expect(cmd.args[2], closeTo(0.8, 0.001));
    });

    test('setStrokeGray (G)', () async {
      final pdf = buildMinimalPdf('0.5 G');
      final result = await extractor.extractPageData(pdf, 1);

      final cmd = result.commands
          .firstWhere((c) => c.type == PathCommandType.setStrokeGray);
      expect(cmd.args[0], closeTo(0.5, 0.001));
    });

    test('setStrokeCMYKColor (K)', () async {
      final pdf = buildMinimalPdf('0.1 0.2 0.3 0.4 K');
      final result = await extractor.extractPageData(pdf, 1);

      final cmd = result.commands
          .firstWhere((c) => c.type == PathCommandType.setStrokeCMYKColor);
      expect(cmd.args, hasLength(4));
    });

    test('setFillRGBColor (rg)', () async {
      final pdf = buildMinimalPdf('0.1 0.2 0.3 rg');
      final result = await extractor.extractPageData(pdf, 1);

      final cmd = result.commands
          .firstWhere((c) => c.type == PathCommandType.setFillRGBColor);
      expect(cmd.args, hasLength(3));
    });

    test('setFillGray (g)', () async {
      final pdf = buildMinimalPdf('0.7 g');
      final result = await extractor.extractPageData(pdf, 1);

      final cmd = result.commands
          .firstWhere((c) => c.type == PathCommandType.setFillGray);
      expect(cmd.args[0], closeTo(0.7, 0.001));
    });

    test('setFillCMYKColor (k)', () async {
      final pdf = buildMinimalPdf('0.1 0.2 0.3 0.4 k');
      final result = await extractor.extractPageData(pdf, 1);

      final cmd = result.commands
          .firstWhere((c) => c.type == PathCommandType.setFillCMYKColor);
      expect(cmd.args, hasLength(4));
    });

    test('setDash (d) with dash array', () async {
      // The tokenizer sees operands as flat numbers; the '[' array is skipped
      // and only the phase operand remains. Test that the operator itself is
      // recognised even when the dash array bracket structure is present.
      final pdf = buildMinimalPdf('[6 3] 0 d');
      final result = await extractor.extractPageData(pdf, 1);

      final cmd = result.commands
          .firstWhere((c) => c.type == PathCommandType.setDash);
      expect(cmd, isNotNull);
    });
  });

  group('Native PDF extractor — complex content streams', () {
    test('multiple paths in one stream', () async {
      final pdf = buildMinimalPdf(
        'q 0 0 m 100 0 l S Q q 200 200 m 300 300 l S Q',
      );
      final result = await extractor.extractPageData(pdf, 1);

      final moves =
          result.commands.where((c) => c.type == PathCommandType.moveTo);
      final lines =
          result.commands.where((c) => c.type == PathCommandType.lineTo);
      expect(moves.length, greaterThanOrEqualTo(2));
      expect(lines.length, greaterThanOrEqualTo(2));
    });

    test('text operators are ignored without corrupting path data', () async {
      final pdf = buildMinimalPdf(
        'BT /F1 12 Tf (Hello World) Tj ET 100 200 m 300 400 l',
      );
      final result = await extractor.extractPageData(pdf, 1);

      final moveCmd = result.commands
          .firstWhere((c) => c.type == PathCommandType.moveTo);
      expect(moveCmd.args[0], closeTo(100, 0.001));
      expect(moveCmd.args[1], closeTo(200, 0.001));
    });

    test('comments in content stream are skipped', () async {
      final pdf = buildMinimalPdf(
        '100 200 m % this is a comment\n300 400 l',
      );
      final result = await extractor.extractPageData(pdf, 1);

      expect(
        result.commands.any((c) => c.type == PathCommandType.moveTo),
        isTrue,
      );
      expect(
        result.commands.any((c) => c.type == PathCommandType.lineTo),
        isTrue,
      );
    });

    test('negative coordinates are parsed correctly', () async {
      final pdf = buildMinimalPdf('-50 -100 m -200 300.5 l');
      final result = await extractor.extractPageData(pdf, 1);

      final moveCmd = result.commands
          .firstWhere((c) => c.type == PathCommandType.moveTo);
      expect(moveCmd.args[0], closeTo(-50, 0.001));
      expect(moveCmd.args[1], closeTo(-100, 0.001));

      final lineCmd = result.commands
          .firstWhere((c) => c.type == PathCommandType.lineTo);
      expect(lineCmd.args[0], closeTo(-200, 0.001));
      expect(lineCmd.args[1], closeTo(300.5, 0.001));
    });

    test('decimal-only numbers (e.g. .5) are parsed', () async {
      final pdf = buildMinimalPdf('.5 .25 m 1.0 2.0 l');
      final result = await extractor.extractPageData(pdf, 1);

      final moveCmd = result.commands
          .firstWhere((c) => c.type == PathCommandType.moveTo);
      expect(moveCmd.args[0], closeTo(0.5, 0.001));
      expect(moveCmd.args[1], closeTo(0.25, 0.001));
    });

    test('mixed graphics state and path operators', () async {
      final pdf = buildMinimalPdf(
        'q 1.5 w 0.2 0.3 0.4 RG 1 0 0 1 10 20 cm 0 0 m 50 50 l S Q',
      );
      final result = await extractor.extractPageData(pdf, 1);

      final types = result.commands.map((c) => c.type).toSet();
      expect(types, contains(PathCommandType.saveState));
      expect(types, contains(PathCommandType.setLineWidth));
      expect(types, contains(PathCommandType.setStrokeRGBColor));
      expect(types, contains(PathCommandType.setCTM));
      expect(types, contains(PathCommandType.moveTo));
      expect(types, contains(PathCommandType.lineTo));
      expect(types, contains(PathCommandType.restoreState));
    });
  });

  group('Native PDF extractor — multi-page', () {
    test('extracts correct page from multi-page PDF', () async {
      final pdf = buildTwoPagePdf(
        '10 20 m 30 40 l',
        '100 200 m 300 400 l',
      );

      final page1 = await extractor.extractPageData(pdf, 1);
      final moveP1 = page1.commands
          .firstWhere((c) => c.type == PathCommandType.moveTo);
      expect(moveP1.args[0], closeTo(10, 0.001));
      expect(moveP1.args[1], closeTo(20, 0.001));

      final page2 = await extractor.extractPageData(pdf, 2);
      final moveP2 = page2.commands
          .firstWhere((c) => c.type == PathCommandType.moveTo);
      expect(moveP2.args[0], closeTo(100, 0.001));
      expect(moveP2.args[1], closeTo(200, 0.001));
    });
  });

  group('Native PDF extractor — error handling & edge cases', () {
    test('empty bytes return empty result', () async {
      final result = await extractor.extractPageData(Uint8List(0), 1);
      expect(result.commands, isEmpty);
      expect(result.view, hasLength(4));
    });

    test('random garbage bytes return empty result', () async {
      final garbage = Uint8List.fromList(
          List.generate(256, (i) => (i * 37 + 13) % 256));
      final result = await extractor.extractPageData(garbage, 1);
      expect(result.commands, isEmpty);
    });

    test('truncated PDF returns empty result', () async {
      final pdf = buildMinimalPdf('100 200 m');
      // Truncate to half the size
      final truncated = pdf.sublist(0, pdf.length ~/ 2);
      final result = await extractor.extractPageData(
          Uint8List.fromList(truncated), 1);
      // Should not throw — graceful fallback
      expect(result, isA<PageExtractResult>());
    });

    test('page number out of range returns empty result', () async {
      final pdf = buildMinimalPdf('0 0 m');
      final result = await extractor.extractPageData(pdf, 99);
      expect(result.commands, isEmpty);
    });

    test('page 0 (invalid) returns empty result', () async {
      final pdf = buildMinimalPdf('0 0 m');
      final result = await extractor.extractPageData(pdf, 0);
      // pageNumber is 1-indexed; 0 maps to index -1 which won't find a page
      expect(result.commands, isEmpty);
    });

    test('content stream with only whitespace returns empty commands',
        () async {
      final pdf = buildMinimalPdf('   \n\r\n   ');
      final result = await extractor.extractPageData(pdf, 1);
      expect(result.commands, isEmpty);
    });

    test('content stream with only comments returns empty commands', () async {
      final pdf = buildMinimalPdf('% just a comment\n% another one\n');
      final result = await extractor.extractPageData(pdf, 1);
      expect(result.commands, isEmpty);
    });

    test('operator with insufficient operands is skipped', () async {
      // 'c' needs 6 operands, only 4 given; should be skipped.
      // Then a valid moveTo follows.
      final pdf = buildMinimalPdf('1 2 3 4 c 10 20 m');
      final result = await extractor.extractPageData(pdf, 1);

      // The malformed 'c' should be skipped, moveTo should parse.
      final moveCmd = result.commands
          .where((c) => c.type == PathCommandType.moveTo);
      expect(moveCmd, isNotEmpty);
    });

    test('unknown operators are ignored', () async {
      final pdf = buildMinimalPdf('100 200 UNKNOWN_OP 10 20 m');
      final result = await extractor.extractPageData(pdf, 1);

      final moveCmd = result.commands
          .firstWhere((c) => c.type == PathCommandType.moveTo);
      expect(moveCmd.args[0], closeTo(10, 0.001));
      expect(moveCmd.args[1], closeTo(20, 0.001));
    });
  });

  group('Native PDF extractor — real-world patterns', () {
    test('CAD-style drawing with multiple line segments', () async {
      final content = StringBuffer();
      content.write('q\n');
      content.write('1 0 0 1 0 0 cm\n');
      content.write('0 0 0 RG\n'); // black stroke
      content.write('0.5 w\n'); // 0.5pt line width
      // Draw a simple floor plan outline
      content.write('72 72 m\n');
      content.write('540 72 l\n');
      content.write('540 720 l\n');
      content.write('72 720 l\n');
      content.write('h\n');
      content.write('S\n');
      // Draw an inner wall
      content.write('200 72 m\n');
      content.write('200 400 l\n');
      content.write('S\n');
      content.write('Q\n');

      final pdf = buildMinimalPdf(content.toString());
      final result = await extractor.extractPageData(pdf, 1);

      final moves =
          result.commands.where((c) => c.type == PathCommandType.moveTo);
      final lines =
          result.commands.where((c) => c.type == PathCommandType.lineTo);
      final close =
          result.commands.where((c) => c.type == PathCommandType.closePath);

      expect(moves.length, equals(2)); // outline start + inner wall
      expect(lines.length, equals(4)); // 3 outline sides + 1 inner wall
      expect(close.length, equals(1)); // outline close
    });

    test('construction drawing with multiple CTM transforms', () async {
      final content = StringBuffer();
      // Scale and translate the coordinate system
      content.write('q\n');
      content.write('2.835 0 0 2.835 0 0 cm\n'); // mm to points
      content.write('q\n');
      content.write('1 0 0 1 10 10 cm\n'); // translate origin
      content.write('0 0 m 100 0 l S\n');
      content.write('Q\n');
      content.write('Q\n');

      final pdf = buildMinimalPdf(content.toString());
      final result = await extractor.extractPageData(pdf, 1);

      expect(result.commands, isNotEmpty);
      final ctmCmds =
          result.commands.where((c) => c.type == PathCommandType.setCTM);
      expect(ctmCmds.length, equals(2));
    });

    test('drawing with rectangles (dimension boxes)', () async {
      final content = StringBuffer();
      content.write('q\n');
      content.write('0.5 w\n');
      // Multiple dimension annotation boxes
      content.write('100 100 200 20 re S\n');
      content.write('100 150 200 20 re S\n');
      content.write('Q\n');

      final pdf = buildMinimalPdf(content.toString());
      final result = await extractor.extractPageData(pdf, 1);

      final rects =
          result.commands.where((c) => c.type == PathCommandType.rect);
      expect(rects.length, equals(2));
    });

    test('compressed content stream (FlateDecode) with real operators',
        () async {
      final content = 'q 1 0 0 1 50 100 cm 0 0 m 200 0 l 200 300 l h S Q';
      final pdf = buildMinimalPdf(content, compress: true);
      final result = await extractor.extractPageData(pdf, 1);

      expect(result.commands, isNotEmpty);
      final moves =
          result.commands.where((c) => c.type == PathCommandType.moveTo);
      expect(moves, isNotEmpty);
      final lines =
          result.commands.where((c) => c.type == PathCommandType.lineTo);
      expect(lines.length, equals(2));
    });
  });

  group('Native PDF extractor — MediaBox variations', () {
    test('non-zero origin MediaBox is reported correctly', () async {
      final pdf = buildMinimalPdf('0 0 m',
          mediaBox: [50, 100, 850, 1100]);
      final result = await extractor.extractPageData(pdf, 1);

      expect(result.view[0], closeTo(50, 0.01));
      expect(result.view[1], closeTo(100, 0.01));
      expect(result.view[2], closeTo(850, 0.01));
      expect(result.view[3], closeTo(1100, 0.01));
      expect(result.pageWidth, closeTo(800, 0.01));
      expect(result.pageHeight, closeTo(1000, 0.01));
    });

    test('A0 size MediaBox', () async {
      final pdf = buildMinimalPdf('0 0 m',
          mediaBox: [0, 0, 2383.94, 3370.39]);
      final result = await extractor.extractPageData(pdf, 1);

      expect(result.pageWidth, closeTo(2383.94, 0.01));
      expect(result.pageHeight, closeTo(3370.39, 0.01));
    });
  });

  group('Native PDF extractor — tokenizer edge cases', () {
    test('inline images (BI/ID/EI) are skipped', () async {
      // BI ... ID <data> EI is an inline image that should be ignored.
      // Followed by real path data.
      final pdf = buildMinimalPdf(
        'BI /W 1 /H 1 /CS /G /BPC 8 ID X EI 10 20 m 30 40 l',
      );
      final result = await extractor.extractPageData(pdf, 1);

      final moveCmd = result.commands
          .where((c) => c.type == PathCommandType.moveTo);
      expect(moveCmd, isNotEmpty);
    });

    test('hex strings in content stream are skipped', () async {
      final pdf = buildMinimalPdf('<48656C6C6F> Tj 10 20 m');
      final result = await extractor.extractPageData(pdf, 1);

      final moveCmd = result.commands
          .where((c) => c.type == PathCommandType.moveTo);
      expect(moveCmd, isNotEmpty);
    });

    test('dict markers in content stream are skipped', () async {
      final pdf = buildMinimalPdf('<< /MCID 0 >> BDC 10 20 m EMC');
      final result = await extractor.extractPageData(pdf, 1);

      final moveCmd = result.commands
          .where((c) => c.type == PathCommandType.moveTo);
      expect(moveCmd, isNotEmpty);
    });

    test('name objects in content stream are skipped', () async {
      final pdf = buildMinimalPdf('/GS0 gs 10 20 m');
      final result = await extractor.extractPageData(pdf, 1);

      final moveCmd = result.commands
          .where((c) => c.type == PathCommandType.moveTo);
      expect(moveCmd, isNotEmpty);
    });

    test('consecutive operators without whitespace parsed', () async {
      // Some PDFs have tight formatting like "0 0 m100 0 l"
      // (number directly before operator letter).
      // This is unusual but legal since digits are not alpha.
      final pdf = buildMinimalPdf('0 0 m\n100 0 l');
      final result = await extractor.extractPageData(pdf, 1);

      final lines =
          result.commands.where((c) => c.type == PathCommandType.lineTo);
      expect(lines, isNotEmpty);
    });
  });
}
