import 'package:flutter/material.dart';

/// Colors used by the in-editor Markdown highlighter and find matches.
class HighlightPalette {
  const HighlightPalette({
    required this.accent,
    required this.muted,
    required this.code,
    required this.codeBackground,
    required this.match,
    required this.currentMatch,
  });
  final Color accent, muted, code, codeBackground, match, currentMatch;
}

class _Mark {
  _Mark(this.start, this.end, this.style);
  final int start, end;
  final TextStyle style;
}

/// A text controller for one pane. It highlights Markdown syntax and find
/// matches without changing the text.
class EditorController extends TextEditingController {
  EditorController({super.text});

  bool markdown = false;
  String query = '';
  TextRange? currentMatch;
  HighlightPalette? palette;

  static final _heading = RegExp(r'^#{1,6}[ \t].*$', multiLine: true);
  static final _quote = RegExp(r'^[ \t]*>.*$', multiLine: true);
  static final _list = RegExp(
    r'^[ \t]*(?:[-*+]|\d+[.)])(?=[ \t])',
    multiLine: true,
  );
  static final _rule = RegExp(
    r'^[ \t]*(?:-{3,}|\*{3,}|_{3,})[ \t]*$',
    multiLine: true,
  );
  static final _fence = RegExp(
    r'^[ \t]*```[^\n]*\n[\s\S]*?(?:^[ \t]*```[ \t]*$|(?![\s\S]))',
    multiLine: true,
  );
  static final _inlineCode = RegExp(r'`[^`\n]+`');
  static final _strong = RegExp(r'(\*\*|__)(?=\S)[^\n]*?\S\1');
  static final _emphasis = RegExp(
    r'(?<![*_\w])([*_])(?=\S)[^*_\n]*?\S\1(?![*_\w])',
  );
  static final _link = RegExp(r'!?\[[^\]\n]*\]\([^)\n]*\)');

  List<_Mark> _marks(String text) {
    final pal = palette;
    if (pal == null) return const [];
    final marks = <_Mark>[];
    void add(RegExp re, TextStyle style) {
      for (final m in re.allMatches(text)) {
        if (m.end > m.start) marks.add(_Mark(m.start, m.end, style));
      }
    }

    if (markdown) {
      add(_heading, TextStyle(fontWeight: FontWeight.w700, color: pal.accent));
      add(_quote, TextStyle(color: pal.muted, fontStyle: FontStyle.italic));
      add(_list, TextStyle(color: pal.accent));
      add(_rule, TextStyle(color: pal.muted));
      add(_strong, const TextStyle(fontWeight: FontWeight.w700));
      add(_emphasis, const TextStyle(fontStyle: FontStyle.italic));
      add(_link, TextStyle(color: pal.accent));
      add(
        _inlineCode,
        TextStyle(color: pal.code, backgroundColor: pal.codeBackground),
      );
      add(
        _fence,
        TextStyle(color: pal.code, backgroundColor: pal.codeBackground),
      );
    }
    if (query.isNotEmpty) {
      var i = text.indexOf(query);
      while (i >= 0) {
        marks.add(
          _Mark(i, i + query.length, TextStyle(backgroundColor: pal.match)),
        );
        i = text.indexOf(query, i + query.length);
      }
      final current = currentMatch;
      if (current != null &&
          current.end <= text.length &&
          text.substring(current.start, current.end) == query) {
        marks.add(
          _Mark(
            current.start,
            current.end,
            TextStyle(backgroundColor: pal.currentMatch),
          ),
        );
      }
    }
    return marks;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    // Leave IME composition rendering to the framework.
    if (withComposing && value.isComposingRangeValid) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    final text = this.text;
    final marks = _marks(text);
    if (marks.isEmpty) return TextSpan(style: style, text: text);

    // Split the text at every mark boundary and merge overlapping styles.
    final points = <int>{0, text.length};
    for (final m in marks) {
      points
        ..add(m.start)
        ..add(m.end);
    }
    final sorted = points.toList()..sort();
    final children = <TextSpan>[];
    for (var i = 0; i + 1 < sorted.length; i++) {
      final a = sorted[i], b = sorted[i + 1];
      if (a == b) continue;
      TextStyle? merged;
      for (final m in marks) {
        if (m.start <= a && m.end >= b) {
          merged = merged == null ? m.style : merged.merge(m.style);
        }
      }
      children.add(TextSpan(text: text.substring(a, b), style: merged));
    }
    return TextSpan(style: style, children: children);
  }
}
