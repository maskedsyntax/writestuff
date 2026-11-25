import 'package:flutter_test/flutter_test.dart';
import 'package:writestuff/src/model/inline.dart';
import 'package:writestuff/src/model/lists.dart';

import 'lists_test.dart' show v, show;

void main() {
  group('wrap', () {
    test('wraps and unwraps a selection', () {
      final bold = toggleWrap(v('a [word] b'), '**');
      expect(show(bold), 'a **[word]** b');
      expect(show(toggleWrap(bold, '**')), 'a [word] b');
    });

    test('unwraps when the markers are selected too', () {
      expect(show(toggleWrap(v('[**word**]'), '**')), '[word]');
    });

    test('wraps the word at the caret', () {
      expect(show(toggleWrap(v('one tw|o'), '_')), 'one _tw|o_');
      expect(show(toggleWrap(v('one _tw|o_'), '_')), 'one tw|o');
    });

    test('inserts a pair with nothing to wrap', () {
      expect(show(toggleWrap(v('a |'), '**')), 'a **|**');
    });

    test('trims whitespace from the selection', () {
      expect(show(toggleWrap(v('[word ]x'), '**')), '**[word]** x');
    });

    test('single marker does not unwrap bold', () {
      expect(show(toggleWrap(v('**[b]**'), '*')), '***[b]***');
    });
  });

  test('link selects the url placeholder', () {
    expect(show(insertLink(v('see [docs]'))), 'see [docs]([url])');
    expect(show(insertLink(v('|'))), '[[text]](url)');
  });

  test('heading cycles levels', () {
    var value = v('Ti|tle');
    final seen = <String>[];
    for (var i = 0; i < 4; i++) {
      value = cycleHeading(value);
      seen.add(show(value));
    }
    expect(seen, ['# Ti|tle', '## Ti|tle', '### Ti|tle', 'Ti|tle']);
  });

  test('checklist toggles on and off', () {
    final on = toggleList(v('[a\nb]'), ordered: false, task: true);
    expect(on.text, '- [ ] a\n- [ ] b');
    expect(toggleList(on, ordered: false, task: true).text, 'a\nb');
    expect(
      toggleList(v('[- a\n- b]'), ordered: false, task: true).text,
      '- [ ] a\n- [ ] b',
    );
  });
}
