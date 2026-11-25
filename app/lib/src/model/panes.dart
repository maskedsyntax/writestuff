/// A binary tiling layout of editor panes.
sealed class PaneNode {}

/// What a pane shows: the editor, the rendered Markdown, or both side by side.
enum PaneMode { edit, split, preview }

class PaneLeaf extends PaneNode {
  PaneLeaf(this.id, this.document);
  final int id;
  int document;
  PaneMode mode = PaneMode.edit;

  /// True when only the rendered preview is shown (no editor).
  bool get preview => mode == PaneMode.preview;
}

/// [horizontal] places children side by side (a vertical divider); otherwise
/// they are stacked.
class PaneSplit extends PaneNode {
  PaneSplit(this.horizontal, this.first, this.second, [this.ratio = 0.5]);
  bool horizontal;
  PaneNode first;
  PaneNode second;
  double ratio;
}

enum DropEdge { left, right, top, bottom, center }

class Panes {
  Panes(int document) : root = PaneLeaf(1, document) {
    active = root as PaneLeaf;
  }

  static const maxPanes = 8;

  PaneNode root;
  late PaneLeaf active;
  int _nextId = 2;

  Iterable<PaneLeaf> get leaves => _leaves(root);
  int get length => leaves.length;

  static Iterable<PaneLeaf> _leaves(PaneNode n) sync* {
    switch (n) {
      case PaneLeaf():
        yield n;
      case PaneSplit():
        yield* _leaves(n.first);
        yield* _leaves(n.second);
    }
  }

  PaneLeaf? byId(int id) {
    for (final l in leaves) {
      if (l.id == id) return l;
    }
    return null;
  }

  PaneSplit? _parentOf(PaneNode target, [PaneNode? from]) {
    final n = from ?? root;
    if (n is! PaneSplit) return null;
    if (identical(n.first, target) || identical(n.second, target)) return n;
    return _parentOf(target, n.first) ?? _parentOf(target, n.second);
  }

  void _replace(PaneNode old, PaneNode replacement) {
    if (identical(root, old)) {
      root = replacement;
      return;
    }
    final parent = _parentOf(old)!;
    if (identical(parent.first, old)) {
      parent.first = replacement;
    } else {
      parent.second = replacement;
    }
  }

  /// Splits the active pane, showing [document] in a new active pane.
  bool split({required bool horizontal, required int document}) {
    if (length >= maxPanes) return false;
    final leaf = PaneLeaf(_nextId++, document);
    _replace(active, PaneSplit(horizontal, active, leaf));
    active = leaf;
    return true;
  }

  /// Removes a view. The only pane cannot be closed.
  bool close(PaneLeaf pane) {
    final parent = _parentOf(pane);
    if (parent == null) return false;
    final sibling = identical(parent.first, pane)
        ? parent.second
        : parent.first;
    _replace(parent, sibling);
    if (identical(active, pane) || !leaves.contains(active)) {
      active = _leaves(sibling).first;
    }
    return true;
  }

  /// Moves [pane] next to [target], or swaps their contents for [DropEdge.center].
  void move(PaneLeaf pane, PaneLeaf target, DropEdge edge) {
    if (identical(pane, target)) return;
    if (edge == DropEdge.center) {
      final doc = pane.document, mode = pane.mode;
      pane
        ..document = target.document
        ..mode = target.mode;
      target
        ..document = doc
        ..mode = mode;
      return;
    }
    final parent = _parentOf(pane)!;
    _replace(
      parent,
      identical(parent.first, pane) ? parent.second : parent.first,
    );
    final horizontal = edge == DropEdge.left || edge == DropEdge.right;
    final before = edge == DropEdge.left || edge == DropEdge.top;
    _replace(
      target,
      before
          ? PaneSplit(horizontal, pane, target)
          : PaneSplit(horizontal, target, pane),
    );
    active = pane;
  }
}
