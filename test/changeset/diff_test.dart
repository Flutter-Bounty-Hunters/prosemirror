import 'package:prosemirror/prosemirror.dart';
import 'package:test/test.dart';

import 'package:prosemirror/test_builder.dart';

void main() {
  group("computeDiff >", () {
    test("returns an empty diff for identical documents", () {
      _test(document(p("foo"), p("bar")), document(p("foo"), p("bar")));
    });

    test("finds single-letter changes", () {
      _test(document(p("foo"), p("bar")), document(p("foa"), p("bar")), [
        [3, 4, 3, 4],
      ]);
    });

    test("finds simple structure changes", () {
      _test(document(p("foo"), p("bar")), document(p("foobar")), [
        [4, 6, 4, 4],
      ]);
    });

    test("finds multiple changes", () {
      _test(document(p("foo"), p("---bar")), document(p("fgo"), p("---bur")), [
        [2, 4, 2, 4],
        [10, 11, 10, 11],
      ]);
    });

    test("ignores single-letter unchanged parts", () {
      _test(document(p("abcdef")), document(p("axydzf")), [
        [2, 6, 2, 6],
      ]);
    });

    test("ignores matching substrings in longer diffs", () {
      _test(
        document(p("One two three")),
        document(p("One"), p("And another long paragraph that has wo and ee in it")),
        [
          [4, 14, 4, 57],
        ],
      );
    });

    test("finds deletions", () {
      _test(document(p("abc"), p("def")), document(p("ac"), p("d")), [
        [2, 3, 2, 2],
        [7, 9, 6, 6],
      ]);
    });

    test("ignores marks", () {
      _test(document(p("abc")), document(p(em("a"), strong("bc"))));
    });

    test("ignores marks in diffing", () {
      _test(document(p("abcdefghi")), document(p(em("x"), strong("bc"), "defgh", em("y"))), [
        [1, 2, 1, 2],
        [9, 10, 9, 10],
      ]);
    });

    test("ignores attributes", () {
      _test(document(h1("x")), document(h2("x")));
    });

    test("finds huge deletions", () {
      final xs = "x" * 200;
      final bs = "b" * 20;
      _test(document(p("a${bs}c")), document(p("a$xs$bs${xs}c")), [
        [2, 2, 2, 202],
        [22, 22, 222, 422],
      ]);
    });

    test("finds huge insertions", () {
      final xs = "x" * 200;
      final bs = "b" * 20;
      _test(document(p("a$xs$bs${xs}c")), document(p("a${bs}c")), [
        [2, 202, 2, 2],
        [222, 422, 22, 22],
      ]);
    });

    test("can handle ambiguous diffs", () {
      _test(document(p("abcbcd")), document(p("abcd")), [
        [4, 6, 4, 4],
      ]);
    });

    test("sees the difference between different closing tokens", () {
      _test(document(p("a")), document(h1("oo")), [
        [0, 3, 0, 4],
      ]);
    });
  });
}

void _test(Node document1, Node document2, [List<List<int>> ranges = const []]) {
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
  final actual = diff.map((change) => [change.fromA, change.toA, change.fromB, change.toB]).toList();
  expect(actual, ranges);
}
