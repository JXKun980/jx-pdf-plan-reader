import 'dart:typed_data';

import 'page_extract_result.dart';

/// Stub implementation for non-web platforms.
Future<PageExtractResult> extractPageData(
  Uint8List pdfBytes,
  int pageNumber,
) async {
  return PageExtractResult(const [], [0, 0, 0, 0]);
}
