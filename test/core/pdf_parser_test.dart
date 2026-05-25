import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_graph_app/core/pdf_parser/path_operators.dart';
import 'package:pdf_graph_app/core/pdf_parser/pdf_path_extractor.dart';
import 'package:pdf_graph_app/core/pdf_parser/page_classifier.dart';

void main() {
  group('PathOperatorParser', () {
    group('basic operators', () {
      test('parse moveTo', () {
        final commands = PathOperatorParser.parse('100 200 m');
        expect(commands, hasLength(1));
        expect(commands[0].type, PathCommandType.moveTo);
        expect(commands[0].args[0], closeTo(100, 0.001));
        expect(commands[0].args[1], closeTo(200, 0.001));
      });

      test('parse lineTo', () {
        final commands = PathOperatorParser.parse('100 200 m 300 400 l');
        expect(commands, hasLength(2));
        expect(commands[0].type, PathCommandType.moveTo);
        expect(commands[1].type, PathCommandType.lineTo);
        expect(commands[1].args[0], closeTo(300, 0.001));
        expect(commands[1].args[1], closeTo(400, 0.001));
      });

      test('parse curveTo', () {
        final commands = PathOperatorParser.parse('0 0 m 10 20 30 40 50 60 c');
        expect(commands, hasLength(2));
        expect(commands[0].type, PathCommandType.moveTo);
        expect(commands[1].type, PathCommandType.curveTo);
        expect(commands[1].args, hasLength(6));
        expect(commands[1].args[0], closeTo(10, 0.001));
        expect(commands[1].args[1], closeTo(20, 0.001));
        expect(commands[1].args[2], closeTo(30, 0.001));
        expect(commands[1].args[3], closeTo(40, 0.001));
        expect(commands[1].args[4], closeTo(50, 0.001));
        expect(commands[1].args[5], closeTo(60, 0.001));
      });

      test('parse closePath', () {
        final commands =
            PathOperatorParser.parse('0 0 m 100 0 l 100 100 l h');
        expect(commands, hasLength(4));
        expect(commands[0].type, PathCommandType.moveTo);
        expect(commands[1].type, PathCommandType.lineTo);
        expect(commands[2].type, PathCommandType.lineTo);
        expect(commands[3].type, PathCommandType.closePath);
        expect(commands[3].args, isEmpty);
      });

      test('parse rect', () {
        final commands = PathOperatorParser.parse('10 20 100 50 re');
        expect(commands, hasLength(1));
        expect(commands[0].type, PathCommandType.rect);
        expect(commands[0].args[0], closeTo(10, 0.001));
        expect(commands[0].args[1], closeTo(20, 0.001));
        expect(commands[0].args[2], closeTo(100, 0.001));
        expect(commands[0].args[3], closeTo(50, 0.001));
      });
    });

    group('multiple paths', () {
      test('multiple paths in sequence', () {
        final commands = PathOperatorParser.parse(
          '0 0 m 100 0 l S 200 200 m 300 300 l',
        );
        expect(commands, hasLength(4));
        expect(commands[0].type, PathCommandType.moveTo);
        expect(commands[1].type, PathCommandType.lineTo);
        expect(commands[2].type, PathCommandType.moveTo);
        expect(commands[2].args[0], closeTo(200, 0.001));
        expect(commands[2].args[1], closeTo(200, 0.001));
        expect(commands[3].type, PathCommandType.lineTo);
      });
    });

    group('stack behaviour', () {
      test('stroke operators clear the number stack', () {
        final commands = PathOperatorParser.parse('1 2 3 S 4 5 m');
        expect(commands, hasLength(1));
        expect(commands[0].type, PathCommandType.moveTo);
        expect(commands[0].args[0], closeTo(4, 0.001));
        expect(commands[0].args[1], closeTo(5, 0.001));
      });

      test('unknown operators clear the stack', () {
        final commands =
            PathOperatorParser.parse('1 2 3 UNKNOWN_OP 4 5 m');
        expect(commands, hasLength(1));
        expect(commands[0].type, PathCommandType.moveTo);
        expect(commands[0].args[0], closeTo(4, 0.001));
        expect(commands[0].args[1], closeTo(5, 0.001));
      });
    });

    group('tokenizer edge cases', () {
      test('comments are skipped', () {
        final commands =
            PathOperatorParser.parse('100 200 m % comment\n300 400 l');
        expect(commands, hasLength(2));
        expect(commands[0].type, PathCommandType.moveTo);
        expect(commands[1].type, PathCommandType.lineTo);
        expect(commands[1].args[0], closeTo(300, 0.001));
        expect(commands[1].args[1], closeTo(400, 0.001));
      });

      test('string literals are skipped', () {
        final commands =
            PathOperatorParser.parse('100 200 m (text) Tj 300 400 l');
        expect(commands, hasLength(2));
        expect(commands[0].type, PathCommandType.moveTo);
        expect(commands[1].type, PathCommandType.lineTo);
        expect(commands[1].args[0], closeTo(300, 0.001));
        expect(commands[1].args[1], closeTo(400, 0.001));
      });

      test('empty input returns empty list', () {
        final commands = PathOperatorParser.parse('');
        expect(commands, isEmpty);
      });

      test('CR-only comments are handled', () {
        final commands =
            PathOperatorParser.parse('100 200 m % comment\r300 400 l');
        expect(commands, hasLength(2));
        expect(commands[0].type, PathCommandType.moveTo);
        expect(commands[1].type, PathCommandType.lineTo);
      });

      test('sign transitions split tokens: 100-200 becomes 100 and -200', () {
        final commands = PathOperatorParser.parse('100-200 m');
        expect(commands, hasLength(1));
        expect(commands[0].type, PathCommandType.moveTo);
        expect(commands[0].args[0], closeTo(100, 0.001));
        expect(commands[0].args[1], closeTo(-200, 0.001));
      });

      test('v operator is parsed with 4 args', () {
        final commands = PathOperatorParser.parse('0 0 m 10 20 30 40 v');
        expect(commands, hasLength(2));
        expect(commands[1].type, PathCommandType.curveToV);
        expect(commands[1].args, hasLength(4));
      });

      test('y operator is parsed with 4 args', () {
        final commands = PathOperatorParser.parse('0 0 m 10 20 30 40 y');
        expect(commands, hasLength(2));
        expect(commands[1].type, PathCommandType.curveToY);
        expect(commands[1].args, hasLength(4));
      });

      test('q/Q emit saveState/restoreState', () {
        final commands = PathOperatorParser.parse('q 0 0 m Q');
        expect(commands[0].type, PathCommandType.saveState);
        expect(commands[1].type, PathCommandType.moveTo);
        expect(commands[2].type, PathCommandType.restoreState);
      });

      test('cm emits setCTM with 6 args', () {
        final commands = PathOperatorParser.parse('1 0 0 1 50 100 cm');
        expect(commands, hasLength(1));
        expect(commands[0].type, PathCommandType.setCTM);
        expect(commands[0].args, hasLength(6));
        expect(commands[0].args[4], closeTo(50, 0.001));
        expect(commands[0].args[5], closeTo(100, 0.001));
      });
    });
  });

  group('PdfPathExtractor', () {
    group('line extraction', () {
      test('simple line path', () {
        final result = PdfPathExtractor.extract('0 0 m 100 0 l');
        expect(result.lines, hasLength(1));
        expect(result.lines[0].start.x, closeTo(0, 0.001));
        expect(result.lines[0].start.y, closeTo(0, 0.001));
        expect(result.lines[0].end.x, closeTo(100, 0.001));
        expect(result.lines[0].end.y, closeTo(0, 0.001));
      });

      test('rectangle produces 4 line segments', () {
        final result = PdfPathExtractor.extract('0 0 100 50 re');
        expect(result.lines, hasLength(4));
        // Bottom edge
        expect(result.lines[0].start.x, closeTo(0, 0.001));
        expect(result.lines[0].start.y, closeTo(0, 0.001));
        expect(result.lines[0].end.x, closeTo(100, 0.001));
        expect(result.lines[0].end.y, closeTo(0, 0.001));
        // Right edge
        expect(result.lines[1].start.x, closeTo(100, 0.001));
        expect(result.lines[1].start.y, closeTo(0, 0.001));
        expect(result.lines[1].end.x, closeTo(100, 0.001));
        expect(result.lines[1].end.y, closeTo(50, 0.001));
        // Top edge
        expect(result.lines[2].start.x, closeTo(100, 0.001));
        expect(result.lines[2].start.y, closeTo(50, 0.001));
        expect(result.lines[2].end.x, closeTo(0, 0.001));
        expect(result.lines[2].end.y, closeTo(50, 0.001));
        // Left edge
        expect(result.lines[3].start.x, closeTo(0, 0.001));
        expect(result.lines[3].start.y, closeTo(50, 0.001));
        expect(result.lines[3].end.x, closeTo(0, 0.001));
        expect(result.lines[3].end.y, closeTo(0, 0.001));
      });

      test('closed triangle produces 3 line segments', () {
        final result =
            PdfPathExtractor.extract('0 0 m 100 0 l 50 100 l h');
        expect(result.lines, hasLength(3));
        // Side 1: (0,0) → (100,0)
        expect(result.lines[0].start.x, closeTo(0, 0.001));
        expect(result.lines[0].end.x, closeTo(100, 0.001));
        // Side 2: (100,0) → (50,100)
        expect(result.lines[1].start.x, closeTo(100, 0.001));
        expect(result.lines[1].end.x, closeTo(50, 0.001));
        // Side 3 (close): (50,100) → (0,0)
        expect(result.lines[2].start.x, closeTo(50, 0.001));
        expect(result.lines[2].end.x, closeTo(0, 0.001));
      });

      test('degenerate lines (length < 0.5) are filtered out', () {
        // Two points only 0.1 apart → should be filtered
        final result = PdfPathExtractor.extract('0 0 m 0.1 0 l');
        expect(result.lines, isEmpty);
      });
    });

    group('arc extraction', () {
      test('bezier approximating a quarter circle produces an ArcSegment', () {
        // Standard cubic bezier approximation of a quarter circle of radius 100
        // Using the kappa constant (4*(sqrt(2)-1)/3 ≈ 0.5522847498)
        const r = 100.0;
        const k = 0.5522847498;
        final content = '$r 0 m '
            '$r ${r * k} ${r * k} $r 0 $r c';
        final result = PdfPathExtractor.extract(content);
        expect(result.arcs, hasLength(1));
        expect(result.arcs[0].radius, closeTo(r, 2.0));
        expect(result.arcs[0].center.x, closeTo(0, 2.0));
        expect(result.arcs[0].center.y, closeTo(0, 2.0));
      });
    });

    group('CTM transforms', () {
      test('cm applies translation to line coordinates', () {
        // Translate by (50, 100), then draw a line from (0,0) to (10,0)
        const content = 'q 1 0 0 1 50 100 cm 0 0 m 10 0 l Q';
        final result = PdfPathExtractor.extract(content);
        expect(result.lines, hasLength(1));
        expect(result.lines[0].start.x, closeTo(50, 0.001));
        expect(result.lines[0].start.y, closeTo(100, 0.001));
        expect(result.lines[0].end.x, closeTo(60, 0.001));
        expect(result.lines[0].end.y, closeTo(100, 0.001));
      });

      test('nested q/Q restores previous CTM', () {
        // Outer translate (10,0), inner translate (0,20), draw inside, restore, draw outside
        const content = 'q 1 0 0 1 10 0 cm '
            'q 1 0 0 1 0 20 cm 0 0 m 5 0 l Q '
            '0 0 m 5 0 l Q';
        final result = PdfPathExtractor.extract(content);
        expect(result.lines, hasLength(2));
        // Inner line: translated by (10+0, 0+20) = (10, 20)
        expect(result.lines[0].start.x, closeTo(10, 0.001));
        expect(result.lines[0].start.y, closeTo(20, 0.001));
        // Outer line: translated by (10, 0) only
        expect(result.lines[1].start.x, closeTo(10, 0.001));
        expect(result.lines[1].start.y, closeTo(0, 0.001));
      });

      test('cm with scale transforms coordinates', () {
        // Scale by 2x
        const content = 'q 2 0 0 2 0 0 cm 10 10 m 20 10 l Q';
        final result = PdfPathExtractor.extract(content);
        expect(result.lines, hasLength(1));
        expect(result.lines[0].start.x, closeTo(20, 0.001));
        expect(result.lines[0].start.y, closeTo(20, 0.001));
        expect(result.lines[0].end.x, closeTo(40, 0.001));
        expect(result.lines[0].end.y, closeTo(20, 0.001));
      });
    });

    group('v and y operators', () {
      test('v operator uses current point as cp1', () {
        // v: cp1 = currentPoint, cp2 = (50,50), end = (100,0)
        const content = '0 0 m 50 50 100 0 v';
        final result = PdfPathExtractor.extract(content);
        // Should produce either an arc or line segments
        expect(result.lines.isNotEmpty || result.arcs.isNotEmpty, isTrue);
      });

      test('y operator uses end point as cp2', () {
        // y: cp1 = (50,50), end = cp2 = (100,0)
        const content = '0 0 m 50 50 100 0 y';
        final result = PdfPathExtractor.extract(content);
        expect(result.lines.isNotEmpty || result.arcs.isNotEmpty, isTrue);
      });
    });

    group('degenerate rect filtering', () {
      test('zero-width rect filters degenerate edges', () {
        // width = 0, so top and bottom edges are degenerate
        const content = '10 20 0 50 re';
        final result = PdfPathExtractor.extract(content);
        // Only left and right edges (vertical) should remain
        expect(result.lines, hasLength(2));
      });
    });

    group('edge cases', () {
      test('empty content returns empty result', () {
        final result = PdfPathExtractor.extract('');
        expect(result.lines, isEmpty);
        expect(result.arcs, isEmpty);
      });
    });

    group('ExtractedPaths', () {
      test('isEmpty is true when no lines or arcs', () {
        final result = PdfPathExtractor.extract('');
        expect(result.isEmpty, isTrue);
        expect(result.isNotEmpty, isFalse);
      });

      test('isNotEmpty is true when lines exist', () {
        final result = PdfPathExtractor.extract('0 0 m 100 0 l');
        expect(result.isNotEmpty, isTrue);
        expect(result.isEmpty, isFalse);
      });
    });
  });

  group('PageClassifier', () {
    test('content with many path commands returns true', () {
      // Generate 15 moveTo+lineTo pairs = 30 path commands (≥ 10)
      final buffer = StringBuffer();
      for (var i = 0; i < 15; i++) {
        buffer.write('${i * 10} ${i * 10} m ${(i + 1) * 10} ${(i + 1) * 10} l ');
      }
      expect(PageClassifier.isVectorPage(buffer.toString()), isTrue);
    });

    test('content with fewer than 10 path commands returns false', () {
      // 3 moveTo + 3 lineTo = 6 path commands (< 10)
      const content = '0 0 m 10 0 l 20 0 m 30 0 l 40 0 m 50 0 l';
      expect(PageClassifier.isVectorPage(content), isFalse);
    });

    test('empty content returns false', () {
      expect(PageClassifier.isVectorPage(''), isFalse);
    });
  });
}
