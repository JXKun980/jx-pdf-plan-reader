import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/project.dart';
import '../models/page_data.dart';
import '../models/measurement.dart';
import '../models/detected_element.dart';
import '../core/calibration/scale.dart';
import '../core/geometry/point2d.dart';
import '../core/geometry/intersections.dart';

// Conditional import for file I/O (not available on web)
import 'project_persistence_stub.dart'
    if (dart.library.io) 'project_persistence_io.dart' as persistence;

final projectProvider =
    StateNotifierProvider<ProjectNotifier, Project?>((ref) {
  return ProjectNotifier();
});

// ---------------------------------------------------------------------------
// Recent projects registry
// ---------------------------------------------------------------------------

class RecentProjectEntry {
  final String filePath;
  final String fileName;
  final DateTime lastOpened;

  const RecentProjectEntry({
    required this.filePath,
    required this.fileName,
    required this.lastOpened,
  });

  Map<String, dynamic> toJson() => {
        'filePath': filePath,
        'fileName': fileName,
        'lastOpened': lastOpened.toIso8601String(),
      };

  factory RecentProjectEntry.fromJson(Map<String, dynamic> json) =>
      RecentProjectEntry(
        filePath: json['filePath'] as String,
        fileName: json['fileName'] as String,
        lastOpened: DateTime.parse(json['lastOpened'] as String),
      );
}

final recentProjectsProvider =
    StateNotifierProvider<RecentProjectsNotifier, List<RecentProjectEntry>>(
        (ref) {
  return RecentProjectsNotifier();
});

class RecentProjectsNotifier
    extends StateNotifier<List<RecentProjectEntry>> {
  RecentProjectsNotifier() : super(const []) {
    _load();
  }

  Future<void> _load() async {
    if (kIsWeb) return;
    try {
      final content = await persistence.loadRecentProjects();
      if (content == null) return;
      final list = jsonDecode(content) as List<dynamic>;
      state = list
          .map((e) =>
              RecentProjectEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      // Ignore corrupt data.
    }
  }

  Future<void> addEntry(String filePath, String fileName) async {
    final entries = state.where((e) => e.filePath != filePath).toList();
    entries.insert(
      0,
      RecentProjectEntry(
        filePath: filePath,
        fileName: fileName,
        lastOpened: DateTime.now(),
      ),
    );
    // Keep at most 100 entries.
    if (entries.length > 100) entries.removeRange(100, entries.length);
    state = entries;
    await _save();
  }

  Future<void> removeEntry(String filePath) async {
    state = state.where((e) => e.filePath != filePath).toList();
    await _save();
  }

  Future<void> _save() async {
    if (kIsWeb) return;
    final json = state.map((e) => e.toJson()).toList();
    await persistence.saveRecentProjects(jsonEncode(json));
  }
}

class ProjectNotifier extends StateNotifier<Project?> {
  ProjectNotifier() : super(null);

  Future<void>? _pendingSave;
  bool _saveDirty = false;

  Future<void> loadProject(
    String filePath,
    String fileName,
    int pageCount,
  ) async {
    // Try to restore a previously saved project for this file.
    final existing = await _loadFromDisk(filePath);
    if (existing != null) {
      state = existing;
      return;
    }

    final now = DateTime.now();
    state = Project(
      id: const Uuid().v4(),
      filePath: filePath,
      fileName: fileName,
      pageCount: pageCount,
      createdAt: now,
      updatedAt: now,
    );
    await _saveToDisk();
  }

  void closeProject() {
    state = null;
  }

  Future<void> updatePage(int pageIndex, PageData pageData) async {
    final project = state;
    if (project == null) return;
    state = project.updatePageData(pageIndex, pageData);
    await _saveToDisk();
  }

  // ---------------------------------------------------------------------------
  // Persistence
  // ---------------------------------------------------------------------------

  Future<void> _saveToDisk() async {
    if (state == null || kIsWeb) return;

    if (_pendingSave != null) {
      _saveDirty = true;
      return;
    }

    _pendingSave = _doSave();
    await _pendingSave;
    _pendingSave = null;

    if (_saveDirty) {
      _saveDirty = false;
      await _saveToDisk();
    }
  }

  Future<void> _doSave() async {
    // Read state at save time to get the latest version.
    final project = state;
    if (project == null) return;
    final json = _projectToJson(project);
    await persistence.saveProject(project.filePath, jsonEncode(json));
  }

  Future<Project?> _loadFromDisk(String filePath) async {
    if (kIsWeb) return null;
    try {
      final content = await persistence.loadProject(filePath);
      if (content == null) return null;
      final json = jsonDecode(content) as Map<String, dynamic>;
      return _projectFromJson(json);
    } catch (_) {
      return null;
    }
  }

  // -- Serialisation ----------------------------------------------------------

  static Map<String, dynamic> _projectToJson(Project project) => {
        'id': project.id,
        'filePath': project.filePath,
        'fileName': project.fileName,
        'pageCount': project.pageCount,
        'createdAt': project.createdAt.toIso8601String(),
        'updatedAt': project.updatedAt.toIso8601String(),
        'pages': project.pages.map(
          (key, value) => MapEntry(key.toString(), _pageDataToJson(value)),
        ),
      };

  static Project _projectFromJson(Map<String, dynamic> json) => Project(
        id: json['id'] as String,
        filePath: json['filePath'] as String,
        fileName: json['fileName'] as String,
        pageCount: json['pageCount'] as int,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        pages: (json['pages'] as Map<String, dynamic>).map(
          (key, value) => MapEntry(
            int.parse(key),
            _pageDataFromJson(value as Map<String, dynamic>),
          ),
        ),
      );

  static Map<String, dynamic> _pageDataToJson(PageData pd) => {
        'pageIndex': pd.pageIndex,
        'isVectorPage': pd.isVectorPage,
        'detectedElements': pd.detectedElements.map((e) => e.toJson()).toList(),
        'detectedJoints': pd.detectedJoints
            .map((j) => {
                  'point': j.point.toJson(),
                  'connectedElementIndices': j.connectedElementIndices,
                })
            .toList(),
        'measurements': pd.measurements.map((m) => m.toJson()).toList(),
        if (pd.calibration != null) 'calibration': pd.calibration!.toJson(),
      };

  static PageData _pageDataFromJson(Map<String, dynamic> json) => PageData(
        pageIndex: json['pageIndex'] as int,
        isVectorPage: json['isVectorPage'] as bool? ?? false,
        detectedElements: (json['detectedElements'] as List<dynamic>?)
                ?.map((e) =>
                    DetectedElement.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        detectedJoints: (json['detectedJoints'] as List<dynamic>?)
                ?.map((j) {
              final m = j as Map<String, dynamic>;
              return Joint(
                Point2D.fromJson(m['point'] as Map<String, dynamic>),
                (m['connectedElementIndices'] as List<dynamic>)
                    .map((e) => (e as num).toInt())
                    .toList(),
              );
            }).toList() ??
            const [],
        measurements: (json['measurements'] as List<dynamic>?)
                ?.map(
                    (m) => Measurement.fromJson(m as Map<String, dynamic>))
                .toList() ??
            const [],
        calibration: json['calibration'] != null
            ? CalibrationScale.fromJson(
                json['calibration'] as Map<String, dynamic>)
            : null,
      );
}
