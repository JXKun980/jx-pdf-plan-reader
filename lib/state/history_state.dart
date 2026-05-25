import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/command.dart';
import '../models/page_data.dart';

class HistoryState {
  final Map<int, List<Command>> undoStacks;
  final Map<int, List<Command>> redoStacks;

  const HistoryState({
    this.undoStacks = const {},
    this.redoStacks = const {},
  });

  bool canUndo(int pageIndex) =>
      undoStacks[pageIndex]?.isNotEmpty ?? false;

  bool canRedo(int pageIndex) =>
      redoStacks[pageIndex]?.isNotEmpty ?? false;

  HistoryState copyWith({
    Map<int, List<Command>>? undoStacks,
    Map<int, List<Command>>? redoStacks,
  }) {
    return HistoryState(
      undoStacks: undoStacks ?? this.undoStacks,
      redoStacks: redoStacks ?? this.redoStacks,
    );
  }
}

final historyProvider =
    StateNotifierProvider<HistoryNotifier, HistoryState>((ref) {
  return HistoryNotifier();
});

class HistoryNotifier extends StateNotifier<HistoryState> {
  HistoryNotifier() : super(const HistoryState());

  /// Execute a command, push it onto the page's undo stack, and clear its redo stack.
  void perform(
    Command command,
    int pageIndex,
    PageData Function() readPage,
    void Function(PageData) updateCallback,
  ) {
    command.execute(readPage(), updateCallback);
    final newUndo = Map<int, List<Command>>.from(state.undoStacks);
    newUndo[pageIndex] = [...(newUndo[pageIndex] ?? []), command];
    final newRedo = Map<int, List<Command>>.from(state.redoStacks);
    newRedo[pageIndex] = [];
    state = state.copyWith(undoStacks: newUndo, redoStacks: newRedo);
  }

  /// Undo the most recent command on the given page.
  void undo(
    int pageIndex,
    PageData Function() readPage,
    void Function(PageData) updateCallback,
  ) {
    if (!state.canUndo(pageIndex)) return;
    final stack = state.undoStacks[pageIndex]!;
    final command = stack.last;
    command.undo(readPage(), updateCallback);

    final newUndo = Map<int, List<Command>>.from(state.undoStacks);
    newUndo[pageIndex] = stack.sublist(0, stack.length - 1);
    final newRedo = Map<int, List<Command>>.from(state.redoStacks);
    newRedo[pageIndex] = [...(newRedo[pageIndex] ?? []), command];
    state = state.copyWith(undoStacks: newUndo, redoStacks: newRedo);
  }

  /// Redo the most recently undone command on the given page.
  void redo(
    int pageIndex,
    PageData Function() readPage,
    void Function(PageData) updateCallback,
  ) {
    if (!state.canRedo(pageIndex)) return;
    final stack = state.redoStacks[pageIndex]!;
    final command = stack.last;
    command.execute(readPage(), updateCallback);

    final newUndo = Map<int, List<Command>>.from(state.undoStacks);
    newUndo[pageIndex] = [...(newUndo[pageIndex] ?? []), command];
    final newRedo = Map<int, List<Command>>.from(state.redoStacks);
    newRedo[pageIndex] = stack.sublist(0, stack.length - 1);
    state = state.copyWith(undoStacks: newUndo, redoStacks: newRedo);
  }

  /// Clear all history for all pages.
  void clear() {
    state = const HistoryState();
  }
}
