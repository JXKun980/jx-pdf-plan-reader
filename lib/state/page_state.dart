import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/page_data.dart';
import 'project_state.dart';

final activePageIndexProvider =
    StateNotifierProvider<ActivePageIndexNotifier, int>((ref) {
  return ActivePageIndexNotifier();
});

class ActivePageIndexNotifier extends StateNotifier<int> {
  ActivePageIndexNotifier() : super(0);

  void setPage(int index) {
    state = index;
  }
}

/// Derived provider that returns the [PageData] for the currently active page.
/// Returns a default [PageData] if no project is loaded.
final currentPageDataProvider = Provider<PageData>((ref) {
  final project = ref.watch(projectProvider);
  final pageIndex = ref.watch(activePageIndexProvider);
  if (project == null) return PageData(pageIndex: pageIndex);
  return project.getPageData(pageIndex);
});
