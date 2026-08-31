import 'package:prosemirror/prosemirror.dart';
import 'package:test/test.dart';

import '../model/support/builders.dart';

void main() {
  group("computeDiff >", () {
    test("returns an empty diff for identical documents", () {
      _test(doc(p("foo"), p("bar")), doc(p("foo"), p("bar")));
    });

    test("finds single-letter changes", () {
      _test(doc(p("foo"), p("bar")), doc(p("foa"), p("bar")), [
        [3, 4, 3, 4],
      ]);
    });

    test("finds simple structure changes", () {
      _test(doc(p("foo"), p("bar")), doc(p("foobar")), [
        [4, 6, 4, 4],
      ]);
    });

    test("finds multiple changes", () {
      _test(doc(p("foo"), p("---bar")), doc(p("fgo"), p("---bur")), [
        [2, 4, 2, 4],
        [10, 11, 10, 11],
      ]);
    });

    test("ignores single-letter unchanged parts", () {
      _test(doc(p("abcdef")), doc(p("axydzf")), [
        [2, 6, 2, 6],
      ]);
    });

    test("ignores matching substrings in longer diffs", () {
      _test(
        doc(p("One two three")),
        doc(p("One"), p("And another long paragraph that has wo and ee in it")),
        [
          [4, 14, 4, 57],
        ],
      );
    });

    test("finds deletions", () {
      _test(doc(p("abc"), p("def")), doc(p("ac"), p("d")), [
        [2, 3, 2, 2],
        [7, 9, 6, 6],
      ]);
    });

    test("ignores marks", () {
      _test(doc(p("abc")), doc(p(em("a"), strong("bc"))));
    });

    test("ignores marks in diffing", () {
      _test(
        doc(p("abcdefghi")),
        doc(p(em("x"), strong("bc"), "defgh", em("y"))),
        [
          [1, 2, 1, 2],
          [9, 10, 9, 10],
        ],
      );
    });

    test("ignores attributes", () {
      _test(doc(h1("x")), doc(h2("x")));
    });

    test("finds huge deletions", () {
      final xs = "x" * 200;
      final bs = "b" * 20;
      _test(doc(p("a${bs}c")), doc(p("a$xs$bs${xs}c")), [
        [2, 2, 2, 202],
        [22, 22, 222, 422],
      ]);
    });

    test("finds huge insertions", () {
      final xs = "x" * 200;
      final bs = "b" * 20;
      _test(doc(p("a$xs$bs${xs}c")), doc(p("a${bs}c")), [
        [2, 202, 2, 2],
        [222, 422, 22, 22],
      ]);
    });

    test("can handle ambiguous diffs", () {
      _test(doc(p("abcbcd")), doc(p("abcd")), [
        [4, 6, 4, 4],
      ]);
    });

    test("sees the difference between different closing tokens", () {
      _test(doc(p("a")), doc(h1("oo")), [
        [0, 3, 0, 4],
      ]);
    });
  });
}

void _test(
  Node document1,
  Node document2, [
  List<List<int>> ranges = const [],
]) {
  final diff = computeDiff(
    document1.content,
    document2.content,
    Change(
      0,
      document1.content.size,
      0,
      document2.content.size,
      [Span(document1.content.size, 0)],
      [Span(document2.content.size, 0)],
    ),
  );
  final actual = diff
      .map((change) => [change.fromA, change.toA, change.fromB, change.toB])
      .toList();
  expect(actual, ranges);
}
