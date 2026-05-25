import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<File> _getFile(String filePath) async {
  final dir = await getApplicationDocumentsDirectory();
  final safeKey = filePath.hashCode.toRadixString(16);
  return File('${dir.path}/pdf_graph_$safeKey.json');
}

Future<void> saveProject(String filePath, String jsonContent) async {
  final file = await _getFile(filePath);
  await file.writeAsString(jsonContent);
}

Future<String?> loadProject(String filePath) async {
  try {
    final file = await _getFile(filePath);
    if (!await file.exists()) return null;
    return await file.readAsString();
  } catch (_) {
    return null;
  }
}

Future<File> _recentFile() async {
  final dir = await getApplicationDocumentsDirectory();
  return File('${dir.path}/pdf_graph_recent.json');
}

Future<void> saveRecentProjects(String jsonContent) async {
  final file = await _recentFile();
  await file.writeAsString(jsonContent);
}

Future<String?> loadRecentProjects() async {
  try {
    final file = await _recentFile();
    if (!await file.exists()) return null;
    return await file.readAsString();
  } catch (_) {
    return null;
  }
}
