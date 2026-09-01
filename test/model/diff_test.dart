import 'package:prosemirror/prosemirror.dart';
import 'package:test/test.dart';

import 'package:prosemirror/test_builder.dart';

void main() {
  group("Fragment > findDiffStart >", () {
    test("returns null for identical nodes", () {
      _start(
        document(p("a", em("b")), p("hello"), blockquote(h1("bye"))),
        document(p("a", em("b")), p("hello"), blockquote(h1("bye"))),
      );
    });

    test("notices when one node is longer", () {
      _start(
        document(p("a", em("b")), p("hello"), blockquote(h1("bye")), "<a>"),
        document(p("a", em("b")), p("hello"), blockquote(h1("bye")), p("oops")),
      );
    });

    test("notices when one node is shorter", () {
      _start(
        document(p("a", em("b")), p("hello"), blockquote(h1("bye")), "<a>", p("oops")),
        document(p("a", em("b")), p("hello"), blockquote(h1("bye"))),
      );
    });

    test("notices differing marks", () {
      _start(document(p("a<a>", em("b"))), document(p("a", strong("b"))));
    });

    test("stops at longer text", () {
      _start(document(p("foo<a>bar", em("b"))), document(p("foo", em("b"))));
    });

    test("stops at a different character", () {
      _start(document(p("foo<a>bar")), document(p("foocar")));
    });

    test("stops at a different node type", () {
      _start(document(p("a"), "<a>", p("b")), document(p("a"), h1("b")));
    });

    test("works when the difference is at the start", () {
      _start(document("<a>", p("b")), document(h1("b")));
    });

    test("notices a different attribute", () {
      _start(document(p("a"), "<a>", h1("foo")), document(p("a"), h2("foo")));
    });
  });

  group("Fragment > findDiffEnd >", () {
    test("returns null when there is no difference", () {
      _end(
        document(p("a", em("b")), p("hello"), blockquote(h1("bye"))),
        document(p("a", em("b")), p("hello"), blockquote(h1("bye"))),
      );
    });

    test("notices when the second doc is longer", () {
      _end(
        document("<a>", p("a", em("b")), p("hello"), blockquote(h1("bye"))),
        document(p("oops"), p("a", em("b")), p("hello"), blockquote(h1("bye"))),
      );
    });

    test("notices when the second doc is shorter", () {
      _end(
        document(p("oops"), "<a>", p("a", em("b")), p("hello"), blockquote(h1("bye"))),
        document(p("a", em("b")), p("hello"), blockquote(h1("bye"))),
      );
    });

    test("notices different styles", () {
      _end(document(p("a", em("b"), "<a>c")), document(p("a", strong("b"), "c")));
    });

    test("spots longer text", () {
      _end(document(p("bar<a>foo", em("b"))), document(p("foo", em("b"))));
    });

    test("spots different text", () {
      _end(document(p("foob<a>ar")), document(p("foocar")));
    });

    test("notices different nodes", () {
      _end(document(p("a"), "<a>", p("b")), document(h1("a"), p("b")));
    });

    test("notices a difference at the end", () {
      _end(document(p("b"), "<a>"), document(h1("b")));
    });

    test("handles a similar start", () {
      _end(document("<a>", p("hello")), document(p("hey"), p("hello")));
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
