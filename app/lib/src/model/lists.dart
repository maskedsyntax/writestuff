import 'package:flutter/services.dart';

/// Markdown list editing: continuing, nesting and toggling bullet points.
///
/// Every function takes the editor value and returns the new value, or null
/// when the key should be handled normally.

final _item = RegExp(
  r'^([ \t]*)([-*+]|(\d{1,9})([.)]))([ \t]+)(\[[ xX]\][ \t]+)?',
);

class ListItem {
  ListItem(
    this.indent,
    this.marker,
    this.number,
    this.delimiter,
    this.gap,
    this.checkbox,
  );
  final String indent;
  final String marker;
  final int? number;
  final String? delimiter;
  final String gap;
  final String? checkbox;

  bool get ordered => number != null;

  /// Width of the marker plus its spacing: where nested items must start.
  int get width => marker.length + gap.length;
  int get prefixLength =>
      indent.length + marker.length + gap.length + (checkbox?.length ?? 0);

  static ListItem? parse(String line) {
    final m = _item.firstMatch(line);
    if (m == null) return null;
    return ListItem(
      m[1]!,
      m[2]!,
      m[3] == null ? null : int.parse(m[3]!),
      m[4],
      m[5]!,
      m[6],
    );
  }
}

/// Nesting depth from indentation, used for the bullet glyph.
int listDepth(String indent) {
  var columns = 0;
  for (final c in indent.codeUnits) {
    columns += c == 0x09 ? 4 : 1;
  }
  return columns ~/ 2;
}

(int, int) _lineBounds(String text, int offset) {
  final start = offset == 0 ? 0 : text.lastIndexOf('\n', offset - 1) + 1;
  var end = text.indexOf('\n', offset);
  if (end < 0) end = text.length;
  return (start, end);
}

/// Enter inside a list item: start the next item, or end an empty one.
TextEditingValue? continueList(TextEditingValue value) {
  final s = value.selection;
  if (!s.isValid || value.isComposingRangeValid) return null;
  final text = value.text;
  final (start, end) = _lineBounds(text, s.start);
  if (s.end > end) return null;
  final line = text.substring(start, end).replaceAll('\r', '');
  final item = ListItem.parse(line);
  if (item == null || s.start - start < item.prefixLength) return null;

  if (line.substring(item.prefixLength).trim().isEmpty) {
    // Empty item: outdent a nested one, otherwise end the list.
    if (item.indent.isNotEmpty) return indentLines(value, outdent: true);
    final cleared = text.replaceRange(start, end, '');
    return TextEditingValue(
      text: cleared,
      selection: TextSelection.collapsed(offset: start),
    );
  }

  final marker = item.ordered
      ? '${item.number! + 1}${item.delimiter}'
      : item.marker;
  final checkbox = item.checkbox == null ? '' : '[ ] ';
  final crlf = end < text.length && end > 0 && text[end - 1] == '\r';
  final insert =
      '${crlf ? '\r\n' : '\n'}${item.indent}$marker${item.gap}$checkbox';
  final next = text.replaceRange(s.start, s.end, insert);
  return TextEditingValue(
    text: next,
    selection: TextSelection.collapsed(offset: s.start + insert.length),
  );
}

/// The lines touched by the selection, as (start, end) offsets.
List<(int, int)> _selectedLines(String text, TextSelection s) {
  final lines = <(int, int)>[];
  var (start, end) = _lineBounds(text, s.start);
  final last = s.end > s.start && s.end > 0 && text[s.end - 1] == '\n'
      ? s.end - 1
      : s.end;
  while (true) {
    lines.add((start, end));
    if (end >= last || end >= text.length) break;
    (start, end) = _lineBounds(text, end + 1);
  }
  return lines;
}

/// The nearest list item above [lineStart] that satisfies [test].
ListItem? _above(String text, int lineStart, bool Function(ListItem) test) {
  var end = lineStart - 1;
  while (end >= 0) {
    final start = end == 0 ? 0 : text.lastIndexOf('\n', end - 1) + 1;
    final line = text.substring(start, end).replaceAll('\r', '');
    final item = ListItem.parse(line);
    if (item != null && test(item)) return item;
    if (item == null &&
        line.trim().isNotEmpty &&
        !line.startsWith(RegExp(r'[ \t]'))) {
      return null; // a paragraph ends the list
    }
    end = start - 1;
  }
  return null;
}

/// Tab / Shift+Tab on list items: nest under the previous item, or move out
/// one level. Returns null when no selected line is a list item.
TextEditingValue? indentLines(TextEditingValue value, {required bool outdent}) {
  final s = value.selection;
  if (!s.isValid || value.isComposingRangeValid) return null;
  var text = value.text;
  final lines = _selectedLines(text, s);
  if (!lines.any((l) => ListItem.parse(text.substring(l.$1, l.$2)) != null)) {
    return null;
  }
  var base = s.baseOffset, extent = s.extentOffset;
  // Work bottom-up so earlier offsets stay valid.
  for (final (start, end) in lines.reversed) {
    final item = ListItem.parse(text.substring(start, end));
    if (item == null) continue;
    final current = item.indent.length;
    int target;
    if (outdent) {
      final parent = _above(text, start, (p) => p.indent.length < current);
      target = parent?.indent.length ?? 0;
      if (target == current) continue;
    } else {
      final sibling = _above(text, start, (p) => p.indent.length <= current);
      target = sibling == null
          ? current + item.width
          : sibling.indent.length + sibling.width;
      if (target <= current) target = current + item.width;
    }
    final replacement = ' ' * target;
    final delta = replacement.length - current;
    text = text.replaceRange(start, start + current, replacement);
    int move(int o) => o >= start + current
        ? o + delta
        : o > start + target
        ? start + target
        : o;
    base = move(base);
    extent = move(extent);
  }
  return TextEditingValue(
    text: text,
    selection: TextSelection(baseOffset: base, extentOffset: extent),
  );
}

/// Turns the selected lines into a bulleted (or numbered) list, or back into
/// plain lines when they already are one.
TextEditingValue toggleList(TextEditingValue value, {required bool ordered}) {
  final s = value.selection.isValid
      ? value.selection
      : const TextSelection.collapsed(offset: 0);
  var text = value.text;
  final lines = _selectedLines(text, s);
  final items = [
    for (final (a, b) in lines) ListItem.parse(text.substring(a, b)),
  ];
  var base = s.baseOffset, extent = s.extentOffset;
  final process = [
    for (var i = 0; i < lines.length; i++)
      if (lines.length == 1 ||
          text.substring(lines[i].$1, lines[i].$2).trim().isNotEmpty)
        i,
  ];
  final remove = process.every(
    (i) => items[i] != null && items[i]!.ordered == ordered,
  );
  for (var k = process.length - 1; k >= 0; k--) {
    final i = process[k];
    final number = k + 1;
    final (start, end) = lines[i];
    final line = text.substring(start, end);
    final item = items[i];
    final indent = item?.indent ?? RegExp(r'^[ \t]*').firstMatch(line)![0]!;
    final oldEnd = start + (item?.prefixLength ?? indent.length);
    final prefix = remove
        ? indent
        : '$indent${ordered ? '$number.' : '-'} ${item?.checkbox ?? ''}';
    final delta = prefix.length - (oldEnd - start);
    text = text.replaceRange(start, oldEnd, prefix);
    int move(int o) => o >= oldEnd
        ? o + delta
        : o > start
        ? start + prefix.length
        : o;
    base = move(base);
    extent = move(extent);
  }
  return TextEditingValue(
    text: text,
    selection: TextSelection(baseOffset: base, extentOffset: extent),
  );
}
