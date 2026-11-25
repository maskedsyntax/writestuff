import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

/// Reads a UTF-8 text file, returning its canonical path and exact contents.
Future<(String, String)> readText(String path) async {
  final canonical = await File(path).resolveSymbolicLinks();
  final bytes = await File(canonical).readAsBytes();
  try {
    return (canonical, utf8.decode(bytes));
  } on FormatException {
    throw const FileSystemException('The file is not valid UTF-8 text.');
  }
}

/// Canonicalizes [path] when it exists, otherwise its parent directory.
String canonicalize(String path) {
  try {
    return File(path).resolveSymbolicLinksSync();
  } on FileSystemException {
    try {
      final parent = Directory(p.dirname(path)).resolveSymbolicLinksSync();
      return p.join(parent, p.basename(path));
    } on FileSystemException {
      return p.absolute(path);
    }
  }
}

/// Writes beside the destination and atomically replaces it, preserving the
/// permissions of an existing file. When [expected] is given, the file on disk
/// must still match it, so external changes are never overwritten.
Future<void> writeText(String path, String text, {String? expected}) async {
  final target = File(path);
  if (expected != null) {
    String disk;
    try {
      disk = utf8.decode(await target.readAsBytes());
    } catch (e) {
      throw FileSystemException(
        'Cannot verify original file: ${_describe(e)}. Use Save as.',
      );
    }
    if (disk != expected) {
      throw const FileSystemException(
        'The file changed on disk. Use Save as to preserve both versions.',
      );
    }
  }
  final directory = p.dirname(path).isEmpty ? '.' : p.dirname(path);
  final temp = File(
    p.join(
      directory,
      '.${p.basename(path)}.${pid}_${Random().nextInt(1 << 32).toRadixString(36)}.tmp',
    ),
  );
  try {
    final handle = await temp.open(mode: FileMode.writeOnly);
    try {
      await handle.writeFrom(utf8.encode(text));
      await handle.flush(); // fsync
    } finally {
      await handle.close();
    }
    if (!Platform.isWindows && await target.exists()) {
      final mode = (await target.stat()).mode & 0x1ff;
      await Process.run('chmod', [mode.toRadixString(8), temp.path]);
    }
    await temp.rename(path);
  } catch (e) {
    if (await temp.exists()) await temp.delete();
    rethrow;
  }
}

String _describe(Object e) =>
    e is FileSystemException ? (e.osError?.message ?? e.message) : '$e';

String describeError(Object e) => _describe(e);
