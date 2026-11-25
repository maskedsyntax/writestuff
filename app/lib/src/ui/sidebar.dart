import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../model/document.dart';
import 'theme.dart';
import 'widgets.dart';

/// Document list: plays the role of the old tab strip.
class Sidebar extends StatelessWidget {
  const Sidebar({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final unsaved = state.tabs.where((id) => state.documents[id]!.dirty).length;
    final visible = state.panes.leaves.map((l) => l.document).toSet();
    return ColoredBox(
      color: t.sidebar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Room for the macOS traffic lights.
          SizedBox(height: Platform.isMacOS ? 52 : 14),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 6, 18, 6),
            child: Row(
              children: [
                Icon(CupertinoIcons.doc_on_doc, size: 17, color: t.muted),
                const SizedBox(width: 10),
                Text(
                  'Documents',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: t.text,
                  ),
                ),
                const Spacer(),
                if (unsaved > 0)
                  Tooltip(
                    message: '$unsaved unsaved',
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      constraints: const BoxConstraints(minWidth: 18),
                      height: 18,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: t.badge,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text(
                        '$unsaved',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                Text(
                  '${state.tabs.length}',
                  style: TextStyle(fontSize: 13, color: t.muted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
              buildDefaultDragHandles: false,
              itemCount: state.tabs.length,
              onReorderItem: state.reorder,
              proxyDecorator: (child, _, _) => Material(
                color: Colors.transparent,
                child: Opacity(opacity: 0.9, child: child),
              ),
              itemBuilder: (context, index) {
                final id = state.tabs[index];
                return ReorderableDragStartListener(
                  key: ValueKey(id),
                  index: index,
                  child: _DocumentRow(
                    document: state.documents[id]!,
                    active: id == state.activeId,
                    visible: visible.contains(id),
                    onSelect: () => state.select(id),
                    onClose: () => state.close(id),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: Row(
              children: [
                HoverButton(
                  tooltip: 'New document · ${shortcutLabel('N')}',
                  onPressed: state.newDocument,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      Icon(CupertinoIcons.plus, size: 16, color: t.muted),
                      const SizedBox(width: 8),
                      Text(
                        'New Document',
                        style: TextStyle(fontSize: 13, color: t.muted),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                HoverButton(
                  tooltip: 'Open… · ${shortcutLabel('O')}',
                  onPressed: state.open,
                  child: Icon(CupertinoIcons.folder, size: 17, color: t.muted),
                ),
                HoverButton(
                  tooltip: 'Settings · ${shortcutLabel(',')}',
                  onPressed: state.toggleSettings,
                  child: Icon(
                    CupertinoIcons.slider_horizontal_3,
                    size: 17,
                    color: t.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DocumentRow extends StatefulWidget {
  const _DocumentRow({
    required this.document,
    required this.active,
    required this.visible,
    required this.onSelect,
    required this.onClose,
  });
  final Document document;
  final bool active, visible;
  final VoidCallback onSelect, onClose;

  @override
  State<_DocumentRow> createState() => _DocumentRowState();
}

class _DocumentRowState extends State<_DocumentRow> {
  bool hover = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final doc = widget.document;
    return MouseRegion(
      onEnter: (_) => setState(() => hover = true),
      onExit: (_) => setState(() => hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onSelect,
        child: Container(
          height: 32,
          margin: const EdgeInsets.only(bottom: 1),
          padding: const EdgeInsets.only(left: 12, right: 6),
          decoration: BoxDecoration(
            color: widget.active
                ? t.selection
                : hover
                ? t.hover
                : null,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              DocumentGlyph(document: doc, size: 15, color: t.muted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  doc.name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    color: widget.visible || widget.active ? t.text : t.muted,
                  ),
                ),
              ),
              if (hover)
                HoverButton(
                  tooltip: 'Close · ${shortcutLabel('W')}',
                  onPressed: widget.onClose,
                  padding: const EdgeInsets.all(4),
                  child: Icon(CupertinoIcons.xmark, size: 11, color: t.muted),
                )
              else if (doc.dirty)
                Tooltip(
                  message: 'Unsaved changes',
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 7),
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: t.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
