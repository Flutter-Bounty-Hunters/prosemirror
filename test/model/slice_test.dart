import 'package:prosemirror/prosemirror.dart';
import 'package:test/test.dart';

import 'package:prosemirror/test_builder.dart';

void main() {
  group("Node > slice >", () {
    test("can cut half a paragraph", () {
      _slice(document(p("hello<b> world")), document(p("hello")), 0, 1);
    });

    test("can cut to the end of a paragraph", () {
      _slice(document(p("hello<b>")), document(p("hello")), 0, 1);
    });

    test("leaves off extra content", () {
      _slice(document(p("hello<b> world"), p("rest")), document(p("hello")), 0, 1);
    });

    test("preserves styles", () {
      _slice(document(p("hello ", em("WOR<b>LD"))), document(p("hello ", em("WOR"))), 0, 1);
    });

    test("can cut multiple blocks", () {
      _slice(document(p("a"), p("b<b>")), document(p("a"), p("b")), 0, 1);
    });

    test("can cut to a top-level position", () {
      _slice(document(p("a"), "<b>", p("b")), document(p("a")), 0, 0);
    });

    test("can cut to a deep position", () {
      _slice(
        document(blockquote(ul(li(p("a")), li(p("b<b>"))))),
        document(blockquote(ul(li(p("a")), li(p("b"))))),
        0,
        4,
      );
    });

    test("can cut everything after a position", () {
      _slice(document(p("hello<a> world")), document(p(" world")), 1, 0);
    });

    test("can cut from the start of a textblock", () {
      _slice(document(p("<a>hello")), document(p("hello")), 1, 0);
    });

    test("leaves off extra content before", () {
      _slice(document(p("foo"), p("bar<a>baz")), document(p("baz")), 1, 0);
    });

    test("preserves styles after cut", () {
      _slice(
        document(p("a sentence with an ", em("emphasized ", a("li<a>nk")), " in it")),
        document(p(em(a("nk")), " in it")),
        1,
        0,
      );
    });

    test("preserves styles started after cut", () {
      _slice(
        document(p("a ", em("sentence"), " wi<a>th ", em("text"), " in it")),
        document(p("th ", em("text"), " in it")),
        1,
        0,
      );
    });

    test("can cut from a top-level position", () {
      _slice(document(p("a"), "<a>", p("b")), document(p("b")), 0, 0);
    });

    test("can cut from a deep position", () {
      _slice(document(blockquote(ul(li(p("a")), li(p("<a>b"))))), document(blockquote(ul(li(p("b"))))), 4, 0);
    });

    test("can cut part of a text node", () {
      _slice(document(p("hell<a>o wo<b>rld")), p("o wo"), 0, 0);
    });

    test("can cut across paragraphs", () {
      _slice(document(p("on<a>e"), p("t<b>wo")), document(p("e"), p("t")), 1, 1);
    });

    test("can cut part of marked text", () {
      _slice(document(p("here's noth<a>ing and ", em("here's e<b>m"))), p("ing and ", em("here's e")), 0, 0);
    });

    test("can cut across different depths", () {
      _slice(
        document(ul(li(p("hello")), li(p("wo<a>rld")), li(p("x"))), p(em("bo<b>o"))),
        document(ul(li(p("rld")), li(p("x"))), p(em("bo"))),
        3,
        1,
      );
    });

    test("can cut between deeply nested nodes", () {
      _slice(
        document(blockquote(p("foo<a>bar"), ul(li(p("a")), li(p("b"), "<b>", p("c"))), p("d"))),
        blockquote(p("bar"), ul(li(p("a")), li(p("b")))),
        1,
        2,
      );
    });

    test("can include parents", () {
      final d = document(blockquote(p("fo<a>o"), p("bar<b>")));
      final slice = d.slice(d.tag["a"]!, d.tag["b"]!, true);
      expect(slice.toString(), '<blockquote(paragraph("o"), paragraph("bar"))>(2,2)');
    });
  });
}

void _slice(Node document, Node expected, int openStart, int openEnd) {
  final slice = document.slice(document.tag["a"] ?? 0, document.tag["b"]);
  expect(slice.content.eq(expected.content), isTrue);
  expect(slice.openStart, openStart);
  expect(slice.openEnd, openEnd);
}
