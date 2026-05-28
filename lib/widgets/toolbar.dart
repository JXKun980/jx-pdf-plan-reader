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
  /// Called when the user picks an arc sub-mode from the arc dropdown.
  /// Receives `true` for the circular Arc sub-mode, `false` for the Free
  /// (Bezier) sub-mode. Implementers should both activate the arc tool
  /// (`ToolMode.arc`) and set the `arcSymmetric` flag accordingly.
  final ValueChanged<bool> onArcSubModeSelected;
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
    required this.onArcSubModeSelected,
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
                  _ArcDropdownButton(
                    isActive: activeTool == ToolMode.arc,
                    arcSymmetric: arcSymmetric,
                    onSelected: onArcSubModeSelected,
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

/// Custom toolbar button that opens a slide-down dropdown of arc sub-modes
/// (Free / Arc) directly underneath itself. Uses an [OverlayEntry] +
/// [SizeTransition] so the menu animates top→bottom (rather than the
/// material default scale animation) and its top edge sits flush with the
/// bottom of the toolbar.
class _ArcDropdownButton extends StatefulWidget {
  final bool isActive;
  final bool arcSymmetric;
  final ValueChanged<bool> onSelected;

  const _ArcDropdownButton({
    required this.isActive,
    required this.arcSymmetric,
    required this.onSelected,
  });

  @override
  State<_ArcDropdownButton> createState() => _ArcDropdownButtonState();
}

class _ArcDropdownButtonState extends State<_ArcDropdownButton>
    with SingleTickerProviderStateMixin {
  final _link = LayerLink();
  late final AnimationController _controller;
  OverlayEntry? _entry;
  // Pixel offset from button bottom down to the toolbar's bottom border so
  // the menu's top edge appears flush with the toolbar. Matches the
  // toolbar Container's vertical padding (4 px).
  static const double _menuTopOffset = 4;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 140),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _entry?.remove();
    _entry = null;
    super.dispose();
  }

  void _toggle() {
    if (_entry == null) {
      _open();
    } else {
      _close();
    }
  }

  void _open() {
    final overlay = Overlay.of(context);
    _entry = OverlayEntry(builder: _buildOverlay);
    overlay.insert(_entry!);
    _controller.forward();
  }

  Future<void> _close() async {
    if (_entry == null) return;
    final entry = _entry!;
    _entry = null;
    await _controller.reverse();
    entry.remove();
  }

  Widget _buildOverlay(BuildContext overlayContext) {
    return Stack(
      children: [
        // Tap-outside-to-close scrim.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _close,
          ),
        ),
        CompositedTransformFollower(
          link: _link,
          showWhenUnlinked: false,
          targetAnchor: Alignment.bottomLeft,
          followerAnchor: Alignment.topLeft,
          offset: const Offset(0, _menuTopOffset),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizeTransition(
              sizeFactor: CurvedAnimation(
                parent: _controller,
                curve: Curves.easeOutCubic,
              ),
              axisAlignment: -1.0,
              child: Material(
                elevation: 6,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(6),
                  bottomRight: Radius.circular(6),
                ),
                clipBehavior: Clip.antiAlias,
                child: IntrinsicWidth(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _menuItem(false, Icons.gesture, 'Free (Bezier)'),
                      _menuItem(true, Icons.architecture, 'Arc (circular)'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _menuItem(bool symmetric, IconData icon, String label) {
    final isCurrent = widget.isActive && widget.arcSymmetric == symmetric;
    final color = isCurrent ? Colors.blue : null;
    return InkWell(
      onTap: () {
        _close();
        widget.onSelected(symmetric);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        color: isCurrent ? Colors.blue.withValues(alpha: 0.08) : null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 10),
            Text(label, style: TextStyle(color: color)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Always use the same base icon so the toolbar button matches the
    // visual weight/colour of its neighbours; the sub-mode is communicated
    // by the dropdown items, not by the toolbar icon itself.
    return CompositedTransformTarget(
      link: _link,
      child: Tooltip(
        message: 'Curve — Free (Bezier) or Arc (circular)',
        child: IconButton(
          icon: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.gesture),
              SizedBox(width: 2),
              Icon(Icons.arrow_drop_down, size: 18),
            ],
          ),
          isSelected: widget.isActive,
          onPressed: _toggle,
          style: widget.isActive
              ? IconButton.styleFrom(
                  backgroundColor: Colors.blue.withValues(alpha: 0.12),
                  foregroundColor: Colors.blue,
                )
              : null,
        ),
      ),
    );
  }
}
