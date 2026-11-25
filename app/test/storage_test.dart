import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:writestuff/src/storage/atomic_file.dart';
import 'package:writestuff/src/storage/session.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('writestuff_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('atomic save rejects conflict and preserves exact text', () async {
    final path = p.join(dir.path, 'note.md');
    await writeText(path, 'hello\r\n世界');
    expect((await readText(path)).$2, 'hello\r\n世界');
    await expectLater(
      writeText(path, 'lost', expected: 'old'),
      throwsA(anything),
    );
    expect((await readText(path)).$2, 'hello\r\n世界');
    await writeText(path, 'new', expected: 'hello\r\n世界');
    expect((await readText(path)).$2, 'new');
  });

  test('atomic save preserves permissions', () async {
    if (Platform.isWindows) return;
    final path = p.join(dir.path, 'script.sh');
    File(path).writeAsStringSync('old');
    await Process.run('chmod', ['755', path]);
    await writeText(path, 'new', expected: 'old');
    expect(File(path).statSync().mode & 0x1ff, 0x1ed);
    expect(dir.listSync().length, 1, reason: 'no temp files left behind');
  });

  test('non-UTF-8 files are rejected', () async {
    final path = p.join(dir.path, 'binary.txt');
    File(path).writeAsBytesSync([0xff, 0xfe, 0x00]);
    await expectLater(readText(path), throwsA(isA<FileSystemException>()));
  });

  Session sample(String text, int id) => Session(
    documents: [Snapshot(id: id, path: null, text: text, saved: '')],
  );

  test('recovery keeps previous snapshot as backup', () async {
    final path = p.join(dir.path, 'session.json');
    await saveSession(sample('recover this 猫', 42), path);
    await saveSession(sample('new version', 42), path);
    final current = Session.decode(File(path).readAsStringSync());
    final previous = Session.decode(File('$path.bak').readAsStringSync());
    expect(current.documents.first.text, 'new version');
    expect(previous.documents.first.text, 'recover this 猫');
  });

  test(
    'damaged session falls back without destroying the valid backup',
    () async {
      final path = p.join(dir.path, 'session.json');
      await saveSession(sample('safe', 7), path);
      await saveSession(sample('safe', 7), path);
      File(path).writeAsStringSync('{broken');
      final loaded = await loadSession(path);
      expect(loaded.notice, isNotNull);
      expect(loaded.session.documents.first.text, 'safe');
      await saveSession(loaded.session, path);
      final backup = Session.decode(File('$path.bak').readAsStringSync());
      expect(backup.documents.first.text, 'safe');
      expect(dir.listSync().any((f) => f.path.endsWith('.damaged')), isTrue);
    },
  );

  test('reads the Rust app session format', () {
    const rust =
        '{"settings":{"appearance":"Dark","font":"Serif","size":99.0,'
        '"line_height":1.8,"wrap":false,"status":true},"documents":[{"id":3,'
        '"path":"/tmp/a.md","text":"x","saved":"y"}],"active":3}';
    final s = Session.decode(rust);
    expect(s.settings.appearance, Appearance.dark);
    expect(s.settings.font, Typeface.serif);
    expect(s.settings.size, 40, reason: 'clamped');
    expect(s.settings.wrap, isFalse);
    expect(s.documents.single.path, '/tmp/a.md');
    expect(s.active, 3);
    final round = jsonDecode(jsonEncode(s.toJson())) as Map;
    expect((round['settings'] as Map)['appearance'], 'Dark');
    expect((round['settings'] as Map)['line_height'], 1.8);
  });

  test('missing settings fields use defaults', () {
    final s = Session.decode('{"settings":{"size":12},"documents":[]}');
    expect(s.settings.size, 12);
    expect(s.settings.lineHeight, 1.6);
    expect(s.settings.appearance, Appearance.system);
  });
}
