import 'package:prosemirror/prosemirror.dart';
import 'package:test/test.dart';

import '../model/support/builders.dart';

void main() {
  group("simplifyChanges >", () {
    test("doesn't change insertion-only changes", () {
      _test(
        [
          [1, 1, 1, 2],
          [2, 2, 3, 4],
        ],
        doc(p("hello")),
        [
          [1, 1, 1, 2],
          [2, 2, 3, 4],
        ],
      );
    });

    test("doesn't change deletion-only changes", () {
      _test(
        [
          [1, 2, 1, 1],
          [3, 4, 2, 2],
        ],
        doc(p("hello")),
        [
          [1, 2, 1, 1],
          [3, 4, 2, 2],
        ],
      );
    });

    test("doesn't change single-letter-replacements", () {
      _test(
        [
          [1, 2, 1, 2],
        ],
        doc(p("hello")),
        [
          [1, 2, 1, 2],
        ],
      );
    });

    test("does expand multiple-letter replacements", () {
      _test(
        [
          [2, 4, 2, 4],
        ],
        doc(p("hello")),
        [
          [1, 6, 1, 6],
        ],
      );
    });

    test("does combine changes within the same word", () {
      _test(
        [
          [1, 3, 1, 1],
          [5, 5, 3, 4],
        ],
        doc(p("hello")),
        [
          [1, 7, 1, 6],
        ],
      );
    });

    test("expands changes to cover full words", () {
      _test(
        [
          [7, 10],
        ],
        doc(p("one two three four")),
        [
          [5, 14],
        ],
      );
    });

    test("doesn't expand across non-word text", () {
      _test(
        [
          [7, 10],
        ],
        doc(p("one two ----- four")),
        [
          [5, 10],
        ],
      );
    });

    test("doesn't expand replacements across bracket characters", () {
      _test(
        [
          [7, 10],
        ],
        doc(p("one two [SFX] four")),
        [
          [5, 10],
        ],
      );
    });

    test("treats leaf nodes as non-words", () {
      _test(
        [
          [2, 3],
          [6, 7],
        ],
        doc(p("one", img(), "two")),
        [
          [2, 3],
          [6, 7],
        ],
      );
    });

    test("treats node boundaries as non-words", () {
      _test(
        [
          [2, 3],
          [7, 8],
        ],
        doc(p("one"), p("two")),
        [
          [2, 3],
          [7, 8],
        ],
      );
    });

    test("can merge stretches of changes", () {
      _test(
        [
          [2, 3],
          [4, 6],
          [8, 10],
          [15, 16],
        ],
        doc(p("foo bar baz bug ugh")),
        [
          [1, 12],
          [15, 16],
        ],
      );
    });

    test("handles realistic word updates", () {
      _test(
        [
          [8, 8, 8, 11],
          [10, 15, 13, 17],
        ],
        doc(p("chonic condition")),
        [
          [8, 15, 8, 17],
        ],
      );
    });

    test("works when after significant content", () {
      _test(
        [
          [63, 80, 63, 83],
        ],
        doc(
          p("one long paragraph -----"),
          p("two long paragraphs ------"),
          p("a vote against the government"),
        ),
        [
          [62, 81, 62, 84],
        ],
      );
    });

    test("joins changes that grow together when simplifying", () {
      _test(
        [
          [1, 5, 1, 5],
          [7, 13, 7, 9],
          [20, 21, 16, 16],
        ],
        doc(p("and his co-star")),
        [
          [1, 13, 1, 9],
          [20, 21, 16, 16],
        ],
      );
    });

    test("properly fills in metadata", () {
      final simple = simplifyChanges([
        _range([2, 3], 0),
        _range([4, 6], 1),
        _range([8, 9, 8, 8], 2),
      ], doc(p("1234567890")));
      expect(simple.length, 1);
      expect(
        [
          for (final span in simple[0].deleted) [span.length, span.data],
        ],
        [
          [3, 0],
          [4, 1],
          [4, 2],
        ],
      );
      expect(
        [
          for (final span in simple[0].inserted) [span.length, span.data],
        ],
        [
          [3, 0],
          [4, 1],
          [3, 2],
        ],
      );
    });
  });
}

void _test(List<List<int>> changes, Node document, List<List<int>> result) {
  final ranges = changes.map(_range).toList();
  final simplified = simplifyChanges(ranges, document);
  final actual = <List<int>>[];
  for (var index = 0; index < simplified.length; index++) {
    final change = simplified[index];
    if (index < result.length && result[index].length > 2) {
      actual.add([change.fromA, change.toA, change.fromB, change.toB]);
    } else {
      actual.add([change.fromB, change.toB]);
    }
  }
  expect(actual, result);
}

Change<int> _range(List<int> array, [int author = 0]) {
  final fromA = array[0];
  final toA = array[1];
  final fromB = array.length > 2 ? array[2] : array[0];
  final toB = array.length > 2 ? array[3] : array[1];
  return Change<int>(
    fromA,
    toA,
    fromB,
    toB,
    [Span<int>(toA - fromA, author)],
    [Span<int>(toB - fromB, author)],
  );
}
