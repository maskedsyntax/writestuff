import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../storage/session.dart';

class _History {
  _History(this.text, this.selection);
  final String text;
  final TextSelection selection;
}

/// One open text document. Text is shared by every pane that shows it; each
/// pane keeps its own cursor.
class Document {
  Document({
    required this.id,
    this.path,
    this.title,
    String text = '',
    this.saved = '',
  }) : _text = text {
    _refresh();
  }

  factory Document.restore(Snapshot s) => Document(
    id: s.id,
    path: s.path,
    title: s.title,
    text: s.text,
    saved: s.saved,
  );

  static const historyLimit = 200;
  static const _coalesceWindow = Duration(milliseconds: 1000);

  final int id;
  String? path;

  /// The name of a document that has no file yet.
  String? title;
  String saved;
  String _text;
  int words = 0;
  int characters = 0;

  final List<_History> _undo = [];
  final List<_History> _redo = [];
  DateTime? _lastEdit;
  bool _coalescing = false;

  String get text => _text;
  bool get dirty => _text != saved;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  String get name =>
      path != null ? p.basename(path!) : (title ?? 'Untitled $id');

  /// Saved files are Markdown by extension. New documents are Markdown unless
  /// they were given a name with another extension.
  bool get isMarkdown {
    final ext = p.extension(name).toLowerCase();
    if (path == null && ext.isEmpty) return true;
    return ext == '.md' || ext == '.markdown';
  }

  /// File name proposed by the save dialog.
  String get suggestedFileName =>
      p.extension(name).isEmpty && isMarkdown ? '$name.md' : name;

  Snapshot snapshot() =>
      Snapshot(id: id, path: path, title: title, text: _text, saved: saved);

  void _refresh() {
    words = RegExp(r'\S+').allMatches(_text).length;
    characters = _text.runes.length;
  }

  void _remember(TextSelection selection) {
    if (_undo.length == historyLimit) _undo.removeAt(0);
    _undo.add(_History(_text, selection));
    _redo.clear();
  }

  /// Records a user edit. Consecutive single-character typing is grouped into
  /// one undo step until a pause, a newline, or a larger change.
  void edit(String text, TextSelection before) {
    if (text == _text) return;
    final now = DateTime.now();
    final delta = text.length - _text.length;
    final typing = delta == 1 && !text.endsWith('\n') && _isAppend(text);
    final group =
        typing &&
        _coalescing &&
        _lastEdit != null &&
        now.difference(_lastEdit!) < _coalesceWindow;
    if (!group) _remember(before);
    _coalescing = typing;
    _lastEdit = now;
    _text = text;
    _refresh();
  }

  bool _isAppend(String text) {
    // A single inserted character that is not a line break.
    var i = 0;
    while (i < _text.length && _text.codeUnitAt(i) == text.codeUnitAt(i)) {
      i++;
    }
    return text.codeUnitAt(i) != 0x0A &&
        text.substring(i + 1) == _text.substring(i);
  }

  /// Replaces the whole text as a single undo step (Replace All).
  void replaceText(String text, TextSelection before) {
    if (text == _text) return;
    _remember(before);
    _coalescing = false;
    _text = text;
    _refresh();
  }

  /// Returns the selection to restore, or null when there is nothing to do.
  TextSelection? undo({required bool redo, required TextSelection current}) {
    final from = redo ? _redo : _undo;
    if (from.isEmpty) return null;
    final entry = from.removeLast();
    (redo ? _undo : _redo).add(_History(_text, current));
    _coalescing = false;
    _text = entry.text;
    _refresh();
    return entry.selection;
  }

  /// Marks exactly the text that was written as saved.
  void markSaved(String path, String text) {
    this.path = path;
    title = null;
    saved = text;
  }
}
