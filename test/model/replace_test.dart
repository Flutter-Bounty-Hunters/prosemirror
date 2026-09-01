import 'package:prosemirror/prosemirror.dart';
import 'package:test/test.dart';

import 'package:prosemirror/test_builder.dart';

void main() {
  group("Node > replace >", () {
    test("joins on delete", () {
      _replace(document(p("on<a>e"), p("t<b>wo")), null, document(p("onwo")));
    });

    test("merges matching blocks", () {
      _replace(
        document(p("on<a>e"), p("t<b>wo")),
        document(p("xx<a>xx"), p("yy<b>yy")),
        document(p("onxx"), p("yywo")),
      );
    });

    test("merges when adding text", () {
      _replace(document(p("on<a>e"), p("t<b>wo")), document(p("<a>H<b>")), document(p("onHwo")));
    });

    test("can insert text", () {
      _replace(
        document(p("before"), p("on<a><b>e"), p("after")),
        document(p("<a>H<b>")),
        document(p("before"), p("onHe"), p("after")),
      );
    });

    test("doesn't merge non-matching blocks", () {
      _replace(document(p("on<a>e"), p("t<b>wo")), document(h1("<a>H<b>")), document(p("onHwo")));
    });

    test("can merge a nested node", () {
      _replace(
        document(blockquote(blockquote(p("on<a>e"), p("t<b>wo")))),
        document(p("<a>H<b>")),
        document(blockquote(blockquote(p("onHwo")))),
      );
    });

    test("can replace within a block", () {
      _replace(document(blockquote(p("a<a>bc<b>d"))), document(p("x<a>y<b>z")), document(blockquote(p("ayd"))));
    });

    test("can insert a lopsided slice", () {
      _replace(
        document(blockquote(blockquote(p("on<a>e"), p("two"), "<b>", p("three")))),
        document(blockquote(p("aa<a>aa"), p("bb"), p("cc"), "<b>", p("dd"))),
        document(blockquote(blockquote(p("onaa"), p("bb"), p("cc"), p("three")))),
      );
    });

    test("can insert a deep, lopsided slice", () {
      _replace(
        document(blockquote(blockquote(p("on<a>e"), p("two"), p("three")), "<b>", p("x"))),
        document(blockquote(p("aa<a>aa"), p("bb"), p("cc")), "<b>", p("dd")),
        document(blockquote(blockquote(p("onaa"), p("bb"), p("cc")), p("x"))),
      );
    });

    test("can merge multiple levels", () {
      _replace(
        document(blockquote(blockquote(p("hell<a>o"))), blockquote(blockquote(p("<b>a")))),
        null,
        document(blockquote(blockquote(p("hella")))),
      );
    });

    test("can merge multiple levels while inserting", () {
      _replace(
        document(blockquote(blockquote(p("hell<a>o"))), blockquote(blockquote(p("<b>a")))),
        document(p("<a>i<b>")),
        document(blockquote(blockquote(p("hellia")))),
      );
    });

    test("can insert a split", () {
      _replace(document(p("foo<a><b>bar")), document(p("<a>x"), p("y<b>")), document(p("foox"), p("ybar")));
    });

    test("can insert a deep split", () {
      _replace(
        document(blockquote(p("foo<a>x<b>bar"))),
        document(blockquote(p("<a>x")), blockquote(p("y<b>"))),
        document(blockquote(p("foox")), blockquote(p("ybar"))),
      );
    });

    test("can add a split one level up", () {
      _replace(
        document(blockquote(p("foo<a>u"), p("v<b>bar"))),
        document(blockquote(p("<a>x")), blockquote(p("y<b>"))),
        document(blockquote(p("foox")), blockquote(p("ybar"))),
      );
    });

    test("keeps the node type of the left node", () {
      _replace(document(h1("foo<a>bar"), "<b>"), document(p("foo<a>baz"), "<b>"), document(h1("foobaz")));
    });

    test("keeps the node type even when empty", () {
      _replace(document(h1("<a>bar"), "<b>"), document(p("foo<a>baz"), "<b>"), document(h1("baz")));
    });

    test("doesn't allow the left side to be too deep", () {
      _bad(document(p("<a><b>")), document(blockquote(p("<a>")), "<b>"), "deeper");
    });

    test("doesn't allow a depth mismatch", () {
      _bad(document(p("<a><b>")), document("<a>", p("<b>")), "inconsistent");
    });

    test("rejects a bad fit", () {
      _bad(document("<a><b>"), document(p("<a>foo<b>")), "invalid content");
    });

    test("rejects unjoinable content", () {
      _bad(document(ul(li(p("a")), "<a>"), "<b>"), document(p("foo", "<a>"), "<b>"), "cannot join");
    });

    test("rejects an unjoinable delete", () {
      _bad(document(blockquote(p("a"), "<a>"), ul("<b>", li(p("b")))), null, "cannot join");
    });

    test("checks content validity", () {
      _bad(document(blockquote("<a>", p("hi")), "<b>"), document(blockquote("hi", "<a>"), "<b>"), "invalid content");
    });
  });
}

void _replace(Node document, Node? insert, Node expected) {
  final slice = insert != null ? insert.slice(insert.tag["a"]!, insert.tag["b"]!) : Slice.empty;
  expect(document.replace(document.tag["a"]!, document.tag["b"]!, slice).eq(expected), isTrue);
}

void _bad(Node document, Node? insert, String pattern) {
  final slice = insert != null ? insert.slice(insert.tag["a"]!, insert.tag["b"]!) : Slice.empty;
  expect(
    () => document.replace(document.tag["a"]!, document.tag["b"]!, slice),
    throwsA(predicate((error) => RegExp(pattern, caseSensitive: false).hasMatch(error.toString()))),
  );
}
