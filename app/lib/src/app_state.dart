import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'model/document.dart';
import 'model/inline.dart' as inline;
import 'model/lists.dart' as lists;
import 'model/panes.dart';
import 'storage/atomic_file.dart';
import 'storage/session.dart';
import 'ui/editor_controller.dart';

typedef SessionWriter = Future<void> Function(Session session);

/// All application behavior. Widgets only read this state and call methods.
class AppState extends ChangeNotifier {
  AppState(Session session, {this.notice, SessionWriter? writer, this.onExit})
    : _writer = writer ?? saveSession,
      settings = session.settings {
    for (final s in session.documents) {
      if (documents.containsKey(s.id)) continue;
      tabs.add(s.id);
      documents[s.id] = Document.restore(s);
    }
    if (tabs.isEmpty) {
      tabs.add(1);
      documents[1] = Document(id: 1);
    }
    final active = documents.containsKey(session.active)
        ? session.active!
        : tabs.first;
    _nextId = tabs.reduce((a, b) => a > b ? a : b) + 1;
    panes = Panes(active);
  }

  static const checkpointDelay = Duration(milliseconds: 700);

  final SessionWriter _writer;
  final VoidCallback? onExit;

  final Map<int, Document> documents = {};
  final List<int> tabs = [];
  late final Panes panes;
  final Settings settings;
  late int _nextId;

  bool systemDark = false;
  bool settingsOpen = false;
  bool findOpen = false;
  String query = '';
  String replacement = '';
  int _findOffset = 0;
  String? notice;
  int? confirm;
  bool quitting = false;
  int? saving;

  // Recovery persistence.
  Timer? _checkpoint;
  bool _persisting = false;
  bool _persistAgain = false;
  bool exitAfterPersist = false;

  // Per-pane editor state; cursors are independent even for the same document.
  final Map<int, EditorController> _controllers = {};
  final Map<int, FocusNode> _focus = {};
  final Map<int, TextSelection> _lastSelection = {};
  final FocusNode findFocus = FocusNode(debugLabel: 'find');
  bool _syncing = false;

  // ---------------------------------------------------------------- queries

  int get activeId => panes.active.document;
  Document get activeDocument => documents[activeId]!;
  bool get dark => switch (settings.appearance) {
    Appearance.system => systemDark,
    Appearance.light => false,
    Appearance.dark => true,
  };
  bool get blocked => confirm != null || exitAfterPersist;

  String get title =>
      '${activeDocument.name}${activeDocument.dirty ? ' •' : ''} — writestuff';

  EditorController controllerFor(PaneLeaf pane) {
    final doc = documents[pane.document]!;
    final c = _controllers.putIfAbsent(pane.id, () {
      final c = EditorController(text: doc.text);
      c.addListener(() => _onControllerChanged(pane.id));
      return c;
    });
    c.markdown = doc.isMarkdown;
    c.query = findOpen ? query : '';
    if (!findOpen) c.currentMatch = null;
    return c;
  }

  FocusNode focusFor(PaneLeaf pane) => _focus.putIfAbsent(
    pane.id,
    () => FocusNode(
      debugLabel: 'pane ${pane.id}',
      onKeyEvent: (node, event) => _editorKey(pane.id, event),
    ),
  );

  /// Enter continues lists; Tab / Shift+Tab nest list items. Tab elsewhere
  /// inserts a tab character instead of moving focus.
  KeyEventResult _editorKey(int paneId, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final enter =
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter;
    if (!enter && key != LogicalKeyboardKey.tab) return KeyEventResult.ignored;
    final keys = HardwareKeyboard.instance;
    if (keys.isControlPressed || keys.isMetaPressed || keys.isAltPressed) {
      return KeyEventResult.ignored;
    }
    final c = _controllers[paneId];
    if (c == null || !c.selection.isValid || blocked) {
      return KeyEventResult.ignored;
    }
    final shift = keys.isShiftPressed;
    TextEditingValue? next;
    if (enter) {
      if (shift) return KeyEventResult.ignored;
      next = lists.continueList(c.value);
    } else {
      next = lists.indentLines(c.value, outdent: shift);
      if (next == null && !shift) {
        final s = c.selection;
        next = TextEditingValue(
          text: '${s.textBefore(c.text)}\t${s.textAfter(c.text)}',
          selection: TextSelection.collapsed(offset: s.start + 1),
        );
      }
    }
    if (next == null) {
      // Shift+Tab outside a list: swallow it so focus stays in the editor.
      return enter ? KeyEventResult.ignored : KeyEventResult.handled;
    }
    c.value = next;
    return KeyEventResult.handled;
  }

  /// Cmd+Shift+8 / Cmd+Shift+7: toggle bullets or numbering on selected lines.
  void toggleList({required bool ordered, bool task = false}) =>
      format((v) => lists.toggleList(v, ordered: ordered, task: task));

  /// Applies a formatting edit (format bar, Cmd+B and friends) to the
  /// active pane, as one undoable step.
  void format(TextEditingValue Function(TextEditingValue) edit) {
    if (blocked || panes.active.preview) return;
    final c = controllerFor(panes.active);
    c.value = edit(c.value);
    focusActive();
  }

  void bold() => format((v) => inline.toggleWrap(v, '**'));
  void italic() => format((v) => inline.toggleWrap(v, '_'));
  void strikethrough() => format((v) => inline.toggleWrap(v, '~~'));
  void code() => format((v) => inline.toggleWrap(v, '`'));
  void link() => format(inline.insertLink);
  void heading() => format(inline.cycleHeading);

  bool get editorFocused => _focus.values.any((f) => f.hasFocus);

  /// Line and column (1-based, in characters) of the active pane's cursor.
  (int, int) get cursor {
    final c = _controllers[panes.active.id];
    if (c == null) return (1, 1);
    final offset = c.selection.isValid
        ? c.selection.extentOffset.clamp(0, c.text.length)
        : 0;
    final before = c.text.substring(0, offset);
    final lineStart = before.lastIndexOf('\n') + 1;
    final line = '\n'.allMatches(before).length + 1;
    final column =
        before.substring(lineStart).replaceAll('\r', '').runes.length + 1;
    return (line, column);
  }

  // --------------------------------------------------------------- editing

  void _onControllerChanged(int paneId) {
    if (_syncing) return;
    final pane = panes.byId(paneId);
    final c = _controllers[paneId];
    if (pane == null || c == null) return;
    final doc = documents[pane.document]!;
    if (c.text != doc.text) {
      if (blocked) {
        _syncing = true;
        c.value = TextEditingValue(
          text: doc.text,
          selection:
              _lastSelection[paneId] ??
              const TextSelection.collapsed(offset: 0),
        );
        _syncing = false;
        return;
      }
      final before = _lastSelection[paneId] ?? c.selection;
      final old = doc.text;
      doc.edit(c.text, before);
      panes.active = pane;
      _syncOthers(doc, old, except: paneId);
      _lastSelection[paneId] = c.selection;
      _changed();
    } else {
      _lastSelection[paneId] = c.selection;
      if (!identical(panes.active, pane) &&
          c.selection.isValid &&
          (_focus[paneId]?.hasFocus ?? false)) {
        panes.active = pane;
      }
      notifyListeners();
    }
  }

  /// Pushes a document's new text into every other pane showing it, keeping
  /// each pane's cursor at the same place relative to the change.
  void _syncOthers(
    Document doc,
    String old, {
    int? except,
    TextSelection? selectionForActive,
  }) {
    _syncing = true;
    for (final leaf in panes.leaves) {
      if (leaf.document != doc.id || leaf.id == except) continue;
      final c = _controllers[leaf.id];
      if (c == null) continue;
      final selection =
          selectionForActive != null && identical(leaf, panes.active)
          ? selectionForActive
          : _shift(c.selection, old, doc.text);
      c.value = TextEditingValue(
        text: doc.text,
        selection: _clamp(selection, doc.text),
      );
      _lastSelection[leaf.id] = c.selection;
    }
    _syncing = false;
  }

  static TextSelection _clamp(TextSelection s, String text) {
    if (!s.isValid) return const TextSelection.collapsed(offset: 0);
    return TextSelection(
      baseOffset: s.baseOffset.clamp(0, text.length),
      extentOffset: s.extentOffset.clamp(0, text.length),
    );
  }

  static TextSelection _shift(TextSelection s, String old, String now) {
    if (!s.isValid) return s;
    var prefix = 0;
    final max = old.length < now.length ? old.length : now.length;
    while (prefix < max && old.codeUnitAt(prefix) == now.codeUnitAt(prefix)) {
      prefix++;
    }
    final delta = now.length - old.length;
    int move(int o) => o > prefix ? (o + delta).clamp(prefix, now.length) : o;
    return TextSelection(
      baseOffset: move(s.baseOffset),
      extentOffset: move(s.extentOffset),
    );
  }

  void _loadIntoPane(PaneLeaf pane) {
    final c = _controllers[pane.id];
    if (c == null) return;
    final doc = documents[pane.document]!;
    _syncing = true;
    c.value = TextEditingValue(
      text: doc.text,
      selection: TextSelection.collapsed(offset: doc.text.length),
    );
    _syncing = false;
    _lastSelection[pane.id] = c.selection;
  }

  void undo({required bool redo}) {
    if (blocked) return;
    final pane = panes.active;
    final doc = activeDocument;
    final c = controllerFor(pane);
    final old = doc.text;
    final selection = doc.undo(redo: redo, current: c.selection);
    if (selection == null) return;
    _syncOthers(doc, old, selectionForActive: selection);
    _changed();
  }

  // ------------------------------------------------------------ documents

  Document _create() {
    final id = _nextId++;
    final doc = Document(id: id);
    documents[id] = doc;
    tabs.add(id);
    return doc;
  }

  void newDocument() {
    if (blocked) return;
    final doc = _create();
    select(doc.id);
  }

  /// Shows [id] in the active pane.
  void select(int id) {
    if (blocked || !documents.containsKey(id)) return;
    _findOffset = 0;
    if (panes.active.document != id) {
      panes.active.document = id;
      _loadIntoPane(panes.active);
    }
    _changed();
    focusActive();
  }

  void reorder(int from, int to) {
    if (blocked) return;
    final id = tabs.removeAt(from);
    tabs.insert(to, id);
    _changed();
  }

  Future<void> open() async {
    if (blocked) return;
    final XFile? file;
    try {
      file = await openFile(confirmButtonText: 'Open');
    } catch (e) {
      _notify('Could not show the open dialog: $e');
      return;
    }
    if (file == null) return;
    await openPath(file.path);
  }

  Future<void> openPath(String path) async {
    try {
      final (canonical, text) = await readText(path);
      if (blocked) return;
      final existing = tabs.where((id) => documents[id]!.path == canonical);
      if (existing.isNotEmpty) {
        select(existing.first);
        return;
      }
      final id = _create().id;
      documents[id] = Document(
        id: id,
        path: canonical,
        text: text,
        saved: text,
      );
      select(id);
    } catch (e) {
      _notify(describeError(e));
    }
  }

  Future<void> save({bool asNew = false, int? id}) async {
    id ??= activeId;
    if (saving != null) return;
    if (confirm != null && confirm != id) return;
    final doc = documents[id]!;
    saving = id;
    notifyListeners();
    final text = doc.text;
    final original = doc.path;
    final expected = doc.saved;
    try {
      String? path = asNew ? null : doc.path;
      if (path == null) {
        final location = await getSaveLocation(
          suggestedName: doc.suggestedFileName,
          confirmButtonText: 'Save',
        );
        if (location == null) return;
        path = location.path;
      }
      path = canonicalize(path);
      final occupied = documents.values.any(
        (other) => other.id != id && other.path == path,
      );
      if (occupied) {
        throw const FileSystemExceptionMessage(
          'This file is already open in another tab. Save to a different file.',
        );
      }
      await writeText(path, text, expected: original == path ? expected : null);
      final saved = documents[id];
      if (saved == null) return;
      saved.markSaved(path, text);
      for (final leaf in panes.leaves.where((l) => l.document == id)) {
        _controllers[leaf.id]?.markdown = saved.isMarkdown;
      }
      if (confirm == id && !saved.dirty) {
        saving = null;
        if (quitting) {
          confirm = null;
          _quitNext();
        } else {
          _remove(id);
          focusActive();
        }
      }
    } catch (e) {
      _notify(e is FileSystemExceptionMessage ? e.message : describeError(e));
    } finally {
      saving = null;
      _changed();
    }
  }

  /// The pane whose title is being edited.
  int? renaming;

  void startRename([PaneLeaf? pane]) {
    if (blocked) return;
    pane ??= panes.active;
    panes.active = pane;
    renaming = pane.id;
    notifyListeners();
  }

  void cancelRename() {
    renaming = null;
    notifyListeners();
    focusActive();
  }

  /// Names an unsaved document, or renames a saved document's file on disk.
  /// A name without an extension keeps the file's current extension.
  Future<void> rename(int id, String input) async {
    renaming = null;
    final doc = documents[id];
    var name = input.trim();
    if (doc == null || blocked || name.isEmpty || name == doc.name) {
      notifyListeners();
      focusActive();
      return;
    }
    if (name.contains('/') ||
        name.contains('\\') ||
        name == '.' ||
        name == '..') {
      _notify('A name cannot contain slashes.');
      return;
    }
    final path = doc.path;
    if (path == null) {
      doc.title = name;
      _changed();
      focusActive();
      return;
    }
    if (saving == id) {
      _notify('Wait for this document to finish saving.');
      return;
    }
    if (p.extension(name).isEmpty) name += p.extension(path);
    final target = p.join(p.dirname(path), name);
    final sameFile = target.toLowerCase() == path.toLowerCase();
    final taken = documents.values.any((d) => d.id != id && d.path == target);
    if (taken ||
        (!sameFile &&
            FileSystemEntity.typeSync(target, followLinks: false) !=
                FileSystemEntityType.notFound)) {
      _notify('“$name” already exists in this folder. Choose another name.');
      return;
    }
    try {
      await File(path).rename(target);
      doc.path = canonicalize(target);
    } catch (e) {
      _notify('Could not rename: ${describeError(e)}');
      return;
    }
    _changed();
    focusActive();
  }

  void close([int? id]) {
    if (blocked) return;
    id ??= activeId;
    if (saving == id) {
      _notify('Wait for this document to finish saving.');
      return;
    }
    if (documents[id]!.dirty) {
      confirm = id;
      notifyListeners();
    } else {
      _remove(id);
      _changed();
      focusActive();
    }
  }

  void _remove(int id) {
    final affected = panes.leaves.where((l) => l.document == id).toList();
    documents.remove(id);
    tabs.remove(id);
    if (tabs.isEmpty) _create();
    // Prefer another hidden tab. If every remaining document is already
    // visible, remove the empty view rather than mirroring a neighbor.
    final visible = panes.leaves
        .where((l) => !affected.contains(l))
        .map((l) => l.document)
        .toSet();
    final replacement = tabs.where((t) => !visible.contains(t)).firstOrNull;
    for (final pane in affected) {
      if (identical(pane, _closingPane) && panes.length > 1) {
        _closePane(pane);
      } else if (replacement != null) {
        pane.document = replacement;
        _loadIntoPane(pane);
      } else if (panes.length > 1) {
        _closePane(pane);
      } else {
        pane.document = tabs.first;
        _loadIntoPane(pane);
      }
    }
    confirm = null;
    _closingPane = null;
  }

  // ---------------------------------------------------- confirm and quit

  void discard() {
    final id = confirm;
    if (id == null || saving != null) return;
    _remove(id);
    if (quitting) {
      _quitNext();
    } else {
      focusActive();
    }
    _changed();
  }

  void cancel() {
    if (saving != null) return;
    confirm = null;
    _closingPane = null;
    quitting = false;
    notifyListeners();
    focusActive();
  }

  void saveAndClose() {
    final id = confirm;
    if (id != null) save(id: id);
  }

  void requestQuit() {
    if (exitAfterPersist) return;
    if (confirm != null) return;
    quitting = true;
    _quitNext();
  }

  void _quitNext() {
    final dirty = tabs.where((id) => documents[id]!.dirty).firstOrNull;
    if (dirty != null) {
      confirm = dirty;
      notifyListeners();
      return;
    }
    exitAfterPersist = true;
    _checkpoint?.cancel();
    _persist();
  }

  // ---------------------------------------------------------------- panes

  void split({required bool horizontal}) {
    if (blocked || panes.length >= Panes.maxPanes) return;
    final doc = _create();
    panes.split(horizontal: horizontal, document: doc.id);
    _changed();
    focusActive();
  }

  void focusPane(PaneLeaf pane) {
    if (identical(panes.active, pane)) return;
    panes.active = pane;
    notifyListeners();
  }

  /// Closes a pane together with its document, unless another pane still
  /// shows that document. Unsaved changes are confirmed first.
  void closePane([PaneLeaf? pane]) {
    if (blocked) return;
    pane ??= panes.active;
    final target = pane;
    final shared = panes.leaves.any(
      (l) => !identical(l, target) && l.document == target.document,
    );
    if (shared) {
      if (_closePane(pane)) {
        _changed();
        focusActive();
      }
      return;
    }
    panes.active = pane;
    _closingPane = pane;
    close(pane.document);
    if (confirm == null) _closingPane = null;
  }

  /// The pane being closed while its document's unsaved changes are
  /// confirmed; it is removed instead of showing another document.
  PaneLeaf? _closingPane;

  bool _closePane(PaneLeaf pane) {
    if (!panes.close(pane)) return false;
    final c = _controllers.remove(pane.id);
    final f = _focus.remove(pane.id);
    _lastSelection.remove(pane.id);
    _editorKeys.remove(pane.id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      c?.dispose();
      f?.dispose();
    });
    return true;
  }

  void movePane(PaneLeaf pane, PaneLeaf target, DropEdge edge) {
    if (blocked) return;
    panes.move(pane, target, edge);
    if (edge == DropEdge.center) {
      _loadIntoPane(pane);
      _loadIntoPane(target);
    }
    _changed();
    focusActive();
  }

  void setMode(PaneMode mode, [PaneLeaf? pane]) {
    if (blocked) return;
    pane ??= panes.active;
    panes.active = pane;
    pane.mode = mode;
    _changed();
    if (mode != PaneMode.preview) focusActive();
  }

  void togglePreview() =>
      setMode(panes.active.preview ? PaneMode.edit : PaneMode.preview);

  void toggleSideBySide() => setMode(
    panes.active.mode == PaneMode.split ? PaneMode.edit : PaneMode.split,
  );

  void focusActive() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!panes.active.preview) _focus[panes.active.id]?.requestFocus();
    });
  }

  // ------------------------------------------------------ find and replace

  void toggleFind() {
    if (blocked) return;
    findOpen = !findOpen;
    notifyListeners();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (findOpen) {
        findFocus.requestFocus();
      } else {
        focusActive();
      }
    });
  }

  void setQuery(String value) {
    query = value;
    _findOffset = 0;
    for (final c in _controllers.values) {
      c.currentMatch = null;
    }
    notifyListeners();
  }

  void setReplacement(String value) => replacement = value;

  /// Selects the next literal, case-sensitive match, wrapping at the end.
  /// Returns the selection so the view can scroll it into place.
  TextSelection? findNext() {
    if (blocked || query.isEmpty) return null;
    final text = activeDocument.text;
    final start = _findOffset.clamp(0, text.length);
    var found = text.indexOf(query, start);
    if (found < 0) found = text.indexOf(query);
    if (found < 0) {
      _notify('No matches found.');
      return null;
    }
    final selection = TextSelection(
      baseOffset: found,
      extentOffset: found + query.length,
    );
    _findOffset = found + query.length;
    final c = controllerFor(panes.active);
    _syncing = true;
    c.selection = selection;
    _syncing = false;
    _lastSelection[panes.active.id] = selection;
    c.currentMatch = TextRange(start: found, end: found + query.length);
    notifyListeners();
    _reveal(panes.active, selection);
    return selection;
  }

  /// Keys on each pane's editor, used to scroll find results into view.
  final Map<int, GlobalKey> _editorKeys = {};
  GlobalKey editorKeyFor(PaneLeaf pane) => _editorKeys.putIfAbsent(
    pane.id,
    () => GlobalKey(debugLabel: 'editor ${pane.id}'),
  );

  void _reveal(PaneLeaf pane, TextSelection selection) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      EditableTextState? found;
      void visit(Element e) {
        if (found != null) return;
        if (e is StatefulElement && e.state is EditableTextState) {
          found = e.state as EditableTextState;
          return;
        }
        e.visitChildElements(visit);
      }

      _editorKeys[pane.id]?.currentContext?.visitChildElements(visit);
      found?.bringIntoView(selection.extent);
    });
  }

  void resize(PaneSplit split, double ratio) {
    split.ratio = ratio.clamp(0.12, 0.88);
    notifyListeners();
  }

  void replace() {
    if (blocked || query.isEmpty) return;
    final c = controllerFor(panes.active);
    final s = c.selection;
    if (s.isValid && !s.isCollapsed && s.textInside(c.text) == query) {
      final text = s.textBefore(c.text) + replacement + s.textAfter(c.text);
      _lastSelection[panes.active.id] = s;
      c.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(
          offset: s.start + replacement.length,
        ),
      );
      _findOffset = s.start + replacement.length;
    }
    findNext();
  }

  void replaceAll() {
    if (blocked || query.isEmpty) return;
    final doc = activeDocument;
    final c = controllerFor(panes.active);
    final old = doc.text;
    doc.replaceText(old.replaceAll(query, replacement), c.selection);
    _syncOthers(doc, old, selectionForActive: _clamp(c.selection, doc.text));
    _findOffset = 0;
    _changed();
  }

  // ------------------------------------------------------------- settings

  void toggleSettings() {
    if (blocked) return;
    settingsOpen = !settingsOpen;
    notifyListeners();
    if (!settingsOpen) focusActive();
  }

  void updateSettings(void Function(Settings s) change) {
    change(settings);
    settings.size = settings.size.clamp(Settings.minSize, Settings.maxSize);
    settings.lineHeight = double.parse(
      settings.lineHeight
          .clamp(Settings.minLineHeight, Settings.maxLineHeight)
          .toStringAsFixed(1),
    );
    _changed();
  }

  void zoom(double delta) {
    if (blocked) return;
    updateSettings((s) => s.size = (s.size + delta).roundToDouble());
  }

  void setSystemDark(bool value) {
    if (systemDark == value) return;
    systemDark = value;
    notifyListeners();
  }

  // ------------------------------------------------------------- notices

  void _notify(String message) {
    notice = message;
    notifyListeners();
  }

  void showNotice(String message) => _notify(message);

  void dismissNotice() {
    notice = null;
    notifyListeners();
  }

  // ------------------------------------------------------------ recovery

  Session get session => Session(
    settings: settings,
    documents: tabs.map((id) => documents[id]!.snapshot()).toList(),
    active: activeId,
  );

  /// Any state change: repaint and schedule a debounced recovery write.
  void _changed() {
    notifyListeners();
    if (exitAfterPersist) return;
    _checkpoint?.cancel();
    _checkpoint = Timer(checkpointDelay, _persist);
  }

  Future<void> _persist() async {
    if (_persisting) {
      _persistAgain = true;
      return;
    }
    _persisting = true;
    String? error;
    try {
      await _writer(session);
    } catch (e) {
      error = describeError(e);
    }
    _persisting = false;
    if (error != null) {
      notice = 'Session recovery could not be saved: $error';
      exitAfterPersist = false;
      quitting = false;
      notifyListeners();
    }
    if (_persistAgain) {
      _persistAgain = false;
      return _persist();
    }
    if (exitAfterPersist) onExit?.call();
  }

  /// Flushes recovery immediately (used by tests and on exit paths).
  Future<void> flush() async {
    _checkpoint?.cancel();
    await _persist();
  }

  @override
  void dispose() {
    _checkpoint?.cancel();
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final f in _focus.values) {
      f.dispose();
    }
    findFocus.dispose();
    super.dispose();
  }
}

class FileSystemExceptionMessage implements Exception {
  const FileSystemExceptionMessage(this.message);
  final String message;
}
