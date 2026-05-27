import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'page_extract_result.dart';
import 'path_operators.dart';

/// Pure-Dart PDF content stream parser for non-web (Desktop / Android).
///
/// Parses the raw PDF binary to locate page objects, decompress their content
/// streams, and tokenize path operators into [PathCommand] objects.
Future<PageExtractResult> extractPageData(
  Uint8List pdfBytes,
  int pageNumber,
) async {
  try {
    final parser = _PdfParser(pdfBytes);
    return parser.extractPage(pageNumber);
  } catch (_) {
    return PageExtractResult(const [], [0, 0, 0, 0]);
  }
}

// ---------------------------------------------------------------------------
// PDF object model
// ---------------------------------------------------------------------------

/// A parsed PDF object value.
sealed class _PdfObj {}

class _PdfNull extends _PdfObj {
  @override
  String toString() => 'null';
}

class _PdfBool extends _PdfObj {
  final bool value;
  _PdfBool(this.value);
  @override
  String toString() => '$value';
}

class _PdfNum extends _PdfObj {
  final double value;
  _PdfNum(this.value);
  int get intValue => value.toInt();
  @override
  String toString() => '$value';
}

class _PdfString extends _PdfObj {
  final String value;
  _PdfString(this.value);
  @override
  String toString() => '($value)';
}

class _PdfName extends _PdfObj {
  final String name;
  _PdfName(this.name);
  @override
  String toString() => '/$name';
}

class _PdfArray extends _PdfObj {
  final List<_PdfObj> items;
  _PdfArray(this.items);
  @override
  String toString() => '[$items]';
}

class _PdfDict extends _PdfObj {
  final Map<String, _PdfObj> map;
  _PdfDict(this.map);

  _PdfObj? operator [](String key) => map[key];

  int? getInt(String key) {
    final v = map[key];
    if (v is _PdfNum) return v.intValue;
    return null;
  }

  String? getName(String key) {
    final v = map[key];
    if (v is _PdfName) return v.name;
    return null;
  }

  List<double>? getNumberArray(String key) {
    final v = map[key];
    if (v is _PdfArray) {
      return v.items
          .whereType<_PdfNum>()
          .map((n) => n.value)
          .toList();
    }
    return null;
  }

  @override
  String toString() => '<<$map>>';
}

class _PdfRef extends _PdfObj {
  final int objNum;
  final int gen;
  _PdfRef(this.objNum, this.gen);
  @override
  String toString() => '$objNum $gen R';
}

/// A stream object: dictionary + raw bytes.
class _PdfStream {
  final _PdfDict dict;
  final Uint8List rawBytes;
  _PdfStream(this.dict, this.rawBytes);
}

// ---------------------------------------------------------------------------
// PDF parser
// ---------------------------------------------------------------------------

class _PdfParser {
  final Uint8List bytes;
  int _pos = 0;

  _PdfParser(this.bytes);

  // Object cache: objNum -> parsed object (or _PdfStream).
  final Map<int, Object> _objectCache = {};

  // xref: objNum -> file offset.
  final Map<int, int> _xref = {};

  // /Root reference captured from any trailer dictionary we encounter.
  _PdfRef? _rootRef;

  PageExtractResult extractPage(int pageNumber) {
    _buildXref();
    final root = _resolveRef(_rootRef ?? _findTrailerRoot());
    if (root is! _PdfDict) {
      return PageExtractResult(const [], [0, 0, 0, 0]);
    }

    final pages = _resolveRef(root['Pages']);
    if (pages is! _PdfDict) {
      return PageExtractResult(const [], [0, 0, 0, 0]);
    }

    final pageObj = _findPage(pages, pageNumber - 1);
    if (pageObj == null) {
      return PageExtractResult(const [], [0, 0, 0, 0]);
    }

    // Determine the page view (CropBox > MediaBox).
    final view = _getPageBox(pageObj, 'CropBox') ??
        _getPageBox(pageObj, 'MediaBox') ??
        [0, 0, 612, 792];

    // Collect content streams.
    final contentBytes = _getContentStreamBytes(pageObj);
    if (contentBytes.isEmpty) {
      return PageExtractResult(const [], view);
    }

    final commands = _tokenize(contentBytes);
    return PageExtractResult(commands, view);
  }

  // -------------------------------------------------------------------------
  // xref parsing
  // -------------------------------------------------------------------------

  void _buildXref() {
    // Find startxref near end of file.
    final tail = bytes.length > 1024
        ? bytes.sublist(bytes.length - 1024)
        : bytes;
    final tailStr = latin1.decode(tail);
    final sxIdx = tailStr.lastIndexOf('startxref');
    if (sxIdx < 0) return;

    // Parse the offset.
    var i = sxIdx + 9;
    while (i < tailStr.length && _isWhitespaceChar(tailStr.codeUnitAt(i))) {
      i++;
    }
    var numBuf = StringBuffer();
    while (i < tailStr.length && _isDigitChar(tailStr.codeUnitAt(i))) {
      numBuf.writeCharCode(tailStr.codeUnitAt(i));
      i++;
    }
    final xrefOffset = int.tryParse(numBuf.toString());
    if (xrefOffset == null) return;

    _parseXrefAt(xrefOffset);
  }

  void _parseXrefAt(int offset) {
    _pos = offset;
    _skipWhitespace();

    // Check for cross-reference stream (an integer object number) vs table.
    if (_pos < bytes.length && _isDigit(bytes[_pos])) {
      _parseXrefStream(offset);
      return;
    }

    // Traditional xref table.
    if (!_matchKeyword('xref')) return;
    _skipWhitespace();

    while (_pos < bytes.length && _isDigit(bytes[_pos])) {
      final startObj = _readInt()!;
      _skipWhitespace();
      final count = _readInt()!;
      _skipWhitespace();

      for (var j = 0; j < count; j++) {
        final entryOffset = _readInt()!;
        _skipWhitespace();
        _readInt(); // gen
        _skipWhitespace();
        final flag = _pos < bytes.length ? bytes[_pos] : 0;
        _pos++; // 'n' or 'f'
        _skipWhitespace();

        if (flag == 0x6E) {
          // 'n'
          _xref.putIfAbsent(startObj + j, () => entryOffset);
        }
      }
    }

    // Parse trailer dictionary.
    _skipWhitespace();
    if (_matchKeyword('trailer')) {
      _skipWhitespace();
      final trailerDict = _readObject();
      if (trailerDict is _PdfDict) {
        // Capture /Root if present and we haven't seen one yet.
        final rootObj = trailerDict['Root'];
        if (rootObj is _PdfRef) {
          _rootRef ??= rootObj;
        }
        final prev = trailerDict.getInt('Prev');
        if (prev != null) {
          _parseXrefAt(prev);
        }
      }
    }
  }

  void _parseXrefStream(int offset) {
    _pos = offset;
    final obj = _readIndirectObject();
    if (obj is! _PdfStream) return;

    final dict = obj.dict;
    final decoded = _decodeStream(dict, obj.rawBytes);

    final size = dict.getInt('Size') ?? 0;
    final wArr = dict.getNumberArray('W');
    if (wArr == null || wArr.length < 3) return;
    final w = wArr.map((e) => e.toInt()).toList();

    final indexArr = dict.getNumberArray('Index');
    final sections = <List<int>>[];
    if (indexArr != null && indexArr.length >= 2) {
      for (var i = 0; i < indexArr.length; i += 2) {
        sections.add([indexArr[i].toInt(), indexArr[i + 1].toInt()]);
      }
    } else {
      sections.add([0, size]);
    }

    final entrySize = w[0] + w[1] + w[2];
    var dataPos = 0;

    for (final section in sections) {
      final startObj = section[0];
      final count = section[1];
      for (var j = 0; j < count; j++) {
        if (dataPos + entrySize > decoded.length) break;
        final type = w[0] > 0 ? _readXrefInt(decoded, dataPos, w[0]) : 1;
        final field2 = _readXrefInt(decoded, dataPos + w[0], w[1]);
        // field3 = _readXrefInt(decoded, dataPos + w[0] + w[1], w[2]);
        dataPos += entrySize;

        if (type == 1) {
          _xref.putIfAbsent(startObj + j, () => field2);
        }
      }
    }

    final prev = dict.getInt('Prev');
    if (prev != null) {
      _parseXrefAt(prev);
    }

    // Capture /Root if present (cross-reference streams carry trailer metadata).
    final rootObj = dict['Root'];
    if (rootObj is _PdfRef) {
      _rootRef ??= rootObj;
    }
  }

  int _readXrefInt(Uint8List data, int offset, int width) {
    var value = 0;
    for (var i = 0; i < width; i++) {
      value = (value << 8) | data[offset + i];
    }
    return value;
  }

  // -------------------------------------------------------------------------
  // Trailer root
  // -------------------------------------------------------------------------

  _PdfRef _findTrailerRoot() {
    // Search for /Root in trailer dict – scan backwards from EOF.
    final tail = bytes.length > 4096
        ? bytes.sublist(bytes.length - 4096)
        : bytes;
    final tailStr = latin1.decode(tail);

    // Check for cross-reference stream carrying /Root directly.
    for (final entry in _xref.entries) {
      final obj = _readObjectAt(entry.value);
      if (obj is _PdfStream) {
        final root = obj.dict['Root'];
        if (root is _PdfRef) return root;
      }
    }

    // Traditional trailer.
    final trailerIdx = tailStr.lastIndexOf('trailer');
    if (trailerIdx >= 0) {
      _pos = (bytes.length > 4096 ? bytes.length - 4096 : 0) + trailerIdx + 7;
      _skipWhitespace();
      final dict = _readObject();
      if (dict is _PdfDict) {
        final root = dict['Root'];
        if (root is _PdfRef) return root;
      }
    }

    return _PdfRef(0, 0);
  }

  // -------------------------------------------------------------------------
  // Page tree navigation
  // -------------------------------------------------------------------------

  _PdfDict? _findPage(_PdfDict node, int targetIndex) {
    final type = node.getName('Type');
    if (type == 'Page') {
      return targetIndex == 0 ? node : null;
    }

    // Pages node.
    final kids = _resolveRef(node['Kids']);
    if (kids is! _PdfArray) return null;

    var remaining = targetIndex;
    for (final kid in kids.items) {
      final childObj = _resolveRef(kid);
      if (childObj is! _PdfDict) continue;

      final childType = childObj.getName('Type');
      if (childType == 'Page') {
        if (remaining == 0) return childObj;
        remaining--;
      } else if (childType == 'Pages') {
        final count = childObj.getInt('Count') ?? 0;
        if (remaining < count) {
          return _findPage(childObj, remaining);
        }
        remaining -= count;
      }
    }
    return null;
  }

  // -------------------------------------------------------------------------
  // Page box
  // -------------------------------------------------------------------------

  List<double>? _getPageBox(_PdfDict page, String key) {
    final arr = page.getNumberArray(key);
    if (arr != null && arr.length >= 4) return arr.sublist(0, 4);

    // Inherit from parent.
    final parent = _resolveRef(page['Parent']);
    if (parent is _PdfDict) return _getPageBox(parent, key);
    return null;
  }

  // -------------------------------------------------------------------------
  // Content stream extraction
  // -------------------------------------------------------------------------

  Uint8List _getContentStreamBytes(_PdfDict page) {
    final contents = _resolveRefRaw(page['Contents']);

    if (contents is _PdfStream) {
      return _decodeStream(contents.dict, contents.rawBytes);
    }

    // If /Contents is an array of references, resolve each as a stream.
    final contentsObj = contents is _PdfDict ? contents : _resolveRef(page['Contents']);
    if (contentsObj is _PdfArray) {
      final buffers = <Uint8List>[];
      for (final item in contentsObj.items) {
        final resolved = _resolveRefRaw(item);
        if (resolved is _PdfStream) {
          buffers.add(_decodeStream(resolved.dict, resolved.rawBytes));
          buffers.add(Uint8List.fromList([0x0A]));
        }
      }
      if (buffers.isEmpty) return Uint8List(0);
      final total = buffers.fold<int>(0, (s, b) => s + b.length);
      final combined = Uint8List(total);
      var offset = 0;
      for (final b in buffers) {
        combined.setRange(offset, offset + b.length, b);
        offset += b.length;
      }
      return combined;
    }

    return Uint8List(0);
  }

  Uint8List _decodeStream(_PdfDict dict, Uint8List raw) {
    final filter = dict['Filter'];
    final filterName = filter is _PdfName
        ? filter.name
        : (filter is _PdfArray && filter.items.isNotEmpty && filter.items[0] is _PdfName)
            ? (filter.items[0] as _PdfName).name
            : null;

    if (filterName == 'FlateDecode' || filterName == 'Fl') {
      try {
        return Uint8List.fromList(zlib.decode(raw));
      } catch (_) {
        // Try raw deflate (no zlib header) as fallback.
        try {
          final codec = ZLibCodec(raw: true);
          return Uint8List.fromList(codec.decode(raw));
        } catch (_) {
          return raw;
        }
      }
    }

    // No filter or unrecognised – return raw.
    return raw;
  }

  // -------------------------------------------------------------------------
  // Object reading
  // -------------------------------------------------------------------------

  _PdfObj _resolveRef(_PdfObj? obj) {
    if (obj is _PdfRef) {
      final cached = _objectCache[obj.objNum];
      if (cached is _PdfObj) return cached;
      if (cached is _PdfStream) return cached.dict;

      final offset = _xref[obj.objNum];
      if (offset == null) return _PdfNull();

      final parsed = _readObjectAt(offset);
      _objectCache[obj.objNum] = parsed;
      if (parsed is _PdfObj) return parsed;
      if (parsed is _PdfStream) return parsed.dict;
      return _PdfNull();
    }
    return obj ?? _PdfNull();
  }

  Object _resolveRefRaw(_PdfObj? obj) {
    if (obj is _PdfRef) {
      final cached = _objectCache[obj.objNum];
      if (cached != null) return cached;

      final offset = _xref[obj.objNum];
      if (offset == null) return _PdfNull();

      final parsed = _readObjectAt(offset);
      _objectCache[obj.objNum] = parsed;
      return parsed;
    }
    return obj ?? _PdfNull();
  }

  /// Read an indirect object at the given file offset.
  /// Returns either a _PdfObj or a _PdfStream.
  Object _readObjectAt(int offset) {
    _pos = offset;
    return _readIndirectObject();
  }

  /// Parse `<objNum> <gen> obj ... endobj` and return the value or stream.
  Object _readIndirectObject() {
    _skipWhitespace();
    _readInt(); // objNum
    _skipWhitespace();
    _readInt(); // gen
    _skipWhitespace();
    _matchKeyword('obj');
    _skipWhitespace();

    final value = _readObject();

    _skipWhitespace();

    // Check for stream.
    if (value is _PdfDict && _matchKeyword('stream')) {
      // Skip the single EOL after 'stream' keyword.
      if (_pos < bytes.length && bytes[_pos] == 0x0D) _pos++; // CR
      if (_pos < bytes.length && bytes[_pos] == 0x0A) _pos++; // LF

      final length = _resolveStreamLength(value);
      final streamEnd = (_pos + length).clamp(0, bytes.length);
      final raw = bytes.sublist(_pos, streamEnd);
      _pos = streamEnd;
      return _PdfStream(value, raw);
    }

    return value;
  }

  int _resolveStreamLength(_PdfDict dict) {
    final lengthObj = dict['Length'];
    if (lengthObj is _PdfNum) return lengthObj.intValue;
    if (lengthObj is _PdfRef) {
      final resolved = _resolveRef(lengthObj);
      if (resolved is _PdfNum) return resolved.intValue;
    }
    // Fallback: scan for 'endstream'.
    final marker = latin1.encode('endstream');
    for (var i = _pos; i < bytes.length - marker.length; i++) {
      var found = true;
      for (var j = 0; j < marker.length; j++) {
        if (bytes[i + j] != marker[j]) {
          found = false;
          break;
        }
      }
      if (found) return i - _pos;
    }
    return 0;
  }

  // -------------------------------------------------------------------------
  // Object parser (recursive descent)
  // -------------------------------------------------------------------------

  _PdfObj _readObject() {
    _skipWhitespace();
    if (_pos >= bytes.length) return _PdfNull();

    final ch = bytes[_pos];

    // Dictionary or hex string.
    if (ch == 0x3C) {
      // '<'
      if (_pos + 1 < bytes.length && bytes[_pos + 1] == 0x3C) {
        return _readDict();
      }
      return _readHexString();
    }

    // Array.
    if (ch == 0x5B) return _readArray(); // '['

    // Name.
    if (ch == 0x2F) return _readName(); // '/'

    // String literal.
    if (ch == 0x28) return _readLiteralString(); // '('

    // Number or indirect reference.
    if (_isDigit(ch) || ch == 0x2D || ch == 0x2E || ch == 0x2B) {
      return _readNumberOrRef();
    }

    // Boolean / null.
    if (_matchKeyword('true')) return _PdfBool(true);
    if (_matchKeyword('false')) return _PdfBool(false);
    if (_matchKeyword('null')) return _PdfNull();

    // Unknown – skip one byte to avoid infinite loop.
    _pos++;
    return _PdfNull();
  }

  _PdfDict _readDict() {
    _pos += 2; // skip '<<'
    final map = <String, _PdfObj>{};
    _skipWhitespace();

    while (_pos < bytes.length) {
      _skipWhitespace();
      if (_pos + 1 < bytes.length &&
          bytes[_pos] == 0x3E &&
          bytes[_pos + 1] == 0x3E) {
        _pos += 2;
        break;
      }
      if (bytes[_pos] != 0x2F) {
        // Not a name – bail.
        _pos++;
        continue;
      }
      final name = _readName();
      _skipWhitespace();
      final value = _readObject();
      map[name.name] = value;
    }
    return _PdfDict(map);
  }

  _PdfArray _readArray() {
    _pos++; // skip '['
    final items = <_PdfObj>[];
    _skipWhitespace();
    while (_pos < bytes.length && bytes[_pos] != 0x5D) {
      items.add(_readObject());
      _skipWhitespace();
    }
    if (_pos < bytes.length) _pos++; // skip ']'
    return _PdfArray(items);
  }

  _PdfName _readName() {
    _pos++; // skip '/'
    final buf = StringBuffer();
    while (_pos < bytes.length) {
      final c = bytes[_pos];
      if (_isWhitespace(c) ||
          c == 0x2F || // '/'
          c == 0x3C || // '<'
          c == 0x3E || // '>'
          c == 0x5B || // '['
          c == 0x5D || // ']'
          c == 0x28 || // '('
          c == 0x29 || // ')'
          c == 0x7B || // '{'
          c == 0x7D) {
        // '}'
        break;
      }
      if (c == 0x23 && _pos + 2 < bytes.length) {
        // '#' hex escape
        final hi = _hexDigit(bytes[_pos + 1]);
        final lo = _hexDigit(bytes[_pos + 2]);
        if (hi >= 0 && lo >= 0) {
          buf.writeCharCode((hi << 4) | lo);
          _pos += 3;
          continue;
        }
      }
      buf.writeCharCode(c);
      _pos++;
    }
    return _PdfName(buf.toString());
  }

  _PdfString _readLiteralString() {
    _pos++; // skip '('
    final buf = StringBuffer();
    var depth = 1;
    while (_pos < bytes.length && depth > 0) {
      final c = bytes[_pos];
      if (c == 0x28) {
        depth++;
        buf.writeCharCode(c);
      } else if (c == 0x29) {
        depth--;
        if (depth > 0) buf.writeCharCode(c);
      } else if (c == 0x5C) {
        // backslash escape
        _pos++;
        if (_pos < bytes.length) {
          final esc = bytes[_pos];
          switch (esc) {
            case 0x6E:
              buf.writeCharCode(0x0A);
            case 0x72:
              buf.writeCharCode(0x0D);
            case 0x74:
              buf.writeCharCode(0x09);
            case 0x62:
              buf.writeCharCode(0x08);
            case 0x66:
              buf.writeCharCode(0x0C);
            case 0x28:
              buf.writeCharCode(0x28);
            case 0x29:
              buf.writeCharCode(0x29);
            case 0x5C:
              buf.writeCharCode(0x5C);
            default:
              buf.writeCharCode(esc);
          }
        }
      } else {
        buf.writeCharCode(c);
      }
      _pos++;
    }
    return _PdfString(buf.toString());
  }

  _PdfString _readHexString() {
    _pos++; // skip '<'
    final hex = StringBuffer();
    while (_pos < bytes.length && bytes[_pos] != 0x3E) {
      final c = bytes[_pos];
      if (!_isWhitespace(c)) hex.writeCharCode(c);
      _pos++;
    }
    if (_pos < bytes.length) _pos++; // skip '>'
    return _PdfString(hex.toString());
  }

  _PdfObj _readNumberOrRef() {
    final num1 = _readNumber();
    if (num1 == null) return _PdfNull();

    // Check for indirect reference: <int> <int> R
    if (num1 == num1.truncateToDouble() && num1 >= 0) {
      final savedPos = _pos;
      _skipWhitespace();
      if (_pos < bytes.length && _isDigit(bytes[_pos])) {
        final num2 = _readNumber();
        if (num2 != null) {
          _skipWhitespace();
          if (_pos < bytes.length && bytes[_pos] == 0x52) {
            // 'R'
            // Verify the next character is a delimiter or whitespace.
            if (_pos + 1 >= bytes.length || _isDelimiterOrWhitespace(bytes[_pos + 1])) {
              _pos++;
              return _PdfRef(num1.toInt(), num2.toInt());
            }
          }
        }
      }
      _pos = savedPos;
    }

    return _PdfNum(num1);
  }

  double? _readNumber() {
    _skipWhitespace();
    if (_pos >= bytes.length) return null;

    final buf = StringBuffer();
    if (bytes[_pos] == 0x2D || bytes[_pos] == 0x2B) {
      buf.writeCharCode(bytes[_pos]);
      _pos++;
    }
    var hasDot = false;
    while (_pos < bytes.length) {
      final c = bytes[_pos];
      if (_isDigit(c)) {
        buf.writeCharCode(c);
        _pos++;
      } else if (c == 0x2E && !hasDot) {
        hasDot = true;
        buf.writeCharCode(c);
        _pos++;
      } else {
        break;
      }
    }
    if (buf.isEmpty) return null;
    return double.tryParse(buf.toString());
  }

  int? _readInt() {
    _skipWhitespace();
    if (_pos >= bytes.length) return null;
    final buf = StringBuffer();
    if (bytes[_pos] == 0x2D || bytes[_pos] == 0x2B) {
      buf.writeCharCode(bytes[_pos]);
      _pos++;
    }
    while (_pos < bytes.length && _isDigit(bytes[_pos])) {
      buf.writeCharCode(bytes[_pos]);
      _pos++;
    }
    if (buf.isEmpty) return null;
    return int.tryParse(buf.toString());
  }

  // -------------------------------------------------------------------------
  // Content stream tokenizer → PathCommand list
  // -------------------------------------------------------------------------

  List<PathCommand> _tokenize(Uint8List stream) {
    final commands = <PathCommand>[];
    final operands = <double>[];
    var i = 0;

    while (i < stream.length) {
      final c = stream[i];

      // Skip whitespace.
      if (_isWhitespace(c)) {
        i++;
        continue;
      }

      // Skip comments.
      if (c == 0x25) {
        // '%'
        while (i < stream.length && stream[i] != 0x0A && stream[i] != 0x0D) {
          i++;
        }
        continue;
      }

      // Number.
      if (_isDigit(c) || c == 0x2D || c == 0x2E || c == 0x2B) {
        final numStart = i;
        if (c == 0x2D || c == 0x2B) i++;
        var hasDot = false;
        while (i < stream.length) {
          final nc = stream[i];
          if (_isDigit(nc)) {
            i++;
          } else if (nc == 0x2E && !hasDot) {
            hasDot = true;
            i++;
          } else {
            break;
          }
        }
        final numStr = latin1.decode(stream.sublist(numStart, i));
        final val = double.tryParse(numStr);
        if (val != null) operands.add(val);
        continue;
      }

      // Inline image: BI ... ID <data> EI — skip entirely.
      if (c == 0x42 && i + 1 < stream.length && stream[i + 1] == 0x49) {
        // 'BI'
        // Check that it's delimited.
        if (i == 0 || _isWhitespace(stream[i - 1])) {
          if (i + 2 >= stream.length || _isWhitespace(stream[i + 2])) {
            // Skip until 'EI' (preceded by whitespace).
            i += 2;
            while (i < stream.length) {
              if (stream[i] == 0x45 &&
                  i + 1 < stream.length &&
                  stream[i + 1] == 0x49 &&
                  (i + 2 >= stream.length || _isWhitespace(stream[i + 2])) &&
                  (i == 0 || _isWhitespace(stream[i - 1]))) {
                i += 2;
                break;
              }
              i++;
            }
            operands.clear();
            continue;
          }
        }
      }

      // Operator (alphabetic or single-char operators like ' and ").
      if (_isAlpha(c) || c == 0x27 || c == 0x22) {
        final opStart = i;
        while (i < stream.length &&
            !_isWhitespace(stream[i]) &&
            !_isDigit(stream[i]) &&
            stream[i] != 0x2D &&
            stream[i] != 0x2E &&
            stream[i] != 0x2F &&
            stream[i] != 0x5B &&
            stream[i] != 0x5D &&
            stream[i] != 0x3C &&
            stream[i] != 0x3E &&
            stream[i] != 0x28 &&
            stream[i] != 0x25) {
          i++;
        }
        final op = latin1.decode(stream.sublist(opStart, i));
        final cmd = _mapOperator(op, operands);
        if (cmd != null) commands.add(cmd);
        operands.clear();
        continue;
      }

      // Skip array brackets, string literals, and dict markers in content
      // streams (these appear in text/marked-content operators we ignore).
      if (c == 0x5B) {
        // '['  — skip to matching ']'
        i++;
        var depth = 1;
        while (i < stream.length && depth > 0) {
          if (stream[i] == 0x5B) depth++;
          if (stream[i] == 0x5D) depth--;
          i++;
        }
        operands.clear();
        continue;
      }

      if (c == 0x28) {
        // '(' literal string — skip balanced parens
        i++;
        var depth = 1;
        while (i < stream.length && depth > 0) {
          if (stream[i] == 0x5C) {
            i++; // skip escape
          } else if (stream[i] == 0x28) {
            depth++;
          } else if (stream[i] == 0x29) {
            depth--;
          }
          i++;
        }
        operands.clear();
        continue;
      }

      if (c == 0x3C) {
        // '<' — hex string or dict
        if (i + 1 < stream.length && stream[i + 1] == 0x3C) {
          // '<<' dict — skip to '>>'
          i += 2;
          var depth = 1;
          while (i + 1 < stream.length && depth > 0) {
            if (stream[i] == 0x3C && stream[i + 1] == 0x3C) {
              depth++;
              i += 2;
            } else if (stream[i] == 0x3E && stream[i + 1] == 0x3E) {
              depth--;
              i += 2;
            } else {
              i++;
            }
          }
        } else {
          // Hex string.
          i++;
          while (i < stream.length && stream[i] != 0x3E) {
            i++;
          }
          if (i < stream.length) i++;
        }
        operands.clear();
        continue;
      }

      if (c == 0x2F) {
        // '/' name — skip
        i++;
        while (i < stream.length &&
            !_isWhitespace(stream[i]) &&
            stream[i] != 0x2F &&
            stream[i] != 0x3C &&
            stream[i] != 0x3E &&
            stream[i] != 0x5B &&
            stream[i] != 0x5D &&
            stream[i] != 0x28) {
          i++;
        }
        continue;
      }

      // Skip unknown byte.
      i++;
    }

    return commands;
  }

  PathCommand? _mapOperator(String op, List<double> operands) {
    switch (op) {
      case 'm':
        if (operands.length >= 2) {
          return PathCommand(PathCommandType.moveTo,
              [operands[operands.length - 2], operands[operands.length - 1]]);
        }
      case 'l':
        if (operands.length >= 2) {
          return PathCommand(PathCommandType.lineTo,
              [operands[operands.length - 2], operands[operands.length - 1]]);
        }
      case 'c':
        if (operands.length >= 6) {
          return PathCommand(PathCommandType.curveTo,
              operands.sublist(operands.length - 6));
        }
      case 'v':
        if (operands.length >= 4) {
          return PathCommand(PathCommandType.curveToV,
              operands.sublist(operands.length - 4));
        }
      case 'y':
        if (operands.length >= 4) {
          return PathCommand(PathCommandType.curveToY,
              operands.sublist(operands.length - 4));
        }
      case 'h':
        return PathCommand(PathCommandType.closePath, const []);
      case 're':
        if (operands.length >= 4) {
          return PathCommand(PathCommandType.rect,
              operands.sublist(operands.length - 4));
        }
      case 'q':
        return PathCommand(PathCommandType.saveState, const []);
      case 'Q':
        return PathCommand(PathCommandType.restoreState, const []);
      case 'cm':
        if (operands.length >= 6) {
          return PathCommand(PathCommandType.setCTM,
              operands.sublist(operands.length - 6));
        }
      case 'w':
        if (operands.isNotEmpty) {
          return PathCommand(PathCommandType.setLineWidth,
              [operands[operands.length - 1]]);
        }
      case 'RG':
        if (operands.length >= 3) {
          return PathCommand(PathCommandType.setStrokeRGBColor,
              operands.sublist(operands.length - 3));
        }
      case 'G':
        if (operands.isNotEmpty) {
          return PathCommand(PathCommandType.setStrokeGray,
              [operands[operands.length - 1]]);
        }
      case 'K':
        if (operands.length >= 4) {
          return PathCommand(PathCommandType.setStrokeCMYKColor,
              operands.sublist(operands.length - 4));
        }
      case 'rg':
        if (operands.length >= 3) {
          return PathCommand(PathCommandType.setFillRGBColor,
              operands.sublist(operands.length - 3));
        }
      case 'g':
        if (operands.isNotEmpty) {
          return PathCommand(PathCommandType.setFillGray,
              [operands[operands.length - 1]]);
        }
      case 'k':
        if (operands.length >= 4) {
          return PathCommand(PathCommandType.setFillCMYKColor,
              operands.sublist(operands.length - 4));
        }
      case 'd':
        // dash pattern: args = dashArray + dashPhase (already flat in operands)
        return PathCommand(PathCommandType.setDash, List.from(operands));
    }
    return null;
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  void _skipWhitespace() {
    while (_pos < bytes.length) {
      final c = bytes[_pos];
      if (_isWhitespace(c)) {
        _pos++;
      } else if (c == 0x25) {
        // '%' comment – skip to EOL
        while (_pos < bytes.length &&
            bytes[_pos] != 0x0A &&
            bytes[_pos] != 0x0D) {
          _pos++;
        }
      } else {
        break;
      }
    }
  }

  bool _matchKeyword(String keyword) {
    if (_pos + keyword.length > bytes.length) return false;
    for (var i = 0; i < keyword.length; i++) {
      if (bytes[_pos + i] != keyword.codeUnitAt(i)) return false;
    }
    // Ensure the keyword ends at a delimiter or EOF.
    if (_pos + keyword.length < bytes.length) {
      final next = bytes[_pos + keyword.length];
      if (!_isWhitespace(next) && !_isDelimiter(next)) return false;
    }
    _pos += keyword.length;
    return true;
  }

  static bool _isWhitespace(int c) =>
      c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0x00 || c == 0x0C;

  static bool _isWhitespaceChar(int c) => _isWhitespace(c);

  static bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

  static bool _isDigitChar(int c) => _isDigit(c);

  static bool _isAlpha(int c) =>
      (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);

  static bool _isDelimiter(int c) =>
      c == 0x28 || c == 0x29 || c == 0x3C || c == 0x3E ||
      c == 0x5B || c == 0x5D || c == 0x7B || c == 0x7D || c == 0x2F || c == 0x25;

  static bool _isDelimiterOrWhitespace(int c) =>
      _isWhitespace(c) || _isDelimiter(c);

  static int _hexDigit(int c) {
    if (c >= 0x30 && c <= 0x39) return c - 0x30;
    if (c >= 0x41 && c <= 0x46) return c - 0x41 + 10;
    if (c >= 0x61 && c <= 0x66) return c - 0x61 + 10;
    return -1;
  }
}
