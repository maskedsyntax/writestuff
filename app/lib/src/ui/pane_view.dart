import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../app_state.dart';
import '../model/document.dart';
import '../model/panes.dart';
import 'home.dart' show FindBar;
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
        if (split && state.renaming != pane.id) {
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

        final Widget body = switch (pane.mode) {
          PaneMode.edit => _Editor(state: state, pane: pane, gutter: gutter),
          PaneMode.preview => _Preview(
            state: state,
            document: doc,
            gutter: gutter,
          ),
          PaneMode.split => Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _Editor(
                  state: state,
                  pane: pane,
                  gutter: gutter,
                  inner: 20,
                ),
              ),
              Container(width: 1, color: t.hairline),
              Expanded(
                child: ColoredBox(
                  color: t.sidebar.withValues(alpha: 0.35),
                  child: _Preview(
                    state: state,
                    document: doc,
                    gutter: gutter,
                    inner: 24,
                  ),
                ),
              ),
            ],
          ),
        };

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
                      if (active && state.findOpen)
                        FindBar(state: state, gutter: gutter),
                      Expanded(child: body),
                      if (!pane.preview && doc.isMarkdown)
                        _FormatBar(
                          state: state,
                          pane: pane,
                          gutter: gutter,
                          compact: constraints.maxWidth < 520,
                        ),
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
    final titleStyle = TextStyle(
      fontSize: titleSize,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.4,
      color: titleColor,
    );

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

    Widget tool(
      IconData icon,
      String tip,
      VoidCallback? action, {
      bool on = false,
    }) => HoverButton(
      tooltip: tip,
      onPressed: action,
      padding: const EdgeInsets.all(7),
      child: Icon(
        icon,
        size: 16,
        color: on ? t.accent : (active ? t.muted : t.faint),
      ),
    );
    final canSplit = state.panes.length < Panes.maxPanes;

    final title = state.renaming == pane.id
        ? _TitleEditor(state: state, document: doc, style: titleStyle)
        : MouseRegion(
            cursor: SystemMouseCursors.text,
            child: GestureDetector(
              onTap: () => state.startRename(pane),
              child: Tooltip(
                message: 'Click to rename',
                waitDuration: const Duration(seconds: 1),
                child: Text(
                  doc.name,
                  overflow: TextOverflow.ellipsis,
                  style: titleStyle,
                ),
              ),
            ),
          );

    return Padding(
      padding: EdgeInsets.fromLTRB(gutter - 4, compact ? 14 : 30, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(width: 4),
              _StateDot(
                size: titleSize * 0.95,
                active: active,
                dirty: doc.dirty,
              ),
              SizedBox(width: compact ? 10 : 14),
              Expanded(
                child: Row(
                  children: [
                    Flexible(child: title),
                    const SizedBox(width: 10),
                    _PaneMenu(state: state, pane: pane),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              tool(
                CupertinoIcons.search,
                'Find and replace · ${shortcutLabel('F')}',
                () {
                  state.focusPane(pane);
                  state.toggleFind();
                },
                on: active && state.findOpen,
              ),
              tool(
                CupertinoIcons.square_split_2x1,
                'Split right · ${shortcutLabel('D')}',
                canSplit ? () => state.split(horizontal: true) : null,
              ),
              tool(
                CupertinoIcons.square_split_1x2,
                'Split down · ${shortcutLabel('D', shift: true)}',
                canSplit ? () => state.split(horizontal: false) : null,
              ),
              if (split)
                tool(
                  CupertinoIcons.xmark,
                  'Close pane · ${shortcutLabel('W', shift: true)}',
                  () => state.closePane(pane),
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
              for (final (mode, label, tip) in [
                (PaneMode.edit, 'Edit', null),
                (
                  PaneMode.split,
                  'Side by side',
                  shortcutLabel('P', shift: true),
                ),
                (PaneMode.preview, 'Preview', shortcutLabel('P')),
              ]) ...[
                PillChip(
                  label: label,
                  tooltip: tip,
                  selected: pane.mode == mode,
                  onTap: () => state.setMode(mode, pane),
                ),
                const SizedBox(width: 4),
              ],
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

/// Ring next to the title: hollow when saved, half filled with unsaved changes.
class _StateDot extends StatelessWidget {
  const _StateDot({
    required this.size,
    required this.active,
    required this.dirty,
  });
  final double size;
  final bool active, dirty;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = active ? t.accent : t.faint;
    return Tooltip(
      message: dirty ? 'Unsaved changes' : 'Saved',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 2),
        ),
        child: dirty
            ? ClipOval(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: 0.5,
                    heightFactor: 1,
                    child: ColoredBox(color: color),
                  ),
                ),
              )
            : null,
      ),
    );
  }
}

/// Inline title field. Enter or clicking away commits; Esc cancels.
class _TitleEditor extends StatefulWidget {
  const _TitleEditor({
    required this.state,
    required this.document,
    required this.style,
  });
  final AppState state;
  final Document document;
  final TextStyle style;

  @override
  State<_TitleEditor> createState() => _TitleEditorState();
}

class _TitleEditorState extends State<_TitleEditor> {
  late final controller = TextEditingController(text: widget.document.name);
  final focus = FocusNode();
  bool done = false;

  @override
  void initState() {
    super.initState();
    // Select the name without its extension, like Finder.
    final name = controller.text;
    final dot = name.lastIndexOf('.');
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: dot > 0 ? dot : name.length,
    );
    focus.addListener(() {
      if (!focus.hasFocus) _commit();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => focus.requestFocus());
  }

  void _commit() {
    if (done) return;
    done = true;
    widget.state.rename(widget.document.id, controller.text);
  }

  @override
  void dispose() {
    focus.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          done = true;
          widget.state.cancelRename();
        },
      },
      child: IntrinsicWidth(
        child: TextField(
          controller: controller,
          focusNode: focus,
          style: widget.style,
          cursorColor: t.accent,
          onSubmitted: (_) => _commit(),
          decoration: InputDecoration(
            isCollapsed: true,
            border: InputBorder.none,
            constraints: const BoxConstraints(minWidth: 120),
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            filled: true,
            fillColor: t.hover,
          ),
        ),
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
        item('Rename…', null, () => state.startRename(pane)),
        item('Open…', shortcutLabel('O'), state.open),
        const PopupMenuDivider(height: 9),
        item(
          'Bulleted list',
          shortcutLabel('8', shift: true),
          () => state.toggleList(ordered: false),
          enabled: !pane.preview,
        ),
        item(
          'Numbered list',
          shortcutLabel('7', shift: true),
          () => state.toggleList(ordered: true),
          enabled: !pane.preview,
        ),
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
          pane.preview ? 'Edit' : 'Preview',
          shortcutLabel('P'),
          state.togglePreview,
        ),
        item(
          pane.mode == PaneMode.split
              ? 'Hide side-by-side preview'
              : 'Side by side',
          shortcutLabel('P', shift: true),
          state.toggleSideBySide,
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

/// Formatting buttons under the editor, always in reach while typing.
class _FormatBar extends StatelessWidget {
  const _FormatBar({
    required this.state,
    required this.pane,
    required this.gutter,
    required this.compact,
  });
  final AppState state;
  final PaneLeaf pane;
  final double gutter;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final controller = state.controllerFor(pane);

    Widget button(Widget child, String tip, VoidCallback action) => Padding(
      padding: const EdgeInsets.only(right: 6),
      child: _FormatButton(tooltip: tip, onPressed: action, child: child),
    );
    Widget glyph(String text, {FontStyle? style, TextDecoration? deco}) => Text(
      text,
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        fontStyle: style,
        decoration: deco,
        decorationColor: t.text,
        decorationThickness: 2,
        color: t.text,
        height: 1,
      ),
    );
    Widget icon(IconData data) => Icon(data, size: 17, color: t.text);
    final divider = Container(
      width: 1,
      height: 20,
      margin: const EdgeInsets.only(left: 4, right: 10),
      color: t.hairline,
    );

    // Taps on the bar count as taps inside the editor, so it keeps focus
    // and its selection.
    return TextFieldTapRegion(
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: t.hairline)),
        ),
        padding: EdgeInsets.fromLTRB(gutter - 6, 8, gutter, 8),
        child: Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    button(
                      glyph('B'),
                      'Bold  ${shortcutLabel('B')}',
                      state.bold,
                    ),
                    button(
                      glyph('I', style: FontStyle.italic),
                      'Italic  ${shortcutLabel('I')}',
                      state.italic,
                    ),
                    button(
                      glyph('S', deco: TextDecoration.lineThrough),
                      'Strikethrough  ${shortcutLabel('X', shift: true)}',
                      state.strikethrough,
                    ),
                    button(
                      icon(Icons.code_rounded),
                      'Code  ${shortcutLabel('E')}',
                      state.code,
                    ),
                    button(
                      icon(Icons.link_rounded),
                      'Link  ${shortcutLabel('K')}',
                      state.link,
                    ),
                    button(glyph('H'), 'Heading (H1 → H2 → H3)', state.heading),
                    divider,
                    button(
                      icon(Icons.format_list_bulleted_rounded),
                      'Bulleted list  ${shortcutLabel('8', shift: true)}',
                      () => state.toggleList(ordered: false),
                    ),
                    button(
                      icon(Icons.format_list_numbered_rounded),
                      'Numbered list  ${shortcutLabel('7', shift: true)}',
                      () => state.toggleList(ordered: true),
                    ),
                    button(
                      icon(Icons.checklist_rounded),
                      'Checklist  ${shortcutLabel('9', shift: true)}',
                      () => state.toggleList(ordered: false, task: true),
                    ),
                  ],
                ),
              ),
            ),
            if (!compact)
              ListenableBuilder(
                listenable: controller,
                builder: (context, _) {
                  final s = controller.selection;
                  final selected = s.isValid && !s.isCollapsed
                      ? s.textInside(controller.text)
                      : '';
                  final words = RegExp(r'\S+').allMatches(selected).length;
                  return Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Text(
                      selected.isEmpty
                          ? 'Select text to format'
                          : '$words ${words == 1 ? 'word' : 'words'} selected',
                      style: TextStyle(fontSize: 12.5, color: t.muted),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// A square, softly filled button like the ones in Things' editing bar.
class _FormatButton extends StatefulWidget {
  const _FormatButton({
    required this.child,
    required this.tooltip,
    required this.onPressed,
  });
  final Widget child;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  State<_FormatButton> createState() => _FormatButtonState();
}

class _FormatButtonState extends State<_FormatButton> {
  bool hover = false, down = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => hover = true),
        onExit: (_) => setState(() => hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => down = true),
          onTapCancel: () => setState(() => down = false),
          onTap: () {
            setState(() => down = false);
            widget.onPressed();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 90),
            width: 34,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: down
                  ? t.chip
                  : hover
                  ? t.selection
                  : t.hover,
              borderRadius: BorderRadius.circular(8),
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class _Editor extends StatelessWidget {
  const _Editor({
    required this.state,
    required this.pane,
    required this.gutter,
    this.inner,
  });
  final AppState state;
  final PaneLeaf pane;
  final double gutter;

  /// Right padding when the preview sits beside the editor.
  final double? inner;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final controller = state.controllerFor(pane)..palette = t.highlight;
    final style = editorStyle(state.settings, t.text);
    final padding = EdgeInsets.fromLTRB(gutter, 6, inner ?? gutter, 16);

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
    this.inner,
  });
  final AppState state;
  final Document document;
  final double gutter;

  /// Left padding when the preview sits beside the editor.
  final double? inner;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
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
      padding: EdgeInsets.fromLTRB(inner ?? gutter, 6, gutter, 80),
      styleSheet: sheet,
      onTapLink: (text, href, title) =>
          state.showNotice('Link: ${href ?? text}'),
      // The default checkbox icon is nearly invisible on the dark canvas.
      checkboxBuilder: (checked) => Padding(
        padding: EdgeInsets.only(right: size * 0.5, top: size * 0.3),
        child: Container(
          width: size * 0.95,
          height: size * 0.95,
          decoration: BoxDecoration(
            color: checked ? t.accent : null,
            borderRadius: BorderRadius.circular(size * 0.22),
            border: Border.all(color: checked ? t.accent : t.muted, width: 1.5),
          ),
          child: checked
              ? Icon(Icons.check_rounded, size: size * 0.8, color: Colors.white)
              : null,
        ),
      ),
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
