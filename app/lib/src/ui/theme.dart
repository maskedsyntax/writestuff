import 'dart:io';

import 'package:flutter/material.dart';

import '../storage/session.dart';
import 'editor_controller.dart';

/// Design tokens for the calm, airy sidebar-and-canvas look.
@immutable
class Tokens extends ThemeExtension<Tokens> {
  const Tokens({
    required this.canvas,
    required this.sidebar,
    required this.selection,
    required this.hover,
    required this.text,
    required this.muted,
    required this.faint,
    required this.hairline,
    required this.accent,
    required this.badge,
    required this.chip,
    required this.code,
    required this.codeBackground,
    required this.match,
    required this.scrim,
    required this.card,
  });

  final Color canvas, sidebar, selection, hover, text, muted, faint, hairline;
  final Color accent, badge, chip, code, codeBackground, match, scrim, card;

  static const light = Tokens(
    canvas: Color(0xFFFFFFFF),
    sidebar: Color(0xFFF5F5F6),
    selection: Color(0xFFE3E3E6),
    hover: Color(0xFFEBEBED),
    text: Color(0xFF1F1F21),
    muted: Color(0xFF8A8A8E),
    faint: Color(0xFFB9B9BD),
    hairline: Color(0xFFE6E6E8),
    accent: Color(0xFF2F6FDB),
    badge: Color(0xFFEE4B57),
    chip: Color(0xFFDADADD),
    code: Color(0xFF7A4BA8),
    codeBackground: Color(0x0F000000),
    match: Color(0x40FFC43D),
    scrim: Color(0x33000000),
    card: Color(0xFFFFFFFF),
  );

  static const dark = Tokens(
    canvas: Color(0xFF1E1E20),
    sidebar: Color(0xFF262628),
    selection: Color(0xFF3A3A3D),
    hover: Color(0xFF313134),
    text: Color(0xFFE8E8EA),
    muted: Color(0xFF98989D),
    faint: Color(0xFF636366),
    hairline: Color(0xFF353538),
    accent: Color(0xFF5B9BF5),
    badge: Color(0xFFEE4B57),
    chip: Color(0xFF48484B),
    code: Color(0xFFC79BF2),
    codeBackground: Color(0x14FFFFFF),
    match: Color(0x55D9A520),
    scrim: Color(0x66000000),
    card: Color(0xFF2C2C2E),
  );

  HighlightPalette get highlight => HighlightPalette(
    accent: accent,
    muted: muted,
    code: code,
    codeBackground: codeBackground,
    match: match,
    currentMatch: currentMatch,
  );

  Color get currentMatch => match.withValues(alpha: 0.9);

  @override
  Tokens copyWith() => this;

  @override
  Tokens lerp(Tokens? other, double t) => t < 0.5 ? this : (other ?? this);
}

extension TokensX on BuildContext {
  Tokens get tokens => Theme.of(this).extension<Tokens>()!;
}

ThemeData buildTheme(bool dark) {
  final t = dark ? Tokens.dark : Tokens.light;
  final base = ThemeData(
    brightness: dark ? Brightness.dark : Brightness.light,
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: t.accent,
      brightness: dark ? Brightness.dark : Brightness.light,
      primary: t.accent,
      surface: t.canvas,
    ),
    scaffoldBackgroundColor: t.canvas,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: t.hover,
    visualDensity: VisualDensity.compact,
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: t.accent,
      selectionColor: t.accent.withValues(alpha: dark ? 0.38 : 0.22),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 500),
      textStyle: TextStyle(fontSize: 12, color: t.canvas),
      decoration: BoxDecoration(
        color: t.text.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(5),
      ),
    ),
    dividerColor: t.hairline,
    extensions: [t],
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: t.text, displayColor: t.text),
  );
}

const _monospace = [
  'SF Mono',
  'Menlo',
  'Consolas',
  'Cascadia Mono',
  'DejaVu Sans Mono',
  'Liberation Mono',
  'monospace',
];
const _serif = [
  'New York',
  'Iowan Old Style',
  'Georgia',
  'Cambria',
  'Times New Roman',
  'DejaVu Serif',
  'Liberation Serif',
  'serif',
];

/// The editor's text style for a typeface preference.
TextStyle editorStyle(Settings s, Color color) {
  final (String? family, List<String>? fallback) = switch (s.font) {
    Typeface.monospace => (
      Platform.isMacOS ? 'Menlo' : _monospace.first,
      _monospace,
    ),
    Typeface.serif => ('Georgia', _serif),
    Typeface.sans => (null, null),
  };
  return TextStyle(
    fontFamily: s.family ?? family,
    fontFamilyFallback: s.family == null ? fallback : [?family, ...?fallback],
    fontSize: s.size,
    height: s.lineHeight,
    color: color,
  );
}
