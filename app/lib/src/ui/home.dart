import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../storage/session.dart';
import 'pane_view.dart';
import 'sidebar.dart';
import 'theme.dart';
import 'widgets.dart';

/// Maps a key press to an app command, mirroring the Rust `shortcut()`.
/// Cmd on macOS, Ctrl elsewhere; never with Alt.
VoidCallback? shortcutFor(AppState state, KeyEvent event) {
  if (event is KeyUpEvent) return null;
  final keys = HardwareKeyboard.instance;
  final command = Platform.isMacOS ? keys.isMetaPressed : keys.isControlPressed;
  if (!command || keys.isAltPressed) return null;
  final shift = keys.isShiftPressed;
  final key = event.logicalKey;
  final repeat = event is KeyRepeatEvent;

  if (key == LogicalKeyboardKey.equal ||
      key == LogicalKeyboardKey.add ||
      key == LogicalKeyboardKey.numpadAdd) {
    return () => state.zoom(1);
  }
  if (key == LogicalKeyboardKey.minus ||
      key == LogicalKeyboardKey.numpadSubtract) {
    return () => state.zoom(-1);
  }
  if (key == LogicalKeyboardKey.keyZ || key == LogicalKeyboardKey.keyY) {
    if (key == LogicalKeyboardKey.keyY && (Platform.isMacOS || shift)) {
      return null;
    }
    // Leave undo in other text fields (find bar) to those fields.
    if (!state.editorFocused) return null;
    final redo = key == LogicalKeyboardKey.keyY || shift;
    return () => state.undo(redo: redo);
  }
  if (repeat) return null;
  if (key == LogicalKeyboardKey.keyN || key == LogicalKeyboardKey.keyT) {
    return state.newDocument;
  }
  if (key == LogicalKeyboardKey.keyO) return state.open;
  if (key == LogicalKeyboardKey.keyS) return () => state.save(asNew: shift);
  if (key == LogicalKeyboardKey.keyW) {
    return shift ? state.closePane : state.close;
  }
  if (key == LogicalKeyboardKey.keyD) {
    return () => state.split(horizontal: !shift);
  }
  if (key == LogicalKeyboardKey.keyF) return state.toggleFind;
  if (shift &&
      (key == LogicalKeyboardKey.digit8 ||
          key == LogicalKeyboardKey.asterisk)) {
    return () => state.toggleList(ordered: false);
  }
  if (shift &&
      (key == LogicalKeyboardKey.digit7 ||
          key == LogicalKeyboardKey.ampersand)) {
    return () => state.toggleList(ordered: true);
  }
  if (key == LogicalKeyboardKey.comma) return state.toggleSettings;
  return null;
}

class Home extends StatelessWidget {
  const Home({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        final action = shortcutFor(state, event);
        if (action == null) return KeyEventResult.ignored;
        action();
        return KeyEventResult.handled;
      },
      child: Material(
        color: t.canvas,
        child: Stack(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: 250, child: Sidebar(state: state)),
                Container(width: 1, color: t.hairline.withValues(alpha: 0.6)),
                Expanded(child: PaneGrid(state: state)),
              ],
            ),
            if (state.notice != null)
              Positioned(
                left: 251,
                right: 0,
                bottom: 24,
                child: Center(child: _Notice(state: state)),
              ),
            if (state.settingsOpen)
              _Modal(
                onDismiss: state.toggleSettings,
                child: SettingsCard(state: state),
              ),
            if (state.confirm != null)
              _Modal(child: _ConfirmCard(state: state)),
          ],
        ),
      ),
    );
  }
}

class FindBar extends StatefulWidget {
  const FindBar({super.key, required this.state, required this.gutter});
  final AppState state;
  final double gutter;

  @override
  State<FindBar> createState() => _FindBarState();
}

class _FindBarState extends State<FindBar> {
  late final find = TextEditingController(text: widget.state.query);
  late final replace = TextEditingController(text: widget.state.replacement);

  @override
  void dispose() {
    find.dispose();
    replace.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final state = widget.state;
    Widget input(
      TextEditingController c,
      String hint,
      ValueChanged<String> onChanged,
      VoidCallback onSubmit, {
      FocusNode? focus,
      IconData? icon,
    }) => Expanded(
      child: Container(
        height: 30,
        decoration: BoxDecoration(
          color: t.sidebar,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: t.hairline),
        ),
        child: Row(
          children: [
            const SizedBox(width: 9),
            Icon(icon, size: 14, color: t.faint),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                controller: c,
                focusNode: focus,
                onChanged: onChanged,
                onSubmitted: (_) {
                  onSubmit();
                  (focus ?? FocusScope.of(context).focusedChild)
                      ?.requestFocus();
                },
                style: TextStyle(fontSize: 13, color: t.text),
                decoration: InputDecoration.collapsed(
                  hintText: hint,
                  hintStyle: TextStyle(fontSize: 13, color: t.faint),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    Widget action(String label, VoidCallback onTap) => HoverButton(
      onPressed: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          color: t.accent,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): state.toggleFind,
      },
      child: Container(
        height: 44,
        padding: EdgeInsets.fromLTRB(widget.gutter - 4, 2, 18, 8),
        child: Row(
          children: [
            input(
              find,
              'Find',
              state.setQuery,
              state.findNext,
              focus: state.findFocus,
              icon: CupertinoIcons.search,
            ),
            const SizedBox(width: 8),
            input(
              replace,
              'Replace with',
              state.setReplacement,
              state.replace,
              icon: CupertinoIcons.arrow_2_squarepath,
            ),
            const SizedBox(width: 6),
            action('Next', state.findNext),
            action('Replace', state.replace),
            action('All', state.replaceAll),
            HoverButton(
              tooltip: 'Close · ${shortcutLabel('F')}',
              onPressed: state.toggleFind,
              child: Icon(CupertinoIcons.xmark, size: 13, color: t.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      constraints: const BoxConstraints(maxWidth: 560),
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.hairline),
        boxShadow: const [
          BoxShadow(
            blurRadius: 18,
            offset: Offset(0, 4),
            color: Color(0x22000000),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              state.notice!,
              style: TextStyle(fontSize: 13, color: t.text),
            ),
          ),
          const SizedBox(width: 10),
          HoverButton(
            onPressed: state.dismissNotice,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Text(
              'Dismiss',
              style: TextStyle(
                fontSize: 13,
                color: t.accent,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Modal extends StatelessWidget {
  const _Modal({required this.child, this.onDismiss});
  final Widget child;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Positioned.fill(
      child: GestureDetector(
        onTap: onDismiss,
        child: ColoredBox(
          color: t.scrim,
          child: Center(
            child: GestureDetector(
              onTap: () {},
              child: Container(
                decoration: BoxDecoration(
                  color: t.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: t.hairline),
                  boxShadow: const [
                    BoxShadow(
                      blurRadius: 40,
                      offset: Offset(0, 12),
                      color: Color(0x33000000),
                    ),
                  ],
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Button extends StatelessWidget {
  const _Button(
    this.label,
    this.onPressed, {
    this.primary = false,
    this.autofocus = false,
  });
  final String label;
  final VoidCallback onPressed;
  final bool primary, autofocus;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return TextButton(
      autofocus: autofocus,
      onPressed: onPressed,
      style: TextButton.styleFrom(
        backgroundColor: primary ? t.accent : t.chip.withValues(alpha: 0.6),
        foregroundColor: primary ? Colors.white : t.text,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        minimumSize: const Size(84, 34),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      child: Text(label),
    );
  }
}

class _ConfirmCard extends StatelessWidget {
  const _ConfirmCard({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final doc = state.documents[state.confirm]!;
    return SizedBox(
      width: 400,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Save changes to ${doc.name}?',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: t.text,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your unsaved changes will be lost if you discard them.',
              style: TextStyle(fontSize: 13, color: t.muted, height: 1.4),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                _Button('Discard', state.discard),
                const Spacer(),
                _Button('Cancel', state.cancel),
                const SizedBox(width: 8),
                _Button(
                  state.saving != null ? 'Saving…' : 'Save',
                  state.saveAndClose,
                  primary: true,
                  autofocus: true,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class SettingsCard extends StatelessWidget {
  const SettingsCard({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final s = state.settings;
    Widget label(String text) => SizedBox(
      width: 110,
      child: Text(text, style: TextStyle(fontSize: 13, color: t.muted)),
    );
    Widget row(String name, Widget control) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          label(name),
          Expanded(child: control),
        ],
      ),
    );
    Widget segments<T extends Enum>(
      List<T> values,
      T selected,
      void Function(T) onSelect,
    ) => Wrap(
      spacing: 4,
      children: [
        for (final v in values)
          PillChip(
            label: v.name[0].toUpperCase() + v.name.substring(1),
            selected: v == selected,
            onTap: () => state.updateSettings((_) => onSelect(v)),
          ),
      ],
    );
    Widget slider(
      double value,
      double min,
      double max,
      int divisions,
      String text,
      void Function(double) onChanged,
    ) => Row(
      children: [
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              activeTrackColor: t.accent,
              inactiveTrackColor: t.chip,
              thumbColor: t.card,
              overlayShape: SliderComponentShape.noOverlay,
              thumbShape: const RoundSliderThumbShape(
                enabledThumbRadius: 8,
                elevation: 2,
              ),
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: (v) => state.updateSettings((_) => onChanged(v)),
            ),
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            text,
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 13, color: t.text),
          ),
        ),
      ],
    );
    Widget toggle(bool value, void Function(bool) onChanged) => Align(
      alignment: Alignment.centerLeft,
      child: Transform.scale(
        scale: 0.75,
        alignment: Alignment.centerLeft,
        child: CupertinoSwitch(
          value: value,
          activeTrackColor: t.accent,
          onChanged: (v) => state.updateSettings((_) => onChanged(v)),
        ),
      ),
    );

    return SizedBox(
      width: 440,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  'Settings',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: t.text,
                  ),
                ),
                const Spacer(),
                _Button('Done', state.toggleSettings, primary: true),
              ],
            ),
            const SizedBox(height: 14),
            row(
              'Theme',
              segments(
                Appearance.values,
                s.appearance,
                (v) => s.appearance = v,
              ),
            ),
            row('Font', segments(Typeface.values, s.font, (v) => s.font = v)),
            row(
              'Size',
              slider(
                s.size,
                Settings.minSize,
                Settings.maxSize,
                30,
                s.size.toStringAsFixed(0),
                (v) => s.size = v,
              ),
            ),
            row(
              'Line height',
              slider(
                s.lineHeight,
                Settings.minLineHeight,
                Settings.maxLineHeight,
                14,
                s.lineHeight.toStringAsFixed(1),
                (v) => s.lineHeight = v,
              ),
            ),
            row('Word wrap', toggle(s.wrap, (v) => s.wrap = v)),
            row('Status line', toggle(s.status, (v) => s.status = v)),
            const SizedBox(height: 10),
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: Image.asset(
                    state.dark
                        ? 'assets/branding/logo-dark.png'
                        : 'assets/branding/logo-light.png',
                    width: 22,
                    height: 22,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'writestuff. just a place to write stuff.',
                  style: TextStyle(fontSize: 11, color: t.faint),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
