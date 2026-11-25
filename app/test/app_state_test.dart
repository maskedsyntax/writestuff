import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writestuff/src/app_state.dart';
import 'package:writestuff/src/model/document.dart';
import 'package:writestuff/src/model/panes.dart';
import 'package:writestuff/src/storage/session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final written = <Session>[];
  AppState app([Session? session]) =>
      AppState(session ?? Session(), writer: (s) async => written.add(s));

  /// Simulates typing in a pane's editor.
  void type(AppState a, PaneLeaf pane, String text) {
    final c = a.controllerFor(pane);
    c.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  test('history and saved snapshot are independent', () {
    final d = Document(id: 1);
    const none = TextSelection.collapsed(offset: 0);
    d.replaceText('one', none);
    d.markSaved('note.txt', 'one');
    d.replaceText('two', none);
    expect(d.dirty, isTrue);
    d.undo(redo: false, current: none);
    expect(d.text, 'one');
    expect(d.dirty, isFalse);
    d.undo(redo: true, current: none);
    expect(d.text, 'two');
    final restored = Document.restore(d.snapshot());
    expect(restored.text, 'two');
    expect(restored.dirty, isTrue);
  });

  test('typing is grouped into one undo step; history is capped', () {
    final d = Document(id: 1);
    var s = '';
    for (final ch in 'hello'.split('')) {
      final before = TextSelection.collapsed(offset: s.length);
      s += ch;
      d.edit(s, before);
    }
    d.undo(redo: false, current: const TextSelection.collapsed(offset: 5));
    expect(d.text, '');
    for (var i = 0; i < 250; i++) {
      d.replaceText('v$i', const TextSelection.collapsed(offset: 0));
    }
    var steps = 0;
    while (d.canUndo) {
      d.undo(redo: false, current: const TextSelection.collapsed(offset: 0));
      steps++;
    }
    expect(steps, Document.historyLimit);
  });

  test('word and character counts are Unicode-aware', () {
    final d = Document(id: 1, text: 'héllo 猫 😀\nworld');
    expect(d.words, 4);
    expect(d.characters, 15);
  });

  test('markdown detection and names', () {
    expect(Document(id: 3).name, 'Untitled 3');
    expect(Document(id: 1, path: '/a/B.MarkDown').isMarkdown, isTrue);
    expect(Document(id: 1, path: '/a/b.txt').isMarkdown, isFalse);
    expect(Document(id: 1).isMarkdown, isFalse);
  });

  test('same document in two panes shares edits but not cursors', () {
    final a = app();
    final id = a.activeId;
    final first = a.panes.active;
    a.panes.split(horizontal: true, document: id);
    final second = a.panes.active;
    a.controllerFor(first);
    type(a, second, 'é');
    expect(a.documents.length, 1);
    expect(a.controllerFor(first).text, 'é');
    a.controllerFor(first).selection = const TextSelection.collapsed(offset: 0);
    expect(a.controllerFor(second).selection.baseOffset, 1);
    a.undo(redo: false);
    expect(a.documents[id]!.text, '');
    expect(a.controllerFor(first).text, '');
  });

  test('close requires explicit discard and redirects all panes', () {
    final a = app();
    final id = a.activeId;
    type(a, a.panes.active, 'keep me');
    a.panes.split(horizontal: true, document: id);
    a.close(id);
    expect(a.documents.containsKey(id), isTrue);
    expect(a.confirm, id);
    a.newDocument();
    expect(a.documents.length, 1, reason: 'blocked behind the prompt');
    a.cancel();
    expect(a.documents.containsKey(id), isTrue);
    a.close(id);
    a.discard();
    expect(a.documents.containsKey(id), isFalse);
    expect(
      a.panes.leaves.every((p) => a.documents.containsKey(p.document)),
      isTrue,
    );
  });

  test('edits are rejected while the prompt is open', () {
    final a = app();
    type(a, a.panes.active, 'draft');
    a.close();
    type(a, a.panes.active, 'draft and more');
    expect(a.activeDocument.text, 'draft');
  });

  test('session roundtrip preserves unsaved content, order and selection', () {
    final a = app();
    final first = a.activeId;
    type(a, a.panes.active, 'unsaved 世界\n');
    a.newDocument();
    final second = a.activeId;
    type(a, a.panes.active, 'second');
    a.select(first);
    final restored = app(Session.decode(jsonEncode(a.session.toJson())));
    expect(restored.activeId, first);
    expect(restored.tabs, [first, second]);
    expect(restored.documents[first]!.text, 'unsaved 世界\n');
    expect(restored.documents[first]!.dirty, isTrue);
    expect(restored.documents[second]!.text, 'second');
  });

  test('restore skips duplicate ids and falls back for a bad active id', () {
    final a = app(
      Session(
        documents: [
          Snapshot(id: 5, text: 'a', saved: ''),
          Snapshot(id: 5, text: 'b', saved: ''),
          Snapshot(id: 9, text: 'c', saved: ''),
        ],
        active: 77,
      ),
    );
    expect(a.tabs, [5, 9]);
    expect(a.activeId, 5);
    a.newDocument();
    expect(a.activeId, 10);
  });

  test('a save that finishes after newer edits keeps them dirty', () {
    final d = Document(id: 1, text: 'newer');
    d.markSaved('test.txt', 'older');
    expect(d.dirty, isTrue);
    expect(d.text, 'newer');
  });

  test('unicode find and replace selects the right text', () {
    final a = app();
    type(a, a.panes.active, 'é猫\nhello 猫');
    a.setQuery('猫');
    a.findNext();
    final c = a.controllerFor(a.panes.active);
    expect(c.selection.textInside(c.text), '猫');
    a.setReplacement('world');
    a.replace();
    expect(a.activeDocument.text, 'éworld\nhello 猫');
    expect(c.selection.textInside(c.text), '猫', reason: 'moved to next match');
  });

  test('find wraps, replace all is one undo step, no-match notice', () {
    final a = app();
    type(a, a.panes.active, 'a b a');
    a.setQuery('a');
    expect(a.findNext()!.start, 0);
    expect(a.findNext()!.start, 4);
    expect(a.findNext()!.start, 0);
    a.setReplacement('x');
    a.replaceAll();
    expect(a.activeDocument.text, 'x b x');
    a.undo(redo: false);
    expect(a.activeDocument.text, 'a b a');
    a.setQuery('zzz');
    a.findNext();
    expect(a.notice, 'No matches found.');
  });

  test(
    'quit prompts for each dirty document then exits after persisting',
    () async {
      var exited = false;
      final a = AppState(
        Session(),
        writer: (_) async {},
        onExit: () => exited = true,
      );
      final first = a.activeId;
      type(a, a.panes.active, 'one');
      a.newDocument();
      final second = a.activeId;
      type(a, a.panes.active, 'two');
      a.requestQuit();
      expect(a.confirm, first);
      a.discard();
      expect(a.confirm, second);
      a.cancel();
      expect(a.quitting, isFalse);
      a.requestQuit();
      a.discard();
      await Future<void>.delayed(Duration.zero);
      expect(exited, isTrue);
      a.newDocument();
      expect(a.tabs.length, 1, reason: 'input ignored while exiting');
    },
  );

  test('failed recovery write aborts quit', () async {
    var exited = false;
    final a = AppState(
      Session(),
      writer: (_) async => throw Exception('disk full'),
      onExit: () => exited = true,
    );
    a.requestQuit();
    await Future<void>.delayed(Duration.zero);
    expect(exited, isFalse);
    expect(a.notice, startsWith('Session recovery could not be saved'));
    expect(a.exitAfterPersist, isFalse);
  });

  test('split creates an independent document; closing the pane keeps it', () {
    final a = app();
    final original = a.activeId;
    final originalPane = a.panes.active;
    type(a, originalPane, 'original');
    a.split(horizontal: true);
    final created = a.activeId;
    expect(created, isNot(original));
    expect(originalPane.document, original);
    type(a, a.panes.active, 'x');
    expect(a.documents[original]!.text, 'original');
    expect(a.documents[created]!.text, 'x');
    a.closePane();
    expect(a.panes.length, 1);
    expect(a.documents.containsKey(created), isTrue);
    expect(a.activeId, original);
  });

  test('closing a split tab does not mirror the neighbor', () {
    final a = app();
    final original = a.activeId;
    a.split(horizontal: true);
    final second = a.activeId;
    a.close(second);
    expect(a.panes.length, 1);
    expect(a.activeId, original);
    expect(a.documents.containsKey(second), isFalse);
  });

  test('closing a tab shows the first hidden tab', () {
    final a = app();
    final hidden = a.activeId;
    a.newDocument();
    a.split(horizontal: true);
    a.newDocument();
    final shown = a.activeId;
    a.close(shown);
    expect(a.activeId, hidden);
  });

  test('at most eight panes', () {
    final a = app();
    for (var i = 0; i < 12; i++) {
      a.split(horizontal: i.isEven);
    }
    expect(a.panes.length, Panes.maxPanes);
  });

  test('pane rearrange and swap', () {
    final p = Panes(1);
    final a = p.active;
    p.split(horizontal: true, document: 2);
    final b = p.active;
    p.move(a, b, DropEdge.bottom);
    final root = p.root as PaneSplit;
    expect(root.horizontal, isFalse);
    expect(identical(root.first, b), isTrue);
    p.move(a, b, DropEdge.center);
    expect(a.document, 2);
    expect(b.document, 1);
  });

  test('tabs reorder and select', () {
    final a = app();
    final one = a.activeId;
    a.newDocument();
    final two = a.activeId;
    a.newDocument();
    final three = a.activeId;
    a.reorder(2, 0);
    expect(a.tabs, [three, one, two]);
    a.select(one);
    expect(a.activeId, one);
  });

  test('font size zoom clamps', () {
    final a = app();
    for (var i = 0; i < 40; i++) {
      a.zoom(1);
    }
    expect(a.settings.size, Settings.maxSize);
  });

  test('recovery writes are debounced', () async {
    final written = <Session>[];
    final a = AppState(Session(), writer: (s) async => written.add(s));
    type(a, a.panes.active, 'a');
    type(a, a.panes.active, 'ab');
    expect(written, isEmpty);
    await Future<void>.delayed(
      AppState.checkpointDelay + const Duration(milliseconds: 100),
    );
    expect(written.length, 1);
    expect(written.single.documents.single.text, 'ab');
  });
}
