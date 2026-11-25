import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'atomic_file.dart';

enum Appearance { system, light, dark }

enum Typeface { monospace, sans, serif }

String _label(Enum e) => e.name[0].toUpperCase() + e.name.substring(1);

T _parse<T extends Enum>(List<T> values, Object? raw, T fallback) =>
    values.firstWhere((v) => _label(v) == raw, orElse: () => fallback);

/// User preferences. The JSON shape matches the Rust app's `session.json`.
class Settings {
  Settings({
    this.appearance = Appearance.system,
    this.font = Typeface.monospace,
    this.size = 16,
    this.lineHeight = 1.6,
    this.wrap = true,
    this.status = true,
  });

  Appearance appearance;
  Typeface font;
  double size;
  double lineHeight;
  bool wrap;
  bool status;

  static const minSize = 10.0, maxSize = 40.0;
  static const minLineHeight = 1.0, maxLineHeight = 2.4;

  factory Settings.fromJson(Map<String, dynamic> j) => Settings(
    appearance: _parse(Appearance.values, j['appearance'], Appearance.system),
    font: _parse(Typeface.values, j['font'], Typeface.monospace),
    size: ((j['size'] as num?)?.toDouble() ?? 16)
        .clamp(minSize, maxSize)
        .toDouble(),
    lineHeight: ((j['line_height'] as num?)?.toDouble() ?? 1.6)
        .clamp(minLineHeight, maxLineHeight)
        .toDouble(),
    wrap: j['wrap'] as bool? ?? true,
    status: j['status'] as bool? ?? true,
  );

  Map<String, dynamic> toJson() => {
    'appearance': _label(appearance),
    'font': _label(font),
    'size': size,
    'line_height': lineHeight,
    'wrap': wrap,
    'status': status,
  };
}

class Snapshot {
  Snapshot({
    required this.id,
    this.path,
    required this.text,
    required this.saved,
  });
  final int id;
  final String? path;
  final String text;
  final String saved;

  factory Snapshot.fromJson(Map<String, dynamic> j) => Snapshot(
    id: j['id'] as int,
    path: j['path'] as String?,
    text: j['text'] as String,
    saved: j['saved'] as String,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'path': path,
    'text': text,
    'saved': saved,
  };
}

class Session {
  Session({Settings? settings, List<Snapshot>? documents, this.active})
    : settings = settings ?? Settings(),
      documents = documents ?? [];
  final Settings settings;
  final List<Snapshot> documents;
  final int? active;

  factory Session.fromJson(Map<String, dynamic> j) => Session(
    settings: Settings.fromJson(
      (j['settings'] as Map?)?.cast<String, dynamic>() ?? const {},
    ),
    documents: ((j['documents'] as List?) ?? const [])
        .map((d) => Snapshot.fromJson((d as Map).cast<String, dynamic>()))
        .toList(),
    active: j['active'] as int?,
  );

  Map<String, dynamic> toJson() => {
    'settings': settings.toJson(),
    'documents': documents.map((d) => d.toJson()).toList(),
    'active': active,
  };

  static Session decode(String source) =>
      Session.fromJson((jsonDecode(source) as Map).cast<String, dynamic>());
}

/// The same directory the Rust app used, so existing recovery data carries over.
String configDirectory() {
  final env = Platform.environment;
  final override = env['WRITESTUFF_CONFIG_DIR'];
  if (override != null && override.isNotEmpty) return override;
  final home = env['HOME'] ?? '';
  if (Platform.isMacOS) {
    return p.join(home, 'Library', 'Application Support', 'writestuff');
  }
  if (Platform.isWindows) {
    return p.join(env['APPDATA'] ?? '', 'writestuff', 'config');
  }
  final xdg = env['XDG_CONFIG_HOME'];
  return p.join(
    xdg != null && xdg.isNotEmpty ? xdg : p.join(home, '.config'),
    'writestuff',
  );
}

String sessionPath() => p.join(configDirectory(), 'session.json');

class LoadResult {
  LoadResult(this.session, this.notice);
  final Session session;
  final String? notice;
}

Future<LoadResult> loadSession([String? path]) async {
  path ??= sessionPath();
  final file = File(path);
  if (!await file.exists()) return LoadResult(Session(), null);
  String source;
  try {
    source = await file.readAsString();
  } catch (e) {
    return LoadResult(Session(), 'Could not read session: ${describeError(e)}');
  }
  try {
    return LoadResult(Session.decode(source), null);
  } catch (error) {
    try {
      final backup = Session.decode(await File('$path.bak').readAsString());
      return LoadResult(
        backup,
        'Recovery snapshot was damaged ($error); restored the previous backup.',
      );
    } catch (_) {
      return LoadResult(
        Session(),
        'Could not restore session: $error. Damaged snapshots are preserved with a .damaged extension on the next recovery write.',
      );
    }
  }
}

Future<void> saveSession(Session session, [String? path]) async {
  path ??= sessionPath();
  await Directory(p.dirname(path)).create(recursive: true);
  final current = File(path);
  if (await current.exists()) {
    final previous = await current.readAsString().then<String?>(
      (s) => s,
      onError: (_) => null,
    );
    var valid = false;
    if (previous != null) {
      try {
        Session.decode(previous);
        valid = true;
      } catch (_) {}
    }
    if (valid) {
      // Keep the previous valid snapshot as a second line of defense.
      await writeText('$path.bak', previous!);
    } else {
      // Preserve corrupt input as evidence without replacing a valid backup.
      final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
      await current.copy(p.join(p.dirname(path), 'session-$stamp.damaged'));
    }
  }
  await writeText(path, jsonEncode(session.toJson()));
}

/// Held for the app lifetime so two instances cannot overwrite recovery.
Future<RandomAccessFile> lockSession() async {
  final dir = configDirectory();
  await Directory(dir).create(recursive: true);
  final file = await File(
    p.join(dir, 'session.lock'),
  ).open(mode: FileMode.append);
  try {
    await file.lock(FileLock.exclusive);
  } on FileSystemException catch (e) {
    await file.close();
    throw StateError(
      'Cannot lock the recovery session; writestuff may already be running: ${describeError(e)}',
    );
  }
  return file;
}
