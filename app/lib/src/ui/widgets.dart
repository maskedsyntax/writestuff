import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../model/document.dart';
import 'theme.dart';

String shortcutLabel(String key, {bool shift = false}) {
  final mod = Platform.isMacOS ? '⌘' : 'Ctrl+';
  final s = shift ? (Platform.isMacOS ? '⇧' : 'Shift+') : '';
  return Platform.isMacOS ? '$s$mod$key' : '$mod$s$key';
}

/// A quiet icon/text button that only shows a background on hover.
class HoverButton extends StatefulWidget {
  const HoverButton({
    super.key,
    required this.child,
    required this.onPressed,
    this.tooltip,
    this.padding = const EdgeInsets.all(6),
  });
  final Widget child;
  final VoidCallback? onPressed;
  final String? tooltip;
  final EdgeInsets padding;

  @override
  State<HoverButton> createState() => _HoverButtonState();
}

class _HoverButtonState extends State<HoverButton> {
  bool hover = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    Widget button = MouseRegion(
      cursor: widget.onPressed == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => hover = true),
      onExit: (_) => setState(() => hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          padding: widget.padding,
          decoration: BoxDecoration(
            color: hover && widget.onPressed != null ? t.hover : null,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Opacity(
            opacity: widget.onPressed == null ? 0.4 : 1,
            child: widget.child,
          ),
        ),
      ),
    );
    if (widget.tooltip != null) {
      button = Tooltip(message: widget.tooltip!, child: button);
    }
    return button;
  }
}

/// Rounded pill used for the Edit / Preview filter chips.
class PillChip extends StatelessWidget {
  const PillChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.tooltip,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return HoverButton(
      tooltip: tooltip,
      onPressed: onTap,
      padding: EdgeInsets.zero,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 3),
        decoration: BoxDecoration(
          color: selected ? t.chip : null,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? t.text : t.muted,
          ),
        ),
      ),
    );
  }
}

/// Icon for a document: Markdown, plain text, or not yet saved.
class DocumentGlyph extends StatelessWidget {
  const DocumentGlyph({
    super.key,
    required this.document,
    required this.size,
    this.color,
  });
  final Document document;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final icon = document.path == null
        ? CupertinoIcons.doc
        : document.isMarkdown
        ? CupertinoIcons.doc_richtext
        : CupertinoIcons.doc_plaintext;
    return Icon(icon, size: size, color: color);
  }
}
