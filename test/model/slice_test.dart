import 'package:prosemirror/prosemirror.dart';
import 'package:test/test.dart';

import 'support/builders.dart';

void main() {
  group("Node > slice >", () {
    test("can cut half a paragraph", () {
      _slice(doc(p("hello<b> world")), doc(p("hello")), 0, 1);
    });

    test("can cut to the end of a paragraph", () {
      _slice(doc(p("hello<b>")), doc(p("hello")), 0, 1);
    });

    test("leaves off extra content", () {
      _slice(doc(p("hello<b> world"), p("rest")), doc(p("hello")), 0, 1);
    });

    test("preserves styles", () {
      _slice(
        doc(p("hello ", em("WOR<b>LD"))),
        doc(p("hello ", em("WOR"))),
        0,
        1,
      );
    });

    test("can cut multiple blocks", () {
      _slice(doc(p("a"), p("b<b>")), doc(p("a"), p("b")), 0, 1);
    });

    test("can cut to a top-level position", () {
      _slice(doc(p("a"), "<b>", p("b")), doc(p("a")), 0, 0);
    });

    test("can cut to a deep position", () {
      _slice(
        doc(blockquote(ul(li(p("a")), li(p("b<b>"))))),
        doc(blockquote(ul(li(p("a")), li(p("b"))))),
        0,
        4,
      );
    });

    test("can cut everything after a position", () {
      _slice(doc(p("hello<a> world")), doc(p(" world")), 1, 0);
    });

    test("can cut from the start of a textblock", () {
      _slice(doc(p("<a>hello")), doc(p("hello")), 1, 0);
    });

    test("leaves off extra content before", () {
      _slice(doc(p("foo"), p("bar<a>baz")), doc(p("baz")), 1, 0);
    });

    test("preserves styles after cut", () {
      _slice(
        doc(
          p("a sentence with an ", em("emphasized ", a("li<a>nk")), " in it"),
        ),
        doc(p(em(a("nk")), " in it")),
        1,
        0,
      );
    });

    test("preserves styles started after cut", () {
      _slice(
        doc(p("a ", em("sentence"), " wi<a>th ", em("text"), " in it")),
        doc(p("th ", em("text"), " in it")),
        1,
        0,
      );
    });

    test("can cut from a top-level position", () {
      _slice(doc(p("a"), "<a>", p("b")), doc(p("b")), 0, 0);
    });

    test("can cut from a deep position", () {
      _slice(
        doc(blockquote(ul(li(p("a")), li(p("<a>b"))))),
        doc(blockquote(ul(li(p("b"))))),
        4,
        0,
      );
    });

    test("can cut part of a text node", () {
      _slice(doc(p("hell<a>o wo<b>rld")), p("o wo"), 0, 0);
    });

    test("can cut across paragraphs", () {
      _slice(doc(p("on<a>e"), p("t<b>wo")), doc(p("e"), p("t")), 1, 1);
    });

    test("can cut part of marked text", () {
      _slice(
        doc(p("here's noth<a>ing and ", em("here's e<b>m"))),
        p("ing and ", em("here's e")),
        0,
        0,
      );
    });

    test("can cut across different depths", () {
      _slice(
        doc(ul(li(p("hello")), li(p("wo<a>rld")), li(p("x"))), p(em("bo<b>o"))),
        doc(ul(li(p("rld")), li(p("x"))), p(em("bo"))),
        3,
        1,
      );
    });

    test("can cut between deeply nested nodes", () {
      _slice(
        doc(
          blockquote(
            p("foo<a>bar"),
            ul(li(p("a")), li(p("b"), "<b>", p("c"))),
            p("d"),
          ),
        ),
        blockquote(p("bar"), ul(li(p("a")), li(p("b")))),
        1,
        2,
      );
    });

    test("can include parents", () {
      final d = doc(blockquote(p("fo<a>o"), p("bar<b>")));
      final slice = d.slice(d.tag["a"]!, d.tag["b"]!, true);
      expect(
        slice.toString(),
        '<blockquote(paragraph("o"), paragraph("bar"))>(2,2)',
      );
    });
  });
}

void _slice(Node document, Node expected, int openStart, int openEnd) {
  final slice = document.slice(document.tag["a"] ?? 0, document.tag["b"]);
  expect(slice.content.eq(expected.content), isTrue);
  expect(slice.openStart, openStart);
  expect(slice.openEnd, openEnd);
}
