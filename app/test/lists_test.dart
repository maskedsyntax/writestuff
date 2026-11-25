import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writestuff/src/model/lists.dart';

/// `|` marks the caret; `[` and `]` mark a selection.
TextEditingValue v(String marked) {
  if (marked.contains('|')) {
    final at = marked.indexOf('|');
    return TextEditingValue(
      text: marked.replaceFirst('|', ''),
      selection: TextSelection.collapsed(offset: at),
    );
  }
  final a = marked.indexOf('[');
  final b = marked.indexOf(']') - 1;
  return TextEditingValue(
    text: marked.replaceFirst('[', '').replaceFirst(']', ''),
    selection: TextSelection(baseOffset: a, extentOffset: b),
  );
}

String show(TextEditingValue? value) {
  if (value == null) return 'null';
  final s = value.selection;
  if (s.isCollapsed) return value.text.replaceRange(s.start, s.start, '|');
  return value.text
      .replaceRange(s.end, s.end, ']')
      .replaceRange(s.start, s.start, '[');
}

void main() {
  group('Enter', () {
    test('continues bullets with the same indent and marker', () {
      expect(show(continueList(v('- one|'))), '- one\n- |');
      expect(show(continueList(v('  * two|'))), '  * two\n  * |');
    });

    test('increments numbered items', () {
      expect(show(continueList(v('9. nine|'))), '9. nine\n10. |');
      expect(show(continueList(v('1) a|'))), '1) a\n2) |');
    });

    test('continues checklists unchecked', () {
      expect(show(continueList(v('- [x] done|'))), '- [x] done\n- [ ] |');
    });

    test('splits the line at the caret', () {
      expect(show(continueList(v('- ab|cd'))), '- ab\n- |cd');
    });

    test('empty top-level item ends the list', () {
      expect(show(continueList(v('- a\n- |'))), '- a\n|');
    });

    test('empty nested item moves out one level', () {
      expect(show(continueList(v('- a\n  - |'))), '- a\n- |');
    });

    test('is ignored outside lists and before the marker', () {
      expect(continueList(v('plain|')), isNull);
      expect(continueList(v('|- a')), isNull);
    });

    test('keeps CRLF line endings', () {
      expect(show(continueList(v('- a|\r\n'))), '- a\r\n- |\r\n');
    });
  });

  group('Tab', () {
    test('nests under the previous item', () {
      expect(show(indentLines(v('- a\n- b|'), outdent: false)), '- a\n  - b|');
      expect(
        show(indentLines(v('1. a\n2. b|'), outdent: false)),
        '1. a\n   2. b|',
      );
    });

    test('nests one level deeper each time', () {
      final once = indentLines(v('- a\n  - b\n  - c|'), outdent: false);
      expect(show(once), '- a\n  - b\n    - c|');
    });

    test('Shift+Tab moves out to the parent level', () {
      expect(
        show(indentLines(v('- a\n  - b\n    - c|'), outdent: true)),
        '- a\n  - b\n  - c|',
      );
      expect(show(indentLines(v('- a|'), outdent: true)), '- a|');
    });

    test('indents every selected item', () {
      expect(
        show(indentLines(v('- a\n[- b\n- c]'), outdent: false)),
        '- a\n  [- b\n  - c]',
      );
    });

    test('returns null outside lists', () {
      expect(indentLines(v('text|'), outdent: false), isNull);
    });
  });

  group('toggle', () {
    test('adds and removes bullets on selected lines', () {
      final on = toggleList(v('[a\n\nb]'), ordered: false);
      expect(on.text, '- a\n\n- b');
      expect(toggleList(on, ordered: false).text, 'a\n\nb');
    });

    test('numbers lines and converts bullets', () {
      expect(toggleList(v('[- a\n- b]'), ordered: true).text, '1. a\n2. b');
      expect(toggleList(v('|'), ordered: true).text, '1. ');
    });

    test('keeps indentation', () {
      expect(toggleList(v('  a|'), ordered: false).text, '  - a');
    });
  });

  test('depth from indentation', () {
    expect(listDepth(''), 0);
    expect(listDepth('  '), 1);
    expect(listDepth('\t'), 2);
  });
}
