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
  bool _measurementPanelOpen = false;
  final _detectedPages = <int>{};
  bool _detecting = false;
  bool _geometryVisible = true;
  String? _selectedMeasurementId;

  @override
  void initState() {
    super.initState();
    _pdfViewerController.addListener(_onZoomChanged);
  }

  @override
  void dispose() {
    _pdfViewerController.removeListener(_onZoomChanged);
    _zoomLabel.dispose();
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
    notifier.clearFirstPoint();
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

    // Step 3: third click defines the midpoint → create arc through 3 points.
    final start = interaction.pendingFirstPoint!;
    final end = interaction.pendingSecondPoint!;
    final arc = ArcSegment.fromThreePoints(start, point, end);

    if (!arc.radius.isFinite || arc.radius <= 0) {
      notifier.clearFirstPoint();
      return;
    }

    final measurement = Measurement(
      id: const Uuid().v4(),
      type: MeasurementType.arc,
      startPoint: start,
      endPoint: end,
      arcSegment: arc,
      pixelLength: arc.arcLength,
    );

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
      _showMeasurementActions(best);
    } else {
      // Tap on empty space → deselect.
      if (_selectedMeasurementId != null) {
        setState(() => _selectedMeasurementId = null);
      }
    }
  }

  void _showMeasurementActions(Measurement m) {
    final calibration = ref.read(currentCalibrationProvider);
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              calibration != null
                  ? m.formatLength(calibration.pixelsPerMm)
                  : '${m.pixelLength.toStringAsFixed(1)} px',
              style: Theme.of(ctx).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete measurement'),
              onTap: () {
                Navigator.pop(ctx);
                _deleteMeasurement(m);
              },
            ),
          ],
        ),
      ),
    ).whenComplete(() {
      if (mounted) setState(() => _selectedMeasurementId = null);
    });
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
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;

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
      onViewerReady: (_, controller) {
        Future.microtask(() {
          controller.goToPage(
            pageNumber: pageIndex + 1,
            anchor: PdfPageAnchor.all,
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
              onTap: _handleTap,
              onHover: _handlePointerHover,
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
    // Wait for the new layoutPages to apply, then fit-to-screen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted && _pdfViewerController.isReady) {
          _pdfViewerController.goToPage(
            pageNumber: index + 1,
            anchor: PdfPageAnchor.all,
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
  final void Function(Point2D) onTap;
  final void Function(Point2D) onHover;
  final bool geometryVisible;
  final String? selectedMeasurementId;

  const _PageOverlay({
    required this.page,
    required this.snapIndicator,
    required this.hoveredMeasurementId,
    required this.cursorPdfPosition,
    required this.previewCircleRadius,
    required this.onTap,
    required this.onHover,
    this.geometryVisible = true,
    this.selectedMeasurementId,
  });

  Point2D _overlayToPdf(Offset localPos, Size overlaySize) {
    final scaleX = page.width / overlaySize.width;
    final scaleY = page.height / overlaySize.height;
    return Point2D(localPos.dx * scaleX, page.height - localPos.dy * scaleY);
  }

  ArcSegment? _computePreviewArc(
    MeasurementInteractionState interaction,
    Point2D? cursor,
  ) {
    if (interaction.toolMode != ToolMode.arc) return null;
    if (interaction.pendingFirstPoint == null) return null;
    if (interaction.pendingSecondPoint == null) return null;
    if (cursor == null) return null;

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
                        builder: (context, circleR, _) => CanvasOverlay(
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
                          previewArc: _computePreviewArc(
                              interaction, cursor),
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
