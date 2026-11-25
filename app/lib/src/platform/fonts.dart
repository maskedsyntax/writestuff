import 'dart:io';

import 'package:flutter/services.dart';

const _channel = MethodChannel('writestuff/fonts');

List<String>? _cache;

/// Font families installed on this computer, sorted by name.
Future<List<String>> systemFontFamilies() async {
  if (_cache != null) return _cache!;
  final names = <String>{};
  try {
    if (Platform.isMacOS) {
      final list = await _channel.invokeListMethod<String>('families');
      names.addAll(list ?? const []);
    } else if (Platform.isLinux) {
      final r = await Process.run('fc-list', [':', 'family']);
      for (final line in (r.stdout as String).split('\n')) {
        // "DejaVu Sans,DejaVu Sans Light": the first name is the family.
        final name = line.split(',').first.trim();
        if (name.isNotEmpty) names.add(name.replaceAll(r'\-', '-'));
      }
    } else if (Platform.isWindows) {
      for (final hive in ['HKLM', 'HKCU']) {
        final r = await Process.run('reg', [
          'query',
          '$hive\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Fonts',
        ]);
        names.addAll(windowsFamilies(r.stdout as String));
      }
    }
  } catch (_) {
    // No list available: the picker shows only the built-in choices.
  }
  names.removeWhere((n) => n.startsWith('.') || n.startsWith('#'));
  return _cache = names.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
}

final _styleWords = RegExp(
  r'\s+(Bold|Italic|Oblique|Light|Thin|Medium|Black|Heavy|Semibold|SemiBold|'
  r'Demibold|ExtraBold|ExtraLight|UltraLight|Regular|Condensed|Narrow)\b.*$',
);

/// Family names from `reg query` output of the Windows Fonts key, e.g.
/// `Segoe UI Bold (TrueType)    REG_SZ    segoeuib.ttf` → `Segoe UI`.
Iterable<String> windowsFamilies(String output) sync* {
  for (final line in output.split('\n')) {
    final m = RegExp(r'^\s+(.+?)\s+REG_SZ\s').firstMatch(line);
    if (m == null) continue;
    var name = m[1]!.replaceAll(RegExp(r'\s*\(.*\)$'), '');
    // "Cambria & Cambria Math" lists two families in one file.
    for (var part in name.split(' & ')) {
      part = part.replaceAll(_styleWords, '').trim();
      if (part.isNotEmpty) yield part;
    }
  }
}
