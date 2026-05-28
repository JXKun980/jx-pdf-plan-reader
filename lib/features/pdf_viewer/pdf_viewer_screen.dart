import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:uuid/uuid.dart';

import '../../core/calibration/scale.dart';
import '../../core/geometry/arc_segment.dart';
import '../../core/geometry/line_segment.dart';
import '../../core/geometry/point2d.dart';
import '../../core/pdf_parser/geometry_detector.dart';
import '../../models/command.dart';
import '../../models/detected_element.dart';
import '../../models/measurement.dart';
import '../../models/page_data.dart';
import '../../state/calibration_state.dart';
import '../../state/history_state.dart';
import '../../state/measurement_state.dart';
import '../../state/page_state.dart';
import '../../state/project_state.dart';
import '../../widgets/canvas_overlay.dart';
import '../../widgets/toolbar.dart';
import 'measurement_list_panel.dart';

class PdfViewerScreen extends ConsumerStatefulWidget {
  final String? filePath;
  final Uint8List? pdfBytes;
  final String fileName;

  const PdfViewerScreen({
    super.key,
    this.filePath,
    this.pdfBytes,
    required this.fileName,
  }) : assert(filePath != null || pdfBytes != null, 'Either filePath or pdfBytes must be provided');

  @override
  ConsumerState<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends ConsumerState<PdfViewerScreen> {
  final _pdfViewerController = PdfViewerController();
  final _focusNode = FocusNode();
  final _snapIndicator = ValueNotifier<Point2D?>(null);
  final _hoveredMeasurementId = ValueNotifier<String?>(null);
  final _cursorPdfPosition = ValueNotifier<Point2D?>(null);
  final _previewCircleRadius = ValueNotifier<double?>(null);
  final _zoomLabel = ValueNotifier<String>('100%');
  final _shiftHeld = ValueNotifier<bool>(false);
  bool _measurementPanelOpen = false;
  final _detectedPages = <int>{};
  bool _detecting = false;
  bool _geometryVisible = true;
  String? _selectedMeasurementId;

  @override
  void initState() {
    super.initState();
    _pdfViewerController.addListener(_onZoomChanged);
    // On web, right-click would otherwise open the browser's native
    // context menu (annoying when the user just wants to cancel a tool
    // action). Disable it while this screen is mounted; restore on dispose.
    if (kIsWeb) {
      BrowserContextMenu.disableContextMenu();
    }
  }

  @override
  void dispose() {
    _pdfViewerController.removeListener(_onZoomChanged);
    if (kIsWeb) {
      BrowserContextMenu.enableContextMenu();
    }
    _zoomLabel.dispose();
    _shiftHeld.dispose();
    _previewCircleRadius.dispose();
    _cursorPdfPosition.dispose();
    _hoveredMeasurementId.dispose();
    _snapIndicator.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onZoomChanged() {
    if (_pdfViewerController.isReady) {
      final pct = (_pdfViewerController.currentZoom * 100).round();
      _zoomLabel.value = '$pct%';
    }
  }

  void _zoomIn() {
    if (!_pdfViewerController.isReady) return;
    _pdfViewerController.zoomUp();
  }

  void _zoomOut() {
    if (!_pdfViewerController.isReady) return;
    _pdfViewerController.zoomDown();
  }

  void _zoomFit() {
    if (!_pdfViewerController.isReady) return;
    final pageIndex = ref.read(activePageIndexProvider);
    _pdfViewerController.goToPage(
      pageNumber: pageIndex + 1,
      anchor: PdfPageAnchor.all,
    );
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      if (!_pdfViewerController.isReady) return;
      // All wheel → zoom (no Ctrl required in single-page mode)
      final delta = event.scrollDelta.dy;
      final zoom = _pdfViewerController.currentZoom;
      final factor = delta < 0 ? 1.15 : 1 / 1.15;
      final newZoom = (zoom * factor).clamp(0.1, 8.0);
      final center = _pdfViewerController.centerPosition;
      _pdfViewerController.setZoom(center, newZoom);
    }
  }

  // ---------------------------------------------------------------------------
  // Snap helpers
  // ---------------------------------------------------------------------------

  Point2D? _findNearestJoint(Point2D pdfPoint) {
    final interaction = ref.read(measurementInteractionProvider);
    if (!interaction.snapEnabled) return null;

    final pageData = ref.read(currentPageDataProvider);
    final tolerance = interaction.snapTolerance;

    Point2D? bestPoint;
    double bestDist = double.infinity;

    void check(Point2D p) {
      final d = p.distanceTo(pdfPoint);
      if (d < tolerance && d < bestDist) {
        bestDist = d;
        bestPoint = p;
      }
    }

    // Detected joints from geometry detection.
    for (final joint in pageData.detectedJoints) {
      check(joint.point);
    }

    // Snap points from user-created measurements.
    for (final m in pageData.measurements) {
      switch (m.type) {
        case MeasurementType.linear:
          check(m.startPoint);
          check(m.endPoint);
        case MeasurementType.circle:
          check(m.startPoint); // center
        case MeasurementType.rectangle:
          check(m.startPoint);
          check(m.endPoint);
          check(Point2D(m.startPoint.x, m.endPoint.y));
          check(Point2D(m.endPoint.x, m.startPoint.y));
        case MeasurementType.arc:
          check(m.startPoint);
          check(m.endPoint);
      }
    }

    return bestPoint;
  }

  Point2D _maybeSnap(Point2D pdfPoint) {
    return _findNearestJoint(pdfPoint) ?? pdfPoint;
  }

  /// True when the host platform has a physical keyboard (and therefore
  /// Shift as a usable modifier). Web counts because most browser users
  /// have a keyboard; mobile-native targets are excluded.
  bool _isDesktopOrWeb() {
    if (kIsWeb) return true;
    switch (defaultTargetPlatform) {
      case TargetPlatform.windows:
      case TargetPlatform.macOS:
      case TargetPlatform.linux:
        return true;
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.fuchsia:
        return false;
    }
  }

  /// Returns a short instruction string for the floating tool tip banner
  /// based on the currently-active tool and how far along the user is in
  /// the drawing flow. Returns `null` when no tip should be shown
  /// (e.g. the select / pointer tool).
  String? _toolTipText(MeasurementInteractionState interaction) {
    final hasFirst = interaction.pendingFirstPoint != null;
    final hasSecond = interaction.pendingSecondPoint != null;

    // Verbs / hints adapt to the input style so phone/tablet users see
    // gestures they can actually perform.
    final desktop = _isDesktopOrWeb();
    final tap = desktop ? 'Click' : 'Tap';
    final cancelStop = desktop ? 'Right-click to stop.' : 'Long-press to stop.';
    final cancelCancel =
        desktop ? 'Right-click to cancel.' : 'Long-press to cancel.';
    final cancelBack =
        desktop ? 'Right-click to go back.' : 'Long-press to go back.';

    switch (interaction.toolMode) {
      case ToolMode.select:
        return null;
      case ToolMode.line:
        if (!hasFirst) {
          return '$tap anywhere to mark the starting point.';
        }
        return '$tap to draw a line. $cancelStop';
      case ToolMode.arc:
        if (!hasFirst) {
          return '$tap anywhere to mark the arc start point.';
        }
        if (!hasSecond) {
          return '$tap to set the arc end point. $cancelCancel';
        }
        // Stage 3 — picking the apex. Describe the active mode
        // ('Arc' = circular through 3 points, 'Free' = Bezier where the
        // cursor IS the curve's peak) and, on desktop/web only, mention
        // the Shift override.
        final mode = interaction.arcSymmetric ? 'Arc' : 'Free';
        final base = '$tap to set the curve apex ($mode). $cancelBack';
        if (desktop) {
          return interaction.arcSymmetric
              ? '$base Hold Shift for Free.'
              : '$base Hold Shift for Arc.';
        }
        return base;
      case ToolMode.circle:
        if (!hasFirst) {
          return '$tap anywhere to set the circle center.';
        }
        return '$tap to set the radius. $cancelCancel';
      case ToolMode.rectangle:
        if (!hasFirst) {
          return '$tap anywhere to set the first corner.';
        }
        return '$tap to set the opposite corner. $cancelCancel';
      case ToolMode.calibrate:
        if (!hasFirst) {
          return '$tap the first point of a known-length feature.';
        }
        return '$tap the second point to set the calibration. $cancelCancel';
    }
  }

  // ---------------------------------------------------------------------------
  // Geometry detection
  // ---------------------------------------------------------------------------

  Future<void> _detectGeometry() async {
    final pageIndex = ref.read(activePageIndexProvider);
    if (_detectedPages.contains(pageIndex)) return;
    if (_detecting) return;

    final pageData = ref.read(currentPageDataProvider);
    if (pageData.detectedElements.isNotEmpty) {
      _detectedPages.add(pageIndex);
      return;
    }

    final bytes = widget.pdfBytes;
    if (bytes == null) return; // Desktop file path — not yet supported

    setState(() => _detecting = true);
    try {
      final result = await GeometryDetector.detectPage(bytes, pageIndex + 1);
      _detectedPages.add(pageIndex);
      if (result.elements.isNotEmpty && mounted) {
        // Auto-create measurements for every detected line.
        final autoMeasurements = <Measurement>[];
        for (var i = 0; i < result.elements.length; i++) {
          final el = result.elements[i];
          if (el.type == DetectedElementType.line && el.lineSegment != null) {
            final seg = el.lineSegment!;
            autoMeasurements.add(Measurement(
              id: 'auto_${el.id}',
              type: MeasurementType.linear,
              startPoint: seg.start,
              endPoint: seg.end,
              pixelLength: seg.length,
              startSnapped: true,
              endSnapped: true,
              autoDetected: true,
            ));
          }
        }
        final updated = pageData.copyWith(
          isVectorPage: result.isVectorPage,
          detectedElements: result.elements,
          detectedJoints: result.joints,
          measurements: [...pageData.measurements, ...autoMeasurements],
        );
        ref.read(projectProvider.notifier).updatePage(pageIndex, updated);
      }
    } catch (e) {
      debugPrint('Geometry detection failed for page $pageIndex: $e');
    } finally {
      if (mounted) setState(() => _detecting = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Page update helper
  // ---------------------------------------------------------------------------

  int get _pageIndex => ref.read(activePageIndexProvider);

  PageData _readPage() => ref.read(currentPageDataProvider);

  void _updatePage(newPageData) {
    ref.read(projectProvider.notifier).updatePage(_pageIndex, newPageData);
  }

  // ---------------------------------------------------------------------------
  // Tap handling
  // ---------------------------------------------------------------------------

  void _handleTap(Point2D pdfPoint) {
    final interaction = ref.read(measurementInteractionProvider);
    final interactionNotifier = ref.read(measurementInteractionProvider.notifier);

    switch (interaction.toolMode) {
      case ToolMode.line:
        _handleMeasureTap(pdfPoint, interaction, interactionNotifier);
      case ToolMode.arc:
        _handleArcTap(pdfPoint, interaction, interactionNotifier);
      case ToolMode.circle:
        _handleCircleTap(pdfPoint, interaction, interactionNotifier);
      case ToolMode.rectangle:
        _handleRectangleTap(pdfPoint, interaction, interactionNotifier);
      case ToolMode.calibrate:
        _handleCalibrateTap(pdfPoint, interaction, interactionNotifier);
      case ToolMode.select:
        _handleSelectTap(pdfPoint);
    }
  }

  /// Right-click cancels the most recent in-progress action.
  ///
  /// - In the middle of drawing (e.g. after picking arc's 2nd point) → drop
  ///   just that last point and step back one stage.
  /// - With only the first point picked → drop it and return to "about to
  ///   pick first point".
  /// - With nothing picked → exit the tool and return to the pointer.
  void _handleRightClick() {
    final interaction = ref.read(measurementInteractionProvider);
    final notifier = ref.read(measurementInteractionProvider.notifier);

    // Select tool: nothing to cancel.
    if (interaction.toolMode == ToolMode.select) return;

    if (interaction.pendingSecondPoint != null) {
      // Arc 3rd-stage → step back to "have first point, pick second".
      notifier.clearSecondPoint();
      return;
    }

    if (interaction.pendingFirstPoint != null) {
      // Step back to "about to pick first point".
      notifier.clearFirstPoint();
      return;
    }

    // Nothing pending → exit the tool, return to pointer/select mode.
    notifier.setTool(ToolMode.select);
  }

  void _handleMeasureTap(
    Point2D rawPoint,
    MeasurementInteractionState interaction,
    MeasurementInteractionNotifier notifier,
  ) {
    final snapPoint = _findNearestJoint(rawPoint);
    final point = snapPoint ?? rawPoint;
    final snapped = snapPoint != null;

    if (interaction.pendingFirstPoint == null) {
      notifier.setFirstPoint(point);
      return;
    }

    final startPoint = interaction.pendingFirstPoint!;

    // Ignore zero-length clicks (e.g. accidental double-click on same spot)
    // but keep the chain alive so the user can keep going.
    if (startPoint.distanceTo(point) == 0) {
      return;
    }

    final startSnap = _findNearestJoint(startPoint);
    final measurement = Measurement(
      id: const Uuid().v4(),
      type: MeasurementType.linear,
      startPoint: startPoint,
      endPoint: point,
      pixelLength: startPoint.distanceTo(point),
      startSnapped: startSnap != null,
      endSnapped: snapped,
    );

    ref.read(historyProvider.notifier).perform(
          AddMeasurementCommand(measurement),
          _pageIndex,
          _readPage,
          _updatePage,
        );

    // Chain mode: the next line starts where this one ended. Right-click
    // (handled in _handleRightClick) clears the pending first point and
    // stops the chain while staying in the line tool.
    notifier.setFirstPoint(point);
  }

  void _handleArcTap(
    Point2D rawPoint,
    MeasurementInteractionState interaction,
    MeasurementInteractionNotifier notifier,
  ) {
    final point = _maybeSnap(rawPoint);

    // Step 1: set start point.
    if (interaction.pendingFirstPoint == null) {
      notifier.setFirstPoint(point);
      return;
    }

    // Step 2: set end point.
    if (interaction.pendingSecondPoint == null) {
      notifier.setSecondPoint(point);
      return;
    }

    // Step 3: third click defines the apex.
    //  - Arc mode (toolbar toggle ON, or Shift on desktop/web inverts):
    //    classic 3-point circular arc passing through start, cursor, end.
    //  - Free mode (toolbar toggle OFF): quadratic Bezier where the cursor
    //    IS the peak (curve point at t=0.5); the bezier control point is
    //    `2 * cursor - midpoint(start, end)`.
    final start = interaction.pendingFirstPoint!;
    final end = interaction.pendingSecondPoint!;
    final arcMode = _effectiveArcSymmetric(interaction, _shiftHeld.value);

    final Measurement measurement;
    if (arcMode) {
      final arc = ArcSegment.fromThreePoints(start, point, end);
      if (!arc.radius.isFinite || arc.radius <= 0) {
        notifier.clearFirstPoint();
        return;
      }
      measurement = Measurement(
        id: const Uuid().v4(),
        type: MeasurementType.arc,
        startPoint: start,
        endPoint: end,
        arcSegment: arc,
        pixelLength: arc.arcLength,
      );
    } else {
      final control = _bezierControlFromApex(start, end, point);
      measurement = Measurement(
        id: const Uuid().v4(),
        type: MeasurementType.arc,
        startPoint: start,
        endPoint: end,
        bezierControl: control,
        pixelLength: _bezierLength(start, control, end),
      );
    }

    ref.read(historyProvider.notifier).perform(
          AddMeasurementCommand(measurement),
          _pageIndex,
          _readPage,
          _updatePage,
        );
    notifier.clearFirstPoint();
  }

  void _handleCircleTap(
    Point2D rawPoint,
    MeasurementInteractionState interaction,
    MeasurementInteractionNotifier notifier,
  ) {
    final point = _maybeSnap(rawPoint);

    if (interaction.pendingFirstPoint == null) {
      // First click: set the circle center.
      notifier.setFirstPoint(point);
      return;
    }

    // Second click: radius = distance from center to this point.
    final center = interaction.pendingFirstPoint!;
    final radius = center.distanceTo(point);
    if (radius < 1) return; // Ignore degenerate circles.

    final measurement = Measurement(
      id: const Uuid().v4(),
      type: MeasurementType.circle,
      startPoint: center, // center
      endPoint: point,    // point on circumference
      pixelLength: radius,
    );

    ref.read(historyProvider.notifier).perform(
          AddMeasurementCommand(measurement),
          _pageIndex,
          _readPage,
          _updatePage,
        );
    notifier.clearFirstPoint();
    _previewCircleRadius.value = null;
  }

  void _handleRectangleTap(
    Point2D rawPoint,
    MeasurementInteractionState interaction,
    MeasurementInteractionNotifier notifier,
  ) {
    final point = _maybeSnap(rawPoint);

    if (interaction.pendingFirstPoint == null) {
      notifier.setFirstPoint(point);
      return;
    }

    final corner1 = interaction.pendingFirstPoint!;
    final w = (point.x - corner1.x).abs();
    final h = (point.y - corner1.y).abs();
    if (w < 1 && h < 1) return; // Ignore degenerate rectangles.

    final measurement = Measurement(
      id: const Uuid().v4(),
      type: MeasurementType.rectangle,
      startPoint: corner1,
      endPoint: point,
      pixelLength: corner1.distanceTo(point), // diagonal
    );

    ref.read(historyProvider.notifier).perform(
          AddMeasurementCommand(measurement),
          _pageIndex,
          _readPage,
          _updatePage,
        );
    notifier.clearFirstPoint();
  }

  void _handleCalibrateTap(
    Point2D rawPoint,
    MeasurementInteractionState interaction,
    MeasurementInteractionNotifier notifier,
  ) {
    final point = _maybeSnap(rawPoint);

    if (interaction.pendingFirstPoint == null) {
      notifier.setFirstPoint(point);
      return;
    }

    final startPoint = interaction.pendingFirstPoint!;
    notifier.clearFirstPoint();

    _showCalibrationDialog(startPoint, point);
  }

  Future<void> _showCalibrationDialog(Point2D p1, Point2D p2) async {
    final controller = TextEditingController();
    final pixelDist = p1.distanceTo(p2);

    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Set Calibration'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Pixel distance: ${pixelDist.toStringAsFixed(1)} px'),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Known distance (mm)',
                hintText: 'e.g. 1000',
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = double.tryParse(controller.text);
              Navigator.pop(ctx, value);
            },
            child: const Text('Set'),
          ),
        ],
      ),
    );

    controller.dispose();
    if (result == null || result <= 0) return;

    late final CalibrationScale calibration;
    try {
      calibration = CalibrationScale.fromPoints(p1, p2, result);
    } on ArgumentError {
      return;
    }
    ref.read(historyProvider.notifier).perform(
          SetCalibrationCommand(calibration),
          _pageIndex,
          _readPage,
          _updatePage,
        );
  }

  void _handleSelectTap(Point2D pdfPoint) {
    final pageData = ref.read(currentPageDataProvider);
    Measurement? best;
    double bestDist = double.infinity;

    for (final m in pageData.measurements) {
      double dist;
      if (m.type == MeasurementType.arc && m.arcSegment != null) {
        dist = m.arcSegment!.distanceToPoint(pdfPoint);
      } else {
        dist = LineSegment(m.startPoint, m.endPoint).distanceToPoint(pdfPoint);
      }
      if (dist < 20 && dist < bestDist) {
        bestDist = dist;
        best = m;
      }
    }

    if (best != null) {
      setState(() => _selectedMeasurementId = best!.id);
    } else if (_selectedMeasurementId != null) {
      // Tap on empty space → deselect.
      setState(() => _selectedMeasurementId = null);
    }
  }

  void _deleteMeasurement(Measurement m) {
    ref.read(historyProvider.notifier).perform(
          DeleteMeasurementCommand(m),
          _pageIndex,
          _readPage,
          _updatePage,
        );
  }

  // ---------------------------------------------------------------------------
  // Pointer move (snap indicator)
  // ---------------------------------------------------------------------------

  void _handlePointerHover(Point2D pdfPoint) {
    final nearest = _findNearestJoint(pdfPoint);
    if (nearest != _snapIndicator.value) {
      _snapIndicator.value = nearest;
    }

    // Update cursor position (snapped if near a joint).
    final crosshairPos = nearest ?? pdfPoint;
    if (crosshairPos != _cursorPdfPosition.value) {
      _cursorPdfPosition.value = crosshairPos;
    }

    // Update circle preview radius when in circle mode with a pending center.
    final interaction = ref.read(measurementInteractionProvider);
    if (interaction.toolMode == ToolMode.circle &&
        interaction.pendingFirstPoint != null) {
      _previewCircleRadius.value =
          interaction.pendingFirstPoint!.distanceTo(crosshairPos);
    } else if (_previewCircleRadius.value != null) {
      _previewCircleRadius.value = null;
    }

    // Find nearest measurement for line hover highlighting.
    final pageData = ref.read(currentPageDataProvider);
    String? bestId;
    double bestDist = 15.0; // hover tolerance in PDF units
    for (final m in pageData.measurements) {
      if (!m.autoDetected) continue;
      final d = LineSegment(m.startPoint, m.endPoint).distanceToPoint(pdfPoint);
      if (d < bestDist) {
        bestDist = d;
        bestId = m.id;
      }
    }
    if (bestId != _hoveredMeasurementId.value) {
      _hoveredMeasurementId.value = bestId;
    }
  }

  // ---------------------------------------------------------------------------
  // Keyboard shortcuts
  // ---------------------------------------------------------------------------

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    // Track Shift state on both press and release so the arc-preview can
    // toggle between free and symmetric mode while the cursor is stationary.
    final shiftNow = HardwareKeyboard.instance.isShiftPressed;
    if (_shiftHeld.value != shiftNow) {
      _shiftHeld.value = shiftNow;
    }

    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final shift = shiftNow;

    if (ctrl && event.logicalKey == LogicalKeyboardKey.keyZ) {
      final pageIndex = _pageIndex;
      if (shift) {
        ref.read(historyProvider.notifier).redo(pageIndex, _readPage, _updatePage);
      } else {
        ref.read(historyProvider.notifier).undo(pageIndex, _readPage, _updatePage);
      }
      return KeyEventResult.handled;
    }

    if (ctrl && event.logicalKey == LogicalKeyboardKey.keyY) {
      final pageIndex = _pageIndex;
      ref.read(historyProvider.notifier).redo(pageIndex, _readPage, _updatePage);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final project = ref.watch(projectProvider);
    final pageIndex = ref.watch(activePageIndexProvider);
    final interaction = ref.watch(measurementInteractionProvider);
    final history = ref.watch(historyProvider);

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        appBar: AppBar(
          title: Text(project?.fileName ?? 'PDF Viewer'),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(48),
            child: ValueListenableBuilder<String>(
              valueListenable: _zoomLabel,
              builder: (context, zoom, _) =>
                  ValueListenableBuilder<Point2D?>(
                valueListenable: _cursorPdfPosition,
                builder: (context, cursor, _) => Toolbar(
                  activeTool: interaction.toolMode,
                  canUndo: history.canUndo(pageIndex),
                  canRedo: history.canRedo(pageIndex),
                  snapEnabled: interaction.snapEnabled,
                  snapTolerance: interaction.snapTolerance,
                  zoomLabel: zoom,
                  coordinateLabel: cursor != null
                      ? 'X: ${cursor.x.toStringAsFixed(1)}  Y: ${cursor.y.toStringAsFixed(1)}'
                      : null,
                  onToolChanged: (mode) => ref
                      .read(measurementInteractionProvider.notifier)
                      .setTool(mode),
                  onUndo: () {
                    ref.read(historyProvider.notifier).undo(pageIndex, _readPage, _updatePage);
                  },
                  onRedo: () {
                    ref.read(historyProvider.notifier).redo(pageIndex, _readPage, _updatePage);
                  },
                  onSnapToggled: (_) =>
                      ref.read(measurementInteractionProvider.notifier).toggleSnap(),
                  onSnapToleranceChanged: (v) => ref
                      .read(measurementInteractionProvider.notifier)
                      .setSnapTolerance(v),
                  arcSymmetric: interaction.arcSymmetric,
                  onArcSubModeSelected: (symmetric) {
                    final n = ref
                        .read(measurementInteractionProvider.notifier);
                    n.setTool(ToolMode.arc);
                    n.setArcSymmetric(symmetric);
                  },
                  onZoomIn: _zoomIn,
                  onZoomOut: _zoomOut,
                  onZoomFit: _zoomFit,
                ),
              ),
            ),
          ),
        ),
        body: Stack(
          children: [
            // PDF viewer fills all available space
            Listener(
              onPointerSignal: _handlePointerSignal,
              child: _buildPdfViewer(pageIndex),
            ),
            // Measurement sidebar (right side, hidden by default)
            Consumer(
              builder: (context, ref, _) {
                final pageData = ref.watch(currentPageDataProvider);
                final calibration = ref.watch(currentCalibrationProvider);
                return MeasurementListPanel(
                  measurements: pageData.measurements,
                  calibration: calibration,
                  onDelete: _deleteMeasurement,
                  isOpen: _measurementPanelOpen,
                  onToggle: () => setState(() =>
                      _measurementPanelOpen = !_measurementPanelOpen),
                );
              },
            ),
            // Floating page dock (right side, bottom)
            if ((project?.pageCount ?? 0) > 1)
              _buildFloatingPageDock(project!.pageCount, pageIndex),
            // Top-anchored overlay column: the tool-tip banner (centered)
            // is rendered first; the selected-measurement action panel
            // (left-aligned) flows directly beneath it. Using a single
            // top-anchored Column means the actions panel automatically
            // shifts down when the banner wraps to multiple lines on
            // narrow / mobile screens — no hard-coded `top:` value.
            Positioned(
              top: 12,
              left: 0,
              right: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Builder(
                    builder: (_) {
                      final tip = _toolTipText(interaction);
                      if (tip == null) return const SizedBox.shrink();
                      return IgnorePointer(
                        child: Center(child: _ToolTipBanner(text: tip)),
                      );
                    },
                  ),
                  if (_selectedMeasurementId != null)
                    Consumer(
                      builder: (context, ref, _) {
                        final pd = ref.watch(currentPageDataProvider);
                        final cal = ref.watch(currentCalibrationProvider);
                        Measurement? sel;
                        for (final m in pd.measurements) {
                          if (m.id == _selectedMeasurementId) {
                            sel = m;
                            break;
                          }
                        }
                        if (sel == null) return const SizedBox.shrink();
                        final hasBanner =
                            _toolTipText(interaction) != null;
                        return Padding(
                          padding: EdgeInsets.only(
                            left: 16,
                            // Bigger gap below the banner; otherwise sit
                            // near the top edge so the panel is reachable
                            // without crowding the toolbar.
                            top: hasBanner ? 12 : 0,
                          ),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: _SelectedMeasurementActions(
                              showCalibrate: cal == null &&
                                  sel.type == MeasurementType.linear,
                              onDelete: () {
                                _deleteMeasurement(sel!);
                                setState(
                                    () => _selectedMeasurementId = null);
                              },
                              onCalibrate: () {
                                final s = sel!;
                                setState(
                                    () => _selectedMeasurementId = null);
                                _showCalibrationDialog(
                                    s.startPoint, s.endPoint);
                              },
                              onClose: () => setState(
                                  () => _selectedMeasurementId = null),
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
            // Floating detect geometry button / hide-show toggle
            Positioned(
              left: 16,
              bottom: 16,
              child: _detecting
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 8),
                          Text('Detecting geometry…',
                              style: TextStyle(fontSize: 12)),
                        ],
                      ),
                    )
                  : _detectedPages.contains(pageIndex)
                      ? FloatingActionButton.extended(
                          onPressed: () =>
                              setState(() => _geometryVisible = !_geometryVisible),
                          icon: Icon(_geometryVisible
                              ? Icons.visibility
                              : Icons.visibility_off),
                          label: Text(_geometryVisible ? 'Hide' : 'Show'),
                          tooltip: _geometryVisible
                              ? 'Hide detected geometry'
                              : 'Show detected geometry',
                          backgroundColor:
                              Theme.of(context).colorScheme.surfaceContainerHigh,
                          foregroundColor:
                              Theme.of(context).colorScheme.onSurface,
                        )
                      : _DetectGeometryButton(onPressed: _detectGeometry),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPdfViewer(int pageIndex) {
    final params = PdfViewerParams(
      enableTextSelection: false,
      panEnabled: true,
      scaleEnabled: true,
      maxScale: 8.0,
      minScale: 0.1,
      useAlternativeFitScaleAsMinScale: false,
      panAxis: PanAxis.free,
      boundaryMargin: const EdgeInsets.all(double.infinity),
      scrollByMouseWheel: null,
      // Fit-to-screen whenever the viewer becomes ready (page change / load).
      // Snap with Duration.zero so the user never sees the pre-fit (raw
      // document-space) position briefly before it animates to fit.
      onViewerReady: (_, controller) {
        Future.microtask(() {
          controller.goToPage(
            pageNumber: pageIndex + 1,
            anchor: PdfPageAnchor.all,
            duration: Duration.zero,
          );
        });
      },
      // Show only the active page by giving zero-size rects to others.
      layoutPages: (pages, params) {
        final pageLayouts = <Rect>[];
        for (var i = 0; i < pages.length; i++) {
          if (i == pageIndex) {
            pageLayouts.add(Rect.fromLTWH(
              params.margin,
              params.margin,
              pages[i].width,
              pages[i].height,
            ));
          } else {
            // Off-screen / zero-size so pdfrx won't render it.
            pageLayouts.add(Rect.zero);
          }
        }
        final active = pages[pageIndex];
        return PdfPageLayout(
          pageLayouts: pageLayouts,
          documentSize: Size(
            active.width + params.margin * 2,
            active.height + params.margin * 2,
          ),
        );
      },
      pageOverlaysBuilder: (context, pageRect, page) {
        if (page.pageNumber - 1 != pageIndex) return [];
        return [
          Positioned.fill(
            child: _PageOverlay(
              page: page,
              snapIndicator: _snapIndicator,
              hoveredMeasurementId: _hoveredMeasurementId,
              cursorPdfPosition: _cursorPdfPosition,
              previewCircleRadius: _previewCircleRadius,
              shiftHeld: _shiftHeld,
              onTap: _handleTap,
              onHover: _handlePointerHover,
              onSecondaryTap: _handleRightClick,
              geometryVisible: _geometryVisible,
              selectedMeasurementId: _selectedMeasurementId,
            ),
          ),
        ];
      },
    );

    if (widget.pdfBytes != null) {
      return PdfViewer.data(
        widget.pdfBytes!,
        sourceName: widget.fileName,
        controller: _pdfViewerController,
        params: params,
      );
    }
    return PdfViewer.file(
      widget.filePath!,
      controller: _pdfViewerController,
      params: params,
    );
  }

  Widget _buildFloatingPageDock(int pageCount, int activeIndex) {
    return Positioned(
      right: 16,
      bottom: 16,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Previous page
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_up),
              tooltip: 'Previous page',
              onPressed: activeIndex > 0
                  ? () => _navigateToPage(activeIndex - 1)
                  : null,
            ),
            // Page number (tappable)
            InkWell(
              onTap: () => _showPagePicker(pageCount, activeIndex),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Text(
                  '${activeIndex + 1}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
            ),
            // Next page
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_down),
              tooltip: 'Next page',
              onPressed: activeIndex < pageCount - 1
                  ? () => _navigateToPage(activeIndex + 1)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToPage(int index) {
    ref.read(activePageIndexProvider.notifier).setPage(index);
    ref.read(measurementInteractionProvider.notifier).clearFirstPoint();
    // Wait for the new layoutPages callback to apply, then snap (no
    // animation) to the fit-to-page transform so the user never sees the
    // brief intermediate position. We chain two post-frame callbacks: the
    // first ensures the page-index state change has been flushed; the
    // second runs after the next layout pass that uses the new pageIndex.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pdfViewerController.isReady) {
          _pdfViewerController.goToPage(
            pageNumber: index + 1,
            anchor: PdfPageAnchor.all,
            duration: Duration.zero,
          );
        }
      });
    });
  }

  void _showPagePicker(int pageCount, int currentIndex) {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Go to page'),
        children: List.generate(pageCount, (i) {
          final isActive = i == currentIndex;
          return SimpleDialogOption(
            onPressed: () {
              Navigator.pop(ctx);
              _navigateToPage(i);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                'Page ${i + 1}',
                style: TextStyle(
                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                  color: isActive
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Extracted overlay – watches only the providers it needs, so hover and
// provider changes never rebuild the PdfViewer itself.
// ---------------------------------------------------------------------------

class _PageOverlay extends ConsumerWidget {
  final PdfPage page;
  final ValueNotifier<Point2D?> snapIndicator;
  final ValueNotifier<String?> hoveredMeasurementId;
  final ValueNotifier<Point2D?> cursorPdfPosition;
  final ValueNotifier<double?> previewCircleRadius;
  final ValueNotifier<bool> shiftHeld;
  final void Function(Point2D) onTap;
  final void Function(Point2D) onHover;
  final VoidCallback onSecondaryTap;
  final bool geometryVisible;
  final String? selectedMeasurementId;

  const _PageOverlay({
    required this.page,
    required this.snapIndicator,
    required this.hoveredMeasurementId,
    required this.cursorPdfPosition,
    required this.previewCircleRadius,
    required this.shiftHeld,
    required this.onTap,
    required this.onHover,
    required this.onSecondaryTap,
    this.geometryVisible = true,
    this.selectedMeasurementId,
  });

  Point2D _overlayToPdf(Offset localPos, Size overlaySize) {
    final scaleX = page.width / overlaySize.width;
    final scaleY = page.height / overlaySize.height;
    return Point2D(localPos.dx * scaleX, page.height - localPos.dy * scaleY);
  }

  /// Returns true while the arc tool is in its apex-picking stage and is
  /// currently configured as Arc mode (circular). Used to render the
  /// dashed cursor-to-second-endpoint bulge guide.
  bool _isArcModeApexStage(
    MeasurementInteractionState interaction,
    bool shiftHeld,
  ) {
    if (interaction.toolMode != ToolMode.arc) return false;
    if (interaction.pendingFirstPoint == null) return false;
    if (interaction.pendingSecondPoint == null) return false;
    return _effectiveArcSymmetric(interaction, shiftHeld);
  }

  /// Cursor position to show as the Bezier apex indicator (small ring),
  /// only when arc tool is in apex-picking stage AND configured as Bezier
  /// (Free) mode.
  Point2D? _computePreviewBezierApex(
    MeasurementInteractionState interaction,
    Point2D? cursor,
    bool shiftHeld,
  ) {
    if (interaction.toolMode != ToolMode.arc) return null;
    if (interaction.pendingFirstPoint == null) return null;
    if (interaction.pendingSecondPoint == null) return null;
    if (cursor == null) return null;
    if (_effectiveArcSymmetric(interaction, shiftHeld)) return null;
    return cursor;
  }

  /// Bezier control point for the Free-mode preview. Null in Arc mode or
  /// before apex stage.
  Point2D? _computePreviewBezierControl(
    MeasurementInteractionState interaction,
    Point2D? cursor,
    bool shiftHeld,
  ) {
    if (interaction.toolMode != ToolMode.arc) return null;
    if (interaction.pendingFirstPoint == null) return null;
    if (interaction.pendingSecondPoint == null) return null;
    if (cursor == null) return null;
    if (_effectiveArcSymmetric(interaction, shiftHeld)) return null;
    return _bezierControlFromApex(
      interaction.pendingFirstPoint!,
      interaction.pendingSecondPoint!,
      cursor,
    );
  }

  /// Circular-arc preview (Arc mode). Returns the 3-point arc through
  /// start, cursor, end; null in Bezier mode or before apex stage.
  ArcSegment? _computePreviewArc(
    MeasurementInteractionState interaction,
    Point2D? cursor,
    bool shiftHeld,
  ) {
    if (interaction.toolMode != ToolMode.arc) return null;
    if (interaction.pendingFirstPoint == null) return null;
    if (interaction.pendingSecondPoint == null) return null;
    if (cursor == null) return null;
    if (!_effectiveArcSymmetric(interaction, shiftHeld)) return null;

    try {
      final arc = ArcSegment.fromThreePoints(
        interaction.pendingFirstPoint!,
        cursor,
        interaction.pendingSecondPoint!,
      );
      if (!arc.radius.isFinite || arc.radius <= 0) return null;
      return arc;
    } catch (_) {
      return null;
    }
  }

  /// Cursor-following straight-line preview.
  ///
  /// - Line tool: from `pendingFirstPoint` to cursor (after click 1).
  /// - Arc tool:  from `pendingFirstPoint` to cursor while still picking the
  ///   second endpoint (click 1 → click 2 phase). Once both endpoints are
  ///   set, the arc preview takes over via `_computePreviewArc`.
  Point2D? _computePreviewLineEnd(
    MeasurementInteractionState interaction,
    Point2D? cursor,
  ) {
    if (cursor == null) return null;
    if (interaction.pendingFirstPoint == null) return null;

    if (interaction.toolMode == ToolMode.line) return cursor;
    if (interaction.toolMode == ToolMode.arc &&
        interaction.pendingSecondPoint == null) {
      return cursor;
    }
    return null;
  }

  bool _isMeasurementTool(ToolMode mode) =>
      mode == ToolMode.line ||
      mode == ToolMode.arc ||
      mode == ToolMode.circle ||
      mode == ToolMode.rectangle ||
      mode == ToolMode.calibrate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pageData = ref.watch(currentPageDataProvider);
    final interaction = ref.watch(measurementInteractionProvider);
    final calibration = ref.watch(currentCalibrationProvider);
    final showCrosshair = _isMeasurementTool(interaction.toolMode);

    return LayoutBuilder(
      builder: (context, constraints) {
        final overlaySize = Size(
          constraints.maxWidth,
          constraints.maxHeight,
        );
        return Stack(
          children: [
            // Painting layer — ignores pointer so PdfViewer handles pan/zoom.
            IgnorePointer(
              child: RepaintBoundary(
                child: ValueListenableBuilder<Point2D?>(
                  valueListenable: snapIndicator,
                  builder: (context, snap, _) =>
                      ValueListenableBuilder<String?>(
                    valueListenable: hoveredMeasurementId,
                    builder: (context, hovered, _) =>
                        ValueListenableBuilder<Point2D?>(
                      valueListenable: cursorPdfPosition,
                      builder: (context, cursor, _) =>
                          ValueListenableBuilder<double?>(
                        valueListenable: previewCircleRadius,
                        builder: (context, circleR, _) =>
                            ValueListenableBuilder<bool>(
                          valueListenable: shiftHeld,
                          builder: (context, shift, _) => CanvasOverlay(
                          detectedElements: geometryVisible
                              ? pageData.detectedElements
                              : const [],
                          joints: geometryVisible
                              ? pageData.detectedJoints
                              : const [],
                          measurements: pageData.measurements,
                          calibration: calibration,
                          pendingPoint: interaction.pendingFirstPoint,
                          pendingSecondPoint: interaction.pendingSecondPoint,
                          snapIndicator: geometryVisible ? snap : null,
                          snapRadius: interaction.snapTolerance,
                          pageWidth: page.width,
                          pageHeight: page.height,
                          selectedMeasurementId: selectedMeasurementId,
                          hoveredMeasurementId:
                              geometryVisible ? hovered : null,
                          crosshairPosition:
                              showCrosshair ? cursor : null,
                          previewCircleCenter:
                              circleR != null
                                  ? interaction.pendingFirstPoint
                                  : null,
                          previewCircleRadius: circleR,
                          previewRectEnd:
                              interaction.toolMode == ToolMode.rectangle &&
                                      interaction.pendingFirstPoint != null
                                  ? cursor
                                  : null,
                          previewLineEnd: _computePreviewLineEnd(
                              interaction, cursor),
                          previewArc: _computePreviewArc(
                              interaction, cursor, shift),
                          previewBezierControl: _computePreviewBezierControl(
                              interaction, cursor, shift),
                          previewBezierApex: _computePreviewBezierApex(
                              interaction, cursor, shift),
                          showArcBulgeGuide:
                              _isArcModeApexStage(interaction, shift),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Gesture layer — only taps and hover; drags pass through.
            Positioned.fill(
              child: MouseRegion(
                opaque: false,
                cursor: showCrosshair
                    ? SystemMouseCursors.none
                    : MouseCursor.defer,
                onHover: (event) =>
                    onHover(_overlayToPdf(event.localPosition, overlaySize)),
                onExit: (_) => cursorPdfPosition.value = null,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTapUp: (details) =>
                      onTap(_overlayToPdf(details.localPosition, overlaySize)),
                  onSecondaryTapUp: (_) => onSecondaryTap(),
                  // Touch equivalent of right-click on mobile (Android/iOS):
                  // long-press cancels the most recent in-progress action.
                  onLongPress: onSecondaryTap,
                ),
              ),
            ),

          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Fixed-size floating detect button.
// ---------------------------------------------------------------------------

class _DetectGeometryButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _DetectGeometryButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      onPressed: onPressed,
      icon: const Icon(Icons.layers_outlined),
      label: const Text('Detect'),
      tooltip: 'Detect geometry on this page',
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
    );
  }
}

// ---------------------------------------------------------------------------
// Floating action panel shown on the left side when a measurement is
// selected. Provides delete + optional calibrate (only for line measurements
// on uncalibrated pages) + close.
// ---------------------------------------------------------------------------

class _SelectedMeasurementActions extends StatelessWidget {
  final bool showCalibrate;
  final VoidCallback onDelete;
  final VoidCallback onCalibrate;
  final VoidCallback onClose;

  const _SelectedMeasurementActions({
    required this.showCalibrate,
    required this.onDelete,
    required this.onCalibrate,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(8),
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              tooltip: 'Delete measurement',
              onPressed: onDelete,
            ),
            if (showCalibrate)
              IconButton(
                icon: const Icon(Icons.square_foot),
                tooltip: 'Calibrate using this measurement',
                onPressed: onCalibrate,
              ),
            const Divider(height: 1),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              tooltip: 'Deselect',
              onPressed: onClose,
            ),
          ],
        ),
      ),
    );
  }
}

/// Small floating banner that displays a one-line instruction for the
/// currently active drawing tool. Rendered at the top center of the viewer.
class _ToolTipBanner extends StatelessWidget {
  final String text;

  const _ToolTipBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 4,
      color: scheme.inverseSurface.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.info_outline,
              size: 16,
              color: scheme.onInverseSurface,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                text,
                style: TextStyle(
                  color: scheme.onInverseSurface,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Arc-tool helpers (top-level so both the screen-state and the page-overlay
// can share the same logic).
// ---------------------------------------------------------------------------

/// Returns true when the arc tool should commit a classic circular arc
/// (formerly "symmetric"). The persistent toolbar toggle sets the default;
/// Shift inverts it for the current click on desktop/web.
///
/// - `true`  → circular 3-point arc through start, cursor, end.
/// - `false` → quadratic Bezier with the cursor as the curve's peak.
bool _effectiveArcSymmetric(
  MeasurementInteractionState interaction,
  bool shiftHeld,
) {
  // XOR: shift inverts the toggle.
  return interaction.arcSymmetric ^ shiftHeld;
}

/// Quadratic Bezier control point such that the curve's peak at t=0.5
/// is exactly at [apex]. Derivation: `B(0.5) = 0.25·P0 + 0.5·P1 + 0.25·P2`,
/// so `P1 = 2·apex − midpoint(P0, P2)`.
Point2D _bezierControlFromApex(Point2D start, Point2D end, Point2D apex) {
  final midX = (start.x + end.x) / 2;
  final midY = (start.y + end.y) / 2;
  return Point2D(2 * apex.x - midX, 2 * apex.y - midY);
}

/// Numeric arc-length of a quadratic Bezier (sampled subdivision).
double _bezierLength(Point2D p0, Point2D p1, Point2D p2, {int samples = 64}) {
  double prevX = p0.x;
  double prevY = p0.y;
  double length = 0;
  for (var i = 1; i <= samples; i++) {
    final t = i / samples;
    final mt = 1 - t;
    final x = mt * mt * p0.x + 2 * mt * t * p1.x + t * t * p2.x;
    final y = mt * mt * p0.y + 2 * mt * t * p1.y + t * t * p2.y;
    final dx = x - prevX;
    final dy = y - prevY;
    length += math.sqrt(dx * dx + dy * dy);
    prevX = x;
    prevY = y;
  }
  return length;
}
