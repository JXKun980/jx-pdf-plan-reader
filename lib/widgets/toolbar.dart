import 'package:flutter/material.dart';

import '../state/measurement_state.dart' show ToolMode;

class Toolbar extends StatelessWidget {
  final ToolMode activeTool;
  final bool canUndo;
  final bool canRedo;
  final bool snapEnabled;
  final double snapTolerance;
  final String? zoomLabel;
  final ValueChanged<ToolMode> onToolChanged;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final ValueChanged<bool> onSnapToggled;
  final ValueChanged<double> onSnapToleranceChanged;
  final bool arcSymmetric;
  final VoidCallback onArcSymmetricToggled;
  final VoidCallback? onZoomIn;
  final VoidCallback? onZoomOut;
  final VoidCallback? onZoomFit;
  final String? coordinateLabel;

  const Toolbar({
    super.key,
    required this.activeTool,
    required this.canUndo,
    required this.canRedo,
    required this.snapEnabled,
    required this.snapTolerance,
    this.zoomLabel,
    required this.onToolChanged,
    required this.onUndo,
    required this.onRedo,
    required this.onSnapToggled,
    required this.onSnapToleranceChanged,
    required this.arcSymmetric,
    required this.onArcSymmetricToggled,
    this.onZoomIn,
    this.onZoomOut,
    this.onZoomFit,
    this.coordinateLabel,
  });

  @override
  Widget build(BuildContext context) {
    // On narrow (mobile) screens we shrink the snap slider and rely on the
    // horizontal scroll view to handle remaining overflow gracefully.
    final width = MediaQuery.sizeOf(context).width;
    final isCompact = width < 600;
    final sliderWidth = isCompact ? 80.0 : 120.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Scrollable toolbar items take the available width minus the
          // coordinate badge, which is pinned to the right.
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _toolButton(
                    icon: Icons.near_me,
                    tooltip: 'Select',
                    mode: ToolMode.select,
                  ),
                  _toolButton(
                    icon: Icons.show_chart,
                    tooltip: 'Line',
                    mode: ToolMode.line,
                  ),
                  _toolButton(
                    icon: Icons.gesture,
                    tooltip: 'Arc',
                    mode: ToolMode.arc,
                  ),
                  _toolButton(
                    icon: Icons.circle_outlined,
                    tooltip: 'Circle',
                    mode: ToolMode.circle,
                  ),
                  _toolButton(
                    icon: Icons.rectangle_outlined,
                    tooltip: 'Rectangle',
                    mode: ToolMode.rectangle,
                  ),
                  _toolButton(
                    icon: Icons.square_foot,
                    tooltip: 'Calibrate',
                    mode: ToolMode.calibrate,
                  ),
                  _divider(),
                  IconButton(
                    icon: const Icon(Icons.undo),
                    tooltip: 'Undo',
                    onPressed: canUndo ? onUndo : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.redo),
                    tooltip: 'Redo',
                    onPressed: canRedo ? onRedo : null,
                  ),
                  _divider(),
                  IconButton(
                    icon: Icon(
                      Icons.adjust,
                      color: snapEnabled
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                    tooltip: snapEnabled ? 'Snap: ON' : 'Snap: OFF',
                    onPressed: () => onSnapToggled(!snapEnabled),
                    style: snapEnabled
                        ? IconButton.styleFrom(
                            backgroundColor: Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: 0.12),
                          )
                        : null,
                  ),
                  if (snapEnabled)
                    SizedBox(
                      width: sliderWidth,
                      child: Slider(
                        value: snapTolerance,
                        min: 2,
                        max: 30,
                        divisions: 14,
                        label: '${snapTolerance.round()} px',
                        onChanged: onSnapToleranceChanged,
                      ),
                    ),
                  if (activeTool == ToolMode.arc) ...[
                    _divider(),
                    IconButton(
                      icon: Icon(
                        Icons.swap_horiz,
                        color: arcSymmetric
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      tooltip: arcSymmetric
                          ? 'Curve: Arc (circular). Click to switch to Free (Bezier).'
                          : 'Curve: Free (Bezier). Click to switch to Arc (circular).',
                      onPressed: onArcSymmetricToggled,
                      style: arcSymmetric
                          ? IconButton.styleFrom(
                              backgroundColor: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: 0.12),
                            )
                          : null,
                    ),
                  ],
                  if (onZoomIn != null) ...[
                    _divider(),
                    IconButton(
                      icon: const Icon(Icons.zoom_out),
                      tooltip: 'Zoom Out',
                      onPressed: onZoomOut,
                    ),
                    if (zoomLabel != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          zoomLabel!,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    IconButton(
                      icon: const Icon(Icons.zoom_in),
                      tooltip: 'Zoom In',
                      onPressed: onZoomIn,
                    ),
                    IconButton(
                      icon: const Icon(Icons.fit_screen),
                      tooltip: 'Fit to Page',
                      onPressed: onZoomFit,
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Coordinate badge stays visible on the right edge (hidden on very
          // narrow screens so the toolbar still gets meaningful space).
          if (coordinateLabel != null && !isCompact) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                coordinateLabel!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _toolButton({
    required IconData icon,
    required String tooltip,
    required ToolMode mode,
  }) {
    final isActive = activeTool == mode;
    return IconButton(
      icon: Icon(icon),
      tooltip: tooltip,
      isSelected: isActive,
      onPressed: () => onToolChanged(mode),
      style: isActive
          ? IconButton.styleFrom(
              backgroundColor: Colors.blue.withValues(alpha: 0.12),
              foregroundColor: Colors.blue,
            )
          : null,
    );
  }

  Widget _divider() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 4),
      child: SizedBox(
        height: 24,
        child: VerticalDivider(width: 1, thickness: 1),
      ),
    );
  }
}
