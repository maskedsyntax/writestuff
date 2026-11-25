import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../app_state.dart';
import '../model/document.dart';
import '../model/panes.dart';
import 'theme.dart';
import 'widgets.dart';

/// Recursively lays out the split tree with draggable dividers.
class PaneGrid extends StatelessWidget {
  const PaneGrid({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) =>
      _node(context, state.panes.root, atTop: true);

  Widget _node(BuildContext context, PaneNode node, {required bool atTop}) {
    switch (node) {
      case PaneLeaf():
        return PaneView(
          key: ObjectKey(node),
          state: state,
          pane: node,
          atTop: atTop,
        );
      case PaneSplit():
        return LayoutBuilder(
          builder: (context, constraints) {
            final horizontal = node.horizontal;
            final total = horizontal
                ? constraints.maxWidth
                : constraints.maxHeight;
            const divider = 1.0;
            final first = (total - divider) * node.ratio;
            final children = [
              SizedBox(
                width: horizontal ? first : null,
                height: horizontal ? null : first,
                child: _node(context, node.first, atTop: atTop),
              ),
              _Divider(
                horizontal: horizontal,
                onDrag: (delta) =>
                    state.resize(node, node.ratio + delta / total),
              ),
              Expanded(
                child: _node(
                  context,
                  node.second,
                  atTop: horizontal ? atTop : false,
                ),
              ),
            ];
            return horizontal
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children,
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children,
                  );
          },
        );
    }
  }
}

class _Divider extends StatefulWidget {
  const _Divider({required this.horizontal, required this.onDrag});
  final bool horizontal;
  final ValueChanged<double> onDrag;

  @override
  State<_Divider> createState() => _DividerState();
}

class _DividerState extends State<_Divider> {
  bool active = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final h = widget.horizontal;
    return SizedBox(
      width: h ? 1 : null,
      height: h ? null : 1,
      child: OverflowBox(
        maxWidth: h ? 9 : null,
        maxHeight: h ? null : 9,
        child: MouseRegion(
          cursor: h
              ? SystemMouseCursors.resizeColumn
              : SystemMouseCursors.resizeRow,
          onEnter: (_) => setState(() => active = true),
          onExit: (_) => setState(() => active = false),
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragUpdate: h ? (d) => widget.onDrag(d.delta.dx) : null,
            onVerticalDragUpdate: h ? null : (d) => widget.onDrag(d.delta.dy),
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: h ? (active ? 2 : 1) : double.infinity,
                height: h ? double.infinity : (active ? 2 : 1),
                color: active ? t.accent : t.hairline,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One editor pane: big title, chips, then the editor or Markdown preview.
class PaneView extends StatefulWidget {
  const PaneView({
    super.key,
    required this.state,
    required this.pane,
    required this.atTop,
  });
  final AppState state;
  final PaneLeaf pane;
  final bool atTop;

  @override
  State<PaneView> createState() => _PaneViewState();
}

class _PaneViewState extends State<PaneView> {
  DropEdge? _hoverEdge;

  DropEdge _edgeFor(Offset global) {
    final box = context.findRenderObject() as RenderBox;
    final local = box.globalToLocal(global);
    final size = box.size;
    final x = local.dx / size.width, y = local.dy / size.height;
    if (x > 0.3 && x < 0.7 && y > 0.3 && y < 0.7) return DropEdge.center;
    final distances = {
      DropEdge.left: x,
      DropEdge.right: 1 - x,
      DropEdge.top: y,
      DropEdge.bottom: 1 - y,
    };
    return distances.entries.reduce((a, b) => a.value <= b.value ? a : b).key;
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final pane = widget.pane;
    final t = context.tokens;
    final doc = state.documents[pane.document]!;
    final active = identical(state.panes.active, pane);
    final split = state.panes.length > 1;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = split || constraints.maxWidth < 560;
        final gutter = constraints.maxWidth < 520 ? 24.0 : 56.0;
        final top = widget.atTop && Platform.isMacOS ? 30.0 : 0.0;

        Widget header = _Header(
          state: state,
          pane: pane,
          document: doc,
          active: active,
          compact: compact,
          gutter: gutter,
        );
        if (split) {
          header = Draggable<PaneLeaf>(
            data: pane,
            dragAnchorStrategy: pointerDragAnchorStrategy,
            feedback: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: t.card,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: const [
                    BoxShadow(blurRadius: 16, color: Color(0x33000000)),
                  ],
                ),
                child: Text(
                  doc.name,
                  style: TextStyle(fontSize: 13, color: t.text),
                ),
              ),
            ),
            child: MouseRegion(cursor: SystemMouseCursors.grab, child: header),
          );
        }

        final body = pane.preview
            ? _Preview(state: state, document: doc, gutter: gutter)
            : _Editor(state: state, pane: pane, gutter: gutter);

        return DragTarget<PaneLeaf>(
          onWillAcceptWithDetails: (d) => !identical(d.data, pane),
          onMove: (d) => setState(() => _hoverEdge = _edgeFor(d.offset)),
          onLeave: (_) => setState(() => _hoverEdge = null),
          onAcceptWithDetails: (d) {
            final edge = _edgeFor(d.offset);
            setState(() => _hoverEdge = null);
            state.movePane(d.data, pane, edge);
          },
          builder: (context, _, _) => Listener(
            onPointerDown: (_) => state.focusPane(pane),
            child: ColoredBox(
              color: t.canvas,
              child: Stack(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(height: top),
                      header,
                      Expanded(child: body),
                    ],
                  ),
                  if (_hoverEdge != null) _DropHighlight(edge: _hoverEdge!),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DropHighlight extends StatelessWidget {
  const _DropHighlight({required this.edge});
  final DropEdge edge;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final (alignment, w, h) = switch (edge) {
      DropEdge.left => (Alignment.centerLeft, 0.5, 1.0),
      DropEdge.right => (Alignment.centerRight, 0.5, 1.0),
      DropEdge.top => (Alignment.topCenter, 1.0, 0.5),
      DropEdge.bottom => (Alignment.bottomCenter, 1.0, 0.5),
      DropEdge.center => (Alignment.center, 1.0, 1.0),
    };
    return Positioned.fill(
      child: IgnorePointer(
        child: FractionallySizedBox(
          alignment: alignment,
          widthFactor: w,
          heightFactor: h,
          child: Container(
            margin: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: t.accent.withValues(alpha: 0.10),
              border: Border.all(color: t.accent.withValues(alpha: 0.6)),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.state,
    required this.pane,
    required this.document,
    required this.active,
    required this.compact,
    required this.gutter,
  });
  final AppState state;
  final PaneLeaf pane;
  final Document document;
  final bool active, compact;
  final double gutter;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final doc = document;
    final titleColor = active ? t.text : t.muted;
    final titleSize = compact ? 21.0 : 27.0;
    final split = state.panes.length > 1;

    final subtitle = doc.path == null
        ? (doc.dirty ? 'Not saved yet' : 'New document')
        : _friendlyDirectory(doc.path!);
    String? status;
    if (state.settings.status && !pane.preview) {
      final (line, col) = active ? state.cursor : (0, 0);
      status = [
        doc.isMarkdown ? 'Markdown' : 'Plain text',
        '${doc.words} words',
        '${doc.characters} characters',
        if (active) 'Ln $line, Col $col',
      ].join('  ·  ');
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(gutter - 4, compact ? 14 : 30, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(width: 4),
              Container(
                width: titleSize * 0.95,
                height: titleSize * 0.95,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: active ? t.accent : t.faint,
                    width: 2,
                  ),
                ),
                child: ClipOval(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: doc.dirty ? 0.5 : 1,
                      heightFactor: 1,
                      child: ColoredBox(
                        color: (active ? t.accent : t.faint).withValues(
                          alpha: doc.dirty ? 1 : 0.0,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(width: compact ? 10 : 14),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Tooltip(
                        message: doc.dirty ? 'Unsaved changes' : '',
                        child: Text(
                          doc.name,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: titleSize,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.4,
                            color: titleColor,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _PaneMenu(state: state, pane: pane),
                  ],
                ),
              ),
              if (split)
                HoverButton(
                  tooltip: 'Close pane · ${shortcutLabel('W', shift: true)}',
                  onPressed: () => state.closePane(pane),
                  child: Icon(CupertinoIcons.xmark, size: 13, color: t.muted),
                ),
            ],
          ),
          Padding(
            padding: EdgeInsets.only(left: 4, top: compact ? 4 : 10),
            child: Text(
              subtitle,
              overflow: TextOverflow.fade,
              softWrap: false,
              style: TextStyle(
                fontSize: compact ? 12.5 : 14.5,
                color: t.muted,
                height: 1.4,
              ),
            ),
          ),
          SizedBox(height: compact ? 10 : 22),
          Row(
            children: [
              PillChip(
                label: 'Edit',
                selected: !pane.preview,
                onTap: () => state.setPreview(false, pane),
              ),
              const SizedBox(width: 4),
              PillChip(
                label: 'Preview',
                selected: pane.preview,
                tooltip: doc.isMarkdown ? null : 'Markdown files only',
                onTap: () => state.setPreview(true, pane),
              ),
              const SizedBox(width: 16),
              if (status != null)
                Expanded(
                  child: Text(
                    status,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 12, color: t.faint),
                  ),
                ),
              const SizedBox(width: 18),
            ],
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

class _PaneMenu extends StatelessWidget {
  const _PaneMenu({required this.state, required this.pane});
  final AppState state;
  final PaneLeaf pane;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    PopupMenuItem<VoidCallback> item(
      String label,
      String? keys,
      VoidCallback action, {
      bool enabled = true,
    }) => PopupMenuItem(
      value: action,
      enabled: enabled,
      height: 32,
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontSize: 13)),
          const Spacer(),
          if (keys != null)
            Text(keys, style: TextStyle(fontSize: 12, color: t.muted)),
        ],
      ),
    );
    return PopupMenuButton<VoidCallback>(
      tooltip: 'Document actions',
      color: t.card,
      elevation: 8,
      constraints: const BoxConstraints(minWidth: 230),
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: t.hairline),
      ),
      onOpened: () => state.focusPane(pane),
      onSelected: (action) => action(),
      itemBuilder: (_) => [
        item('Save', shortcutLabel('S'), () => state.save()),
        item(
          'Save as…',
          shortcutLabel('S', shift: true),
          () => state.save(asNew: true),
        ),
        item('Open…', shortcutLabel('O'), state.open),
        const PopupMenuDivider(height: 9),
        item(
          'Split right',
          shortcutLabel('D'),
          () => state.split(horizontal: true),
          enabled: state.panes.length < 8,
        ),
        item(
          'Split down',
          shortcutLabel('D', shift: true),
          () => state.split(horizontal: false),
          enabled: state.panes.length < 8,
        ),
        item(
          pane.preview ? 'Edit' : 'Preview Markdown',
          null,
          state.togglePreview,
        ),
        item('Find and replace…', shortcutLabel('F'), state.toggleFind),
        const PopupMenuDivider(height: 9),
        if (state.panes.length > 1)
          item(
            'Close pane',
            shortcutLabel('W', shift: true),
            () => state.closePane(pane),
          ),
        item('Close document', shortcutLabel('W'), () => state.close()),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Icon(CupertinoIcons.ellipsis, size: 18, color: t.faint),
      ),
    );
  }
}

class _Editor extends StatelessWidget {
  const _Editor({
    required this.state,
    required this.pane,
    required this.gutter,
  });
  final AppState state;
  final PaneLeaf pane;
  final double gutter;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final controller = state.controllerFor(pane)..palette = t.highlight;
    final style = editorStyle(state.settings, t.text);
    final padding = EdgeInsets.fromLTRB(gutter, 6, gutter, 16);

    Widget field(double? width) => SizedBox(
      width: width,
      child: TextField(
        key: state.editorKeyFor(pane),
        controller: controller,
        focusNode: state.focusFor(pane),
        maxLines: null,
        expands: true,
        keyboardType: TextInputType.multiline,
        textAlignVertical: TextAlignVertical.top,
        style: style,
        strutStyle: StrutStyle.fromTextStyle(style, forceStrutHeight: true),
        cursorColor: t.accent,
        cursorWidth: 2,
        autocorrect: false,
        enableSuggestions: false,
        smartDashesType: SmartDashesType.disabled,
        smartQuotesType: SmartQuotesType.disabled,
        decoration: InputDecoration(
          isCollapsed: true,
          border: InputBorder.none,
          contentPadding: padding,
          hintText: 'Start writing…',
          hintStyle: style.copyWith(color: t.faint),
        ),
      ),
    );

    if (state.settings.wrap) return field(null);

    // No wrapping: size the field to the longest line and scroll sideways.
    return LayoutBuilder(
      builder: (context, constraints) {
        final lines = controller.text.split('\n')
          ..sort((a, b) => b.length - a.length);
        var longest = 0.0;
        for (final line in lines.take(8)) {
          final painter = TextPainter(
            text: TextSpan(text: line, style: style),
            textDirection: TextDirection.ltr,
            maxLines: 1,
          )..layout();
          longest = math.max(longest, painter.width);
          painter.dispose();
        }
        final width = math.max(
          constraints.maxWidth,
          longest + padding.horizontal + style.fontSize!,
        );
        return Scrollbar(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: field(width),
          ),
        );
      },
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({
    required this.state,
    required this.document,
    required this.gutter,
  });
  final AppState state;
  final Document document;
  final double gutter;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    if (!document.isMarkdown) {
      return Padding(
        padding: EdgeInsets.fromLTRB(gutter, 16, gutter, 0),
        child: Text(
          'Save this document as .md to preview Markdown.',
          style: TextStyle(fontSize: 14, color: t.muted),
        ),
      );
    }
    final size = state.settings.size;
    final base = TextStyle(fontSize: size, height: 1.55, color: t.text);
    final sheet = MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: base,
      h1: base.copyWith(fontSize: size * 1.7, fontWeight: FontWeight.w700),
      h2: base.copyWith(
        fontSize: size * 1.35,
        fontWeight: FontWeight.w700,
        color: t.accent,
      ),
      h3: base.copyWith(fontSize: size * 1.15, fontWeight: FontWeight.w600),
      listBullet: base.copyWith(color: t.muted),
      a: base.copyWith(color: t.accent),
      code: base.copyWith(
        fontFamily: 'Menlo',
        fontFamilyFallback: const ['Consolas', 'monospace'],
        fontSize: size * 0.88,
        color: t.code,
        backgroundColor: t.codeBackground,
      ),
      codeblockDecoration: BoxDecoration(
        color: t.codeBackground,
        borderRadius: BorderRadius.circular(6),
      ),
      blockquote: base.copyWith(color: t.muted),
      blockquoteDecoration: BoxDecoration(
        border: Border(left: BorderSide(color: t.hairline, width: 3)),
      ),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.hairline)),
      ),
      h2Padding: const EdgeInsets.only(top: 18, bottom: 6),
    );
    return Markdown(
      data: document.text,
      selectable: true,
      padding: EdgeInsets.fromLTRB(gutter, 6, gutter, 80),
      styleSheet: sheet,
      onTapLink: (text, href, title) =>
          state.showNotice('Link: ${href ?? text}'),
      // No remote images; show the alt text instead.
      imageBuilder: (uri, title, alt) => Text(
        alt ?? uri.toString(),
        style: base.copyWith(color: t.muted, fontStyle: FontStyle.italic),
      ),
    );
  }
}

/// The containing folder, with the home directory shown as `~`.
String _friendlyDirectory(String path) {
  var dir = File(path).parent.path;
  final home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
  if (home != null && home.isNotEmpty && dir.startsWith(home)) {
    dir = '~${dir.substring(home.length)}';
  }
  return dir;
}
