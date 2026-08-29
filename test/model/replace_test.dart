import 'package:prosemirror/prosemirror.dart';
import 'package:test/test.dart';

import 'support/builders.dart';

void main() {
  group("Node > replace >", () {
    test("joins on delete", () {
      _replace(doc(p("on<a>e"), p("t<b>wo")), null, doc(p("onwo")));
    });

    test("merges matching blocks", () {
      _replace(
        doc(p("on<a>e"), p("t<b>wo")),
        doc(p("xx<a>xx"), p("yy<b>yy")),
        doc(p("onxx"), p("yywo")),
      );
    });

    test("merges when adding text", () {
      _replace(
        doc(p("on<a>e"), p("t<b>wo")),
        doc(p("<a>H<b>")),
        doc(p("onHwo")),
      );
    });

    test("can insert text", () {
      _replace(
        doc(p("before"), p("on<a><b>e"), p("after")),
        doc(p("<a>H<b>")),
        doc(p("before"), p("onHe"), p("after")),
      );
    });

    test("doesn't merge non-matching blocks", () {
      _replace(
        doc(p("on<a>e"), p("t<b>wo")),
        doc(h1("<a>H<b>")),
        doc(p("onHwo")),
      );
    });

    test("can merge a nested node", () {
      _replace(
        doc(blockquote(blockquote(p("on<a>e"), p("t<b>wo")))),
        doc(p("<a>H<b>")),
        doc(blockquote(blockquote(p("onHwo")))),
      );
    });

    test("can replace within a block", () {
      _replace(
        doc(blockquote(p("a<a>bc<b>d"))),
        doc(p("x<a>y<b>z")),
        doc(blockquote(p("ayd"))),
      );
    });

    test("can insert a lopsided slice", () {
      _replace(
        doc(blockquote(blockquote(p("on<a>e"), p("two"), "<b>", p("three")))),
        doc(blockquote(p("aa<a>aa"), p("bb"), p("cc"), "<b>", p("dd"))),
        doc(blockquote(blockquote(p("onaa"), p("bb"), p("cc"), p("three")))),
      );
    });

    test("can insert a deep, lopsided slice", () {
      _replace(
        doc(
          blockquote(
            blockquote(p("on<a>e"), p("two"), p("three")),
            "<b>",
            p("x"),
          ),
        ),
        doc(blockquote(p("aa<a>aa"), p("bb"), p("cc")), "<b>", p("dd")),
        doc(blockquote(blockquote(p("onaa"), p("bb"), p("cc")), p("x"))),
      );
    });

    test("can merge multiple levels", () {
      _replace(
        doc(
          blockquote(blockquote(p("hell<a>o"))),
          blockquote(blockquote(p("<b>a"))),
        ),
        null,
        doc(blockquote(blockquote(p("hella")))),
      );
    });

    test("can merge multiple levels while inserting", () {
      _replace(
        doc(
          blockquote(blockquote(p("hell<a>o"))),
          blockquote(blockquote(p("<b>a"))),
        ),
        doc(p("<a>i<b>")),
        doc(blockquote(blockquote(p("hellia")))),
      );
    });

    test("can insert a split", () {
      _replace(
        doc(p("foo<a><b>bar")),
        doc(p("<a>x"), p("y<b>")),
        doc(p("foox"), p("ybar")),
      );
    });

    test("can insert a deep split", () {
      _replace(
        doc(blockquote(p("foo<a>x<b>bar"))),
        doc(blockquote(p("<a>x")), blockquote(p("y<b>"))),
        doc(blockquote(p("foox")), blockquote(p("ybar"))),
      );
    });

    test("can add a split one level up", () {
      _replace(
        doc(blockquote(p("foo<a>u"), p("v<b>bar"))),
        doc(blockquote(p("<a>x")), blockquote(p("y<b>"))),
        doc(blockquote(p("foox")), blockquote(p("ybar"))),
      );
    });

    test("keeps the node type of the left node", () {
      _replace(
        doc(h1("foo<a>bar"), "<b>"),
        doc(p("foo<a>baz"), "<b>"),
        doc(h1("foobaz")),
      );
    });

    test("keeps the node type even when empty", () {
      _replace(
        doc(h1("<a>bar"), "<b>"),
        doc(p("foo<a>baz"), "<b>"),
        doc(h1("baz")),
      );
    });

    test("doesn't allow the left side to be too deep", () {
      _bad(doc(p("<a><b>")), doc(blockquote(p("<a>")), "<b>"), "deeper");
    });

    test("doesn't allow a depth mismatch", () {
      _bad(doc(p("<a><b>")), doc("<a>", p("<b>")), "inconsistent");
    });

    test("rejects a bad fit", () {
      _bad(doc("<a><b>"), doc(p("<a>foo<b>")), "invalid content");
    });

    test("rejects unjoinable content", () {
      _bad(
        doc(ul(li(p("a")), "<a>"), "<b>"),
        doc(p("foo", "<a>"), "<b>"),
        "cannot join",
      );
    });

    test("rejects an unjoinable delete", () {
      _bad(
        doc(blockquote(p("a"), "<a>"), ul("<b>", li(p("b")))),
        null,
        "cannot join",
      );
    });

    test("checks content validity", () {
      _bad(
        doc(blockquote("<a>", p("hi")), "<b>"),
        doc(blockquote("hi", "<a>"), "<b>"),
        "invalid content",
      );
    });
  });
}

void _replace(Node document, Node? insert, Node expected) {
  final slice = insert != null
      ? insert.slice(insert.tag["a"]!, insert.tag["b"]!)
      : Slice.empty;
  expect(
    document
        .replace(document.tag["a"]!, document.tag["b"]!, slice)
        .eq(expected),
    isTrue,
  );
}

void _bad(Node document, Node? insert, String pattern) {
  final slice = insert != null
      ? insert.slice(insert.tag["a"]!, insert.tag["b"]!)
      : Slice.empty;
  expect(
    () => document.replace(document.tag["a"]!, document.tag["b"]!, slice),
    throwsA(
      predicate(
        (error) =>
            RegExp(pattern, caseSensitive: false).hasMatch(error.toString()),
      ),
    ),
  );
}
