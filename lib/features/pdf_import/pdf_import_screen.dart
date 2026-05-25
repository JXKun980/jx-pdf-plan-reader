import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../state/project_state.dart';
import '../pdf_viewer/pdf_viewer_screen.dart';

class PdfImportScreen extends ConsumerStatefulWidget {
  const PdfImportScreen({super.key});

  @override
  ConsumerState<PdfImportScreen> createState() => _PdfImportScreenState();
}

class _PdfImportScreenState extends ConsumerState<PdfImportScreen> {
  bool _editing = false;

  @override
  Widget build(BuildContext context) {
    final allProjects = ref.watch(recentProjectsProvider);
    final recentProjects = allProjects.take(5).toList();

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.picture_as_pdf,
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'PDF Graph Measure',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 48),
              // Recent projects section
              Container(
                constraints: const BoxConstraints(maxHeight: 340),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header row
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Recent Projects',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        if (allProjects.isNotEmpty)
                          IconButton(
                            icon: Icon(
                              _editing ? Icons.done : Icons.edit,
                              size: 18,
                            ),
                            tooltip: _editing ? 'Done' : 'Edit',
                            onPressed: () =>
                                setState(() => _editing = !_editing),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (allProjects.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Column(
                          children: [
                            Icon(Icons.folder_open,
                                size: 48, color: Colors.grey.shade400),
                            const SizedBox(height: 8),
                            Text(
                              'No recent projects',
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      )
                    else
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: recentProjects.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final entry = recentProjects[index];
                            return _ProjectTile(
                              entry: entry,
                              editing: _editing,
                              onTap: () => _openRecent(context, entry),
                              onDelete: () =>
                                  _confirmDelete(context, entry),
                            );
                          },
                        ),
                      ),
                    if (allProjects.length > 5) ...[
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => _showAllProjects(context),
                        child: Text(
                            'View All Projects (${allProjects.length})'),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: () => _importPdf(context),
                icon: const Icon(Icons.upload_file),
                label: const Text('Import PDF'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(240, 56),
                  textStyle: const TextStyle(fontSize: 18),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    RecentProjectEntry entry,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Project'),
        content: Text(
          'Remove "${entry.fileName}" from the project list?\n\n'
          'The PDF file will not be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      ref.read(recentProjectsProvider.notifier).removeEntry(entry.filePath);
    }
  }

  void _showAllProjects(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => _AllProjectsDialog(
        onOpen: (entry) {
          Navigator.pop(ctx);
          _openRecent(context, entry);
        },
        onDelete: (entry) => _confirmDelete(ctx, entry),
      ),
    );
  }

  Future<void> _openRecent(
    BuildContext context,
    RecentProjectEntry entry,
  ) async {
    if (kIsWeb) {
      // Web has no persistent file access — user must re-import.
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please re-import the PDF file on web.'),
        ),
      );
      return;
    }

    try {
      final file = File(entry.filePath);
      if (!await file.exists()) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('File not found: ${entry.fileName}')),
        );
        ref.read(recentProjectsProvider.notifier).removeEntry(entry.filePath);
        return;
      }

      final bytes = await file.readAsBytes();
      final document = await PdfDocument.openData(bytes);
      final pageCount = document.pages.length;
      await document.dispose();

      await ref
          .read(projectProvider.notifier)
          .loadProject(entry.filePath, entry.fileName, pageCount);

      ref
          .read(recentProjectsProvider.notifier)
          .addEntry(entry.filePath, entry.fileName);

      if (!context.mounted) return;

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PdfViewerScreen(
            filePath: entry.filePath,
            pdfBytes: bytes,
            fileName: entry.fileName,
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to open: $e')),
      );
    }
  }

  Future<void> _importPdf(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    final fileName = file.name;

    final Uint8List? bytes = file.bytes;
    final String? filePath = kIsWeb ? null : file.path;

    if (bytes == null && filePath == null) return;
    if (!context.mounted) return;

    final PdfDocument document;
    if (bytes != null) {
      document = await PdfDocument.openData(bytes);
    } else {
      document = await PdfDocument.openFile(filePath!);
    }
    final pageCount = document.pages.length;
    await document.dispose();

    final projectKey = filePath ?? fileName;
    await ref
        .read(projectProvider.notifier)
        .loadProject(projectKey, fileName, pageCount);

    ref.read(recentProjectsProvider.notifier).addEntry(projectKey, fileName);

    if (!context.mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PdfViewerScreen(
          filePath: kIsWeb ? null : filePath,
          pdfBytes: bytes,
          fileName: fileName,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Project tile — used in both the recent list and the all-projects dialog.
// ---------------------------------------------------------------------------

class _ProjectTile extends StatelessWidget {
  final RecentProjectEntry entry;
  final bool editing;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ProjectTile({
    required this.entry,
    required this.editing,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final age = DateTime.now().difference(entry.lastOpened);
    final String timeAgo;
    if (age.inDays > 0) {
      timeAgo = '${age.inDays}d ago';
    } else if (age.inHours > 0) {
      timeAgo = '${age.inHours}h ago';
    } else {
      timeAgo = '${age.inMinutes}m ago';
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.picture_as_pdf, size: 20, color: Colors.red),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.fileName,
                    style: const TextStyle(
                        fontWeight: FontWeight.w500, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    timeAgo,
                    style:
                        TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            if (editing)
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    size: 18, color: Colors.red),
                onPressed: onDelete,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'Remove',
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Full-screen dialog showing all projects.
// ---------------------------------------------------------------------------

class _AllProjectsDialog extends ConsumerStatefulWidget {
  final void Function(RecentProjectEntry) onOpen;
  final void Function(RecentProjectEntry) onDelete;

  const _AllProjectsDialog({
    required this.onOpen,
    required this.onDelete,
  });

  @override
  ConsumerState<_AllProjectsDialog> createState() =>
      _AllProjectsDialogState();
}

class _AllProjectsDialogState extends ConsumerState<_AllProjectsDialog> {
  bool _editing = false;

  @override
  Widget build(BuildContext context) {
    final projects = ref.watch(recentProjectsProvider);

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'All Projects (${projects.length})',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  if (projects.isNotEmpty)
                    IconButton(
                      icon: Icon(
                        _editing ? Icons.done : Icons.edit,
                        size: 20,
                      ),
                      tooltip: _editing ? 'Done' : 'Edit',
                      onPressed: () =>
                          setState(() => _editing = !_editing),
                    ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // List
            if (projects.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Text('No projects yet.'),
              )
            else
              Flexible(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: projects.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final entry = projects[index];
                    return _ProjectTile(
                      entry: entry,
                      editing: _editing,
                      onTap: () => widget.onOpen(entry),
                      onDelete: () => widget.onDelete(entry),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
