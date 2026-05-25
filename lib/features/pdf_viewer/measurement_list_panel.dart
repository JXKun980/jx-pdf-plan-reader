import 'package:flutter/material.dart';

import '../../core/calibration/scale.dart';
import '../../models/measurement.dart';

class MeasurementListPanel extends StatelessWidget {
  final List<Measurement> measurements;
  final CalibrationScale? calibration;
  final ValueChanged<Measurement> onDelete;
  final bool isOpen;
  final VoidCallback onToggle;

  const MeasurementListPanel({
    super.key,
    required this.measurements,
    required this.calibration,
    required this.onDelete,
    required this.isOpen,
    required this.onToggle,
  });

  /// Only show manually-created measurements in the panel.
  List<Measurement> get _manualMeasurements =>
      measurements.where((m) => !m.autoDetected).toList();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      bottom: 0,
      right: 0,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Toggle tab visible when panel is closed
          if (!isOpen)
            _buildToggleTab(context),
          // Sliding panel
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            width: isOpen ? 280 : 0,
            clipBehavior: Clip.hardEdge,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              boxShadow: isOpen
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 8,
                        offset: const Offset(-2, 0),
                      ),
                    ]
                  : [],
            ),
            child: OverflowBox(
              minWidth: 280,
              maxWidth: 280,
              alignment: Alignment.topLeft,
              child: Column(
                children: [
                  _buildPanelHeader(context),
                  if (calibration == null && _manualMeasurements.isNotEmpty)
                    _buildCalibrationHint(context),
                  Expanded(
                    child: _manualMeasurements.isEmpty
                        ? _buildEmptyState(context)
                        : ListView.builder(
                            itemCount: _manualMeasurements.length,
                            padding: EdgeInsets.zero,
                            itemBuilder: (context, index) =>
                                _buildMeasurementTile(context, _manualMeasurements[index]),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleTab(BuildContext context) {
    return GestureDetector(
      onTap: onToggle,
      child: Container(
        width: 32,
        height: 80,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.horizontal(left: Radius.circular(8)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 4,
              offset: const Offset(-2, 0),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.straighten, size: 18),
            if (_manualMeasurements.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${_manualMeasurements.length}',
                  style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(context).colorScheme.onPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPanelHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade300),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Measurements (${_manualMeasurements.length})',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: onToggle,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: 'Close panel',
          ),
        ],
      ),
    );
  }

  Widget _buildCalibrationHint(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber.shade300),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: Colors.amber.shade800),
          const SizedBox(width: 8),
          Text(
            'Set calibration for real units',
            style: TextStyle(fontSize: 12, color: Colors.amber.shade900),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Text(
          'No measurements on this page',
          style: TextStyle(color: Colors.grey.shade500),
        ),
      ),
    );
  }

  Widget _buildMeasurementTile(BuildContext context, Measurement m) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Icon(
            switch (m.type) {
              MeasurementType.arc => Icons.gesture,
              MeasurementType.circle => Icons.circle_outlined,
              MeasurementType.rectangle => Icons.rectangle_outlined,
              _ => Icons.straighten,
            },
            size: 16,
            color: Colors.red,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatValue(m),
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${m.startPoint.x.toStringAsFixed(0)},${m.startPoint.y.toStringAsFixed(0)} → '
                  '${m.endPoint.x.toStringAsFixed(0)},${m.endPoint.y.toStringAsFixed(0)}',
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            onPressed: () => onDelete(m),
            tooltip: 'Delete',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  String _formatValue(Measurement m) {
    if (m.type == MeasurementType.rectangle) {
      return _formatRect(m);
    }
    final prefix = m.type == MeasurementType.circle ? 'R=' : '';
    if (calibration != null) {
      return '$prefix${m.formatLength(calibration!.pixelsPerMm)}';
    }
    return '$prefix${m.pixelLength.toStringAsFixed(1)} px';
  }

  String _formatRect(Measurement m) {
    final w = (m.endPoint.x - m.startPoint.x).abs();
    final h = (m.endPoint.y - m.startPoint.y).abs();
    if (calibration != null) {
      final ppm = calibration!.pixelsPerMm;
      return '${_fmtMm(w / ppm)} × ${_fmtMm(h / ppm)}';
    }
    return '${w.toStringAsFixed(1)} × ${h.toStringAsFixed(1)} px';
  }

  String _fmtMm(double mm) {
    if (mm >= 1000) return '${(mm / 1000).toStringAsFixed(2)} m';
    if (mm >= 10) return '${mm.toStringAsFixed(1)} mm';
    return '${mm.toStringAsFixed(2)} mm';
  }
}
