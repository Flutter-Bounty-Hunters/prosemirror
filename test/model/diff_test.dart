import 'package:prosemirror/prosemirror.dart';
import 'package:test/test.dart';

import 'support/builders.dart';

void main() {
  group("Fragment > findDiffStart >", () {
    test("returns null for identical nodes", () {
      _start(
        doc(p("a", em("b")), p("hello"), blockquote(h1("bye"))),
        doc(p("a", em("b")), p("hello"), blockquote(h1("bye"))),
      );
    });

    test("notices when one node is longer", () {
      _start(
        doc(p("a", em("b")), p("hello"), blockquote(h1("bye")), "<a>"),
        doc(p("a", em("b")), p("hello"), blockquote(h1("bye")), p("oops")),
      );
    });

    test("notices when one node is shorter", () {
      _start(
        doc(
          p("a", em("b")),
          p("hello"),
          blockquote(h1("bye")),
          "<a>",
          p("oops"),
        ),
        doc(p("a", em("b")), p("hello"), blockquote(h1("bye"))),
      );
    });

    test("notices differing marks", () {
      _start(doc(p("a<a>", em("b"))), doc(p("a", strong("b"))));
    });

    test("stops at longer text", () {
      _start(doc(p("foo<a>bar", em("b"))), doc(p("foo", em("b"))));
    });

    test("stops at a different character", () {
      _start(doc(p("foo<a>bar")), doc(p("foocar")));
    });

    test("stops at a different node type", () {
      _start(doc(p("a"), "<a>", p("b")), doc(p("a"), h1("b")));
    });

    test("works when the difference is at the start", () {
      _start(doc("<a>", p("b")), doc(h1("b")));
    });

    test("notices a different attribute", () {
      _start(doc(p("a"), "<a>", h1("foo")), doc(p("a"), h2("foo")));
    });
  });

  group("Fragment > findDiffEnd >", () {
    test("returns null when there is no difference", () {
      _end(
        doc(p("a", em("b")), p("hello"), blockquote(h1("bye"))),
        doc(p("a", em("b")), p("hello"), blockquote(h1("bye"))),
      );
    });

    test("notices when the second doc is longer", () {
      _end(
        doc("<a>", p("a", em("b")), p("hello"), blockquote(h1("bye"))),
        doc(p("oops"), p("a", em("b")), p("hello"), blockquote(h1("bye"))),
      );
    });

    test("notices when the second doc is shorter", () {
      _end(
        doc(
          p("oops"),
          "<a>",
          p("a", em("b")),
          p("hello"),
          blockquote(h1("bye")),
        ),
        doc(p("a", em("b")), p("hello"), blockquote(h1("bye"))),
      );
    });

    test("notices different styles", () {
      _end(doc(p("a", em("b"), "<a>c")), doc(p("a", strong("b"), "c")));
    });

    test("spots longer text", () {
      _end(doc(p("bar<a>foo", em("b"))), doc(p("foo", em("b"))));
    });

    test("spots different text", () {
      _end(doc(p("foob<a>ar")), doc(p("foocar")));
    });

    test("notices different nodes", () {
      _end(doc(p("a"), "<a>", p("b")), doc(h1("a"), p("b")));
    });

    test("notices a difference at the end", () {
      _end(doc(p("b"), "<a>"), doc(h1("b")));
    });

    test("handles a similar start", () {
      _end(doc("<a>", p("hello")), doc(p("hey"), p("hello")));
    });
  });
}

void _start(Node a, Node b) {
  expect(a.content.findDiffStart(b.content), a.tag["a"]);
}

void _end(Node a, Node b) {
  final found = a.content.findDiffEnd(b.content);
  expect(found?.a, a.tag["a"]);
}
