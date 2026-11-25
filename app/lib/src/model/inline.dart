import 'package:flutter/services.dart';

/// Inline Markdown formatting for the format bar: bold, italic, code, links
/// and headings. Each function takes the editor value and returns the new one.

final _word = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// The selection, or the word around a collapsed caret, without surrounding
/// whitespace. Null when the caret is not inside a word.
(int, int)? _target(String text, TextSelection s) {
  var start = s.start, end = s.end;
  if (start == end) {
    bool isWord(int i) => i >= 0 && i < text.length && _word.hasMatch(text[i]);
    if (!isWord(start - 1) && !isWord(start)) return null;
    while (isWord(start - 1)) {
      start--;
    }
    while (isWord(end)) {
      end++;
    }
    return (start, end);
  }
  while (start < end && text[start].trim().isEmpty) {
    start++;
  }
  while (end > start && text[end - 1].trim().isEmpty) {
    end--;
  }
  return (start, end);
}

/// Wraps the selection (or the word at the caret) in [marker], or removes
/// the marker when it is already there. With nothing to wrap, inserts a pair
/// of markers and puts the caret between them.
TextEditingValue toggleWrap(TextEditingValue value, String marker) {
  final s = value.selection.isValid
      ? value.selection
      : TextSelection.collapsed(offset: value.text.length);
  final text = value.text;
  final m = marker.length;
  final target = _target(text, s);

  if (target == null) {
    final next = text.replaceRange(s.start, s.end, '$marker$marker');
    return TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: s.start + m),
    );
  }
  final (start, end) = target;
  final collapsed = s.isCollapsed;
  TextSelection keep(int a, int b) => collapsed
      ? TextSelection.collapsed(offset: (s.start + (a - start)).clamp(a, b))
      : TextSelection(baseOffset: a, extentOffset: b);

  // Markers just outside the target: remove them.
  if (start >= m &&
      end + m <= text.length &&
      text.substring(start - m, start) == marker &&
      text.substring(end, end + m) == marker &&
      _exact(text, start - m, end + m, marker)) {
    final next = text
        .replaceRange(end, end + m, '')
        .replaceRange(start - m, start, '');
    return TextEditingValue(text: next, selection: keep(start - m, end - m));
  }
  // Markers inside the selection: remove them.
  final inner = text.substring(start, end);
  if (inner.length >= 2 * m &&
      inner.startsWith(marker) &&
      inner.endsWith(marker) &&
      _exact(text, start, end, marker)) {
    final next = text.replaceRange(
      start,
      end,
      inner.substring(m, inner.length - m),
    );
    return TextEditingValue(
      text: next,
      selection: collapsed
          ? TextSelection.collapsed(
              offset: (s.start - m).clamp(start, end - 2 * m),
            )
          : TextSelection(baseOffset: start, extentOffset: end - 2 * m),
    );
  }

  final next = text.replaceRange(start, end, '$marker$inner$marker');
  return TextEditingValue(
    text: next,
    selection: collapsed
        ? TextSelection.collapsed(offset: s.start + m)
        : TextSelection(baseOffset: start + m, extentOffset: end + m),
  );
}

/// True when the marker run at each end of [start, end) is exactly [marker],
/// so `*` does not match one side of `**bold**`.
bool _exact(String text, int start, int end, String marker) {
  final c = marker[0], m = marker.length;
  bool at(int i) => i >= 0 && i < text.length && text[i] == c;
  if (at(start - 1) || at(end)) return false;
  if (start + m < end - m && (at(start + m) || at(end - m - 1))) return false;
  return true;
}

/// Turns the selection into a link and selects the URL placeholder, or
/// inserts `[text](url)` with "text" selected.
TextEditingValue insertLink(TextEditingValue value) {
  final s = value.selection.isValid
      ? value.selection
      : TextSelection.collapsed(offset: value.text.length);
  final text = value.text;
  final target = s.isCollapsed ? null : _target(text, s);
  if (target == null || target.$1 == target.$2) {
    const label = 'text';
    final next = text.replaceRange(s.start, s.end, '[$label](url)');
    return TextEditingValue(
      text: next,
      selection: TextSelection(
        baseOffset: s.start + 1,
        extentOffset: s.start + 1 + label.length,
      ),
    );
  }
  final (start, end) = target;
  final label = text.substring(start, end);
  final link = '[$label](url)';
  final urlStart = start + label.length + 3;
  return TextEditingValue(
    text: text.replaceRange(start, end, link),
    selection: TextSelection(baseOffset: urlStart, extentOffset: urlStart + 3),
  );
}

final _headingPrefix = RegExp(r'^(#{1,6})[ \t]+');

/// Cycles the current line through heading levels 1–3 and back to plain text.
TextEditingValue cycleHeading(TextEditingValue value) {
  final s = value.selection.isValid
      ? value.selection
      : const TextSelection.collapsed(offset: 0);
  final text = value.text;
  final start = s.start == 0 ? 0 : text.lastIndexOf('\n', s.start - 1) + 1;
  var end = text.indexOf('\n', start);
  if (end < 0) end = text.length;
  final line = text.substring(start, end);
  final current = _headingPrefix.firstMatch(line);
  final level = current == null ? 0 : current[1]!.length;
  final oldLength = current?[0]!.length ?? 0;
  final nextLevel = level >= 3 ? 0 : level + 1;
  final prefix = nextLevel == 0 ? '' : '${'#' * nextLevel} ';
  final delta = prefix.length - oldLength;
  int move(int o) => o < start
      ? o
      : o < start + oldLength
      ? start + prefix.length
      : o + delta;
  return TextEditingValue(
    text: text.replaceRange(start, start + oldLength, prefix),
    selection: TextSelection(
      baseOffset: move(s.baseOffset),
      extentOffset: move(s.extentOffset),
    ),
  );
}
