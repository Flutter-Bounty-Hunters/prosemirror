import 'package:prosemirror/prosemirror.dart';
import 'package:test/test.dart';

import 'package:prosemirror/test_builder.dart';

void main() {
  group("wrapInList >", () {
    final wrap = wrapInList(schema.nodes["bullet_list"]!);
    final wrapOrdered = wrapInList(schema.nodes["ordered_list"]!);

    test("can wrap a paragraph", () {
      _apply(document(p("<a>foo")), wrap, document(ul(li(p("foo")))));
    });

    test("can wrap a nested paragraph", () {
      _apply(document(blockquote(p("<a>foo"))), wrapOrdered, document(blockquote(ol(li(p("foo"))))));
    });

    test("can wrap multiple paragraphs", () {
      _apply(document(p("foo"), p("ba<a>r"), p("ba<b>z")), wrap, document(p("foo"), ul(li(p("bar")), li(p("baz")))));
    });

    test("doesn't wrap the first paragraph in a list item", () {
      _apply(document(ul(li(p("<a>foo")))), wrap, null);
    });

    test("doesn't wrap the first para in a different type of list item", () {
      _apply(document(ol(li(p("<a>foo")))), wrapOrdered, null);
    });

    test("does wrap the second paragraph in a list item", () {
      _apply(document(ul(li(p("foo"), p("<a>bar")))), wrap, document(ul(li(p("foo"), ul(li(p("bar")))))));
    });

    test("joins with the list item above when wrapping its first paragraph", () {
      _apply(
        document(ul(li(p("foo")), li(p("<a>bar")), li(p("baz")))),
        wrapOrdered,
        document(ul(li(p("foo"), ol(li(p("bar")))), li(p("baz")))),
      );
    });

    test("only splits items where valid", () {
      _apply(
        document(p("<a>one"), ol(li("two")), p("three<b>")),
        wrapOrdered,
        document(ol(li(p("one"), ol(li("two"))), li(p("three")))),
      );
    });
  });

  group("splitListItem >", () {
    final split = splitListItem(schema.nodes["list_item"]!);

    test("has no effect outside of a list", () {
      _apply(document(p("foo<a>bar")), split, null);
    });

    test("has no effect on the top level", () {
      _apply(document("<a>", p("foobar")), split, null);
    });

    test("can split a list item", () {
      _apply(document(ul(li(p("foo<a>bar")))), split, document(ul(li(p("foo")), li(p("bar")))));
    });

    test("can split a list item at the end", () {
      _apply(document(ul(li(p("foobar<a>")))), split, document(ul(li(p("foobar")), li(p()))));
    });

    test("deletes selected content", () {
      _apply(document(ul(li(p("foo<a>ba<b>r")))), split, document(ul(li(p("foo")), li(p("r")))));
    });

    test("splits when lifting from a nested list", () {
      _apply(
        document(ul(li(p("a"), ul(li(p("b")), li(p("<a>"))))), p("x")),
        split,
        document(ul(li(p("a"), ul(li(p("b")))), li(p("<a>"))), p("x")),
      );
    });

    test("can lift from a continued nested list item", () {
      _apply(
        document(ul(li(p("a"), ul(li(p("b")), li(p("ok"), p("<a>"))))), p("x")),
        split,
        document(ul(li(p("a"), ul(li(p("b")), li(p("ok")))), li(p("<a>"))), p("x")),
      );
    });

    test("correctly lifts an entirely empty sublist", () {
      _apply(
        document(ul(li(p("one"), ul(li(p("<a>"))), p("two")))),
        split,
        document(ul(li(p("one")), li(p("<a>")), li(p("two")))),
      );
    });
  });

  group("liftListItem >", () {
    final lift = liftListItem(schema.nodes["list_item"]!);

    test("can lift from a nested list", () {
      _apply(
        document(ul(li(p("hello"), ul(li(p("o<a><b>ne")), li(p("two")))))),
        lift,
        document(ul(li(p("hello")), li(p("one"), ul(li(p("two")))))),
      );
    });

    test("can lift two items from a nested list", () {
      _apply(
        document(ul(li(p("hello"), ul(li(p("o<a>ne")), li(p("two<b>")))))),
        lift,
        document(ul(li(p("hello")), li(p("one")), li(p("two")))),
      );
    });

    test("can lift two items from a nested three-item list", () {
      _apply(
        document(ul(li(p("hello"), ul(li(p("o<a>ne")), li(p("two<b>")), li(p("three")))))),
        lift,
        document(ul(li(p("hello")), li(p("one")), li(p("two"), ul(li(p("three")))))),
      );
    });

    test("can lift an item out of a list", () {
      _apply(document(p("a"), ul(li(p("b<a>"))), p("c")), lift, document(p("a"), p("b"), p("c")));
    });

    test("can lift two items out of a list", () {
      _apply(
        document(p("a"), ul(li(p("b<a>")), li(p("c<b>"))), p("d")),
        lift,
        document(p("a"), p("b"), p("c"), p("d")),
      );
    });

    test("can lift three items from the middle of a list", () {
      _apply(
        document(ul(li(p("a")), li(p("b<a>")), li(p("c")), li(p("d<b>")), li(p("e")))),
        lift,
        document(ul(li(p("a"))), p("b"), p("c"), p("d"), ul(li(p("e")))),
      );
    });

    test("can lift the first item from a list", () {
      _apply(document(ul(li(p("a<a>")), li(p("b")), li(p("c")))), lift, document(p("a"), ul(li(p("b")), li(p("c")))));
    });

    test("can lift the last item from a list", () {
      _apply(document(ul(li(p("a")), li(p("b")), li(p("c<a>")))), lift, document(ul(li(p("a")), li(p("b"))), p("c")));
    });

    test("joins adjacent lists when lifting an item with subitems", () {
      _apply(
        document(ol(li(p("a"), ol(li(p("<a>b<b>"), ol(li(p("c")))), li(p("d")))), li(p("e")))),
        lift,
        document(ol(li(p("a")), li(p("b"), ol(li(p("c")), li(p("d")))), li(p("e")))),
      );
    });

    test("only joins adjacent lists when lifting if their types match", () {
      _apply(
        document(ol(li(p("a"), ul(li(p("<a>b<b>"), ol(li(p("c")))), li(p("d")))))),
        lift,
        document(ol(li(p("a")), li(p("b"), ol(li(p("c"))), ul(li(p("d")))))),
      );
    });
  });

  group("sinkListItem >", () {
    final sink = sinkListItem(schema.nodes["list_item"]!);

    test("can wrap a simple item in a list", () {
      _apply(
        document(ul(li(p("one")), li(p("t<a><b>wo")), li(p("three")))),
        sink,
        document(ul(li(p("one"), ul(li(p("two")))), li(p("three")))),
      );
    });

    test("won't wrap the first item in a sublist", () {
      _apply(document(ul(li(p("o<a><b>ne")), li(p("two")), li(p("three")))), sink, null);
    });

    test("will move an item's content into the item above", () {
      _apply(
        document(ul(li(p("one")), li(p("..."), ul(li(p("two")))), li(p("t<a><b>hree")))),
        sink,
        document(ul(li(p("one")), li(p("..."), ul(li(p("two")), li(p("three")))))),
      );
    });
  });
}

void _apply(Node document, Command command, Node? result) {
  var state = EditorState.create(EditorStateConfig(doc: document, selection: _selFor(document)));
  command.execute(state, (tr) => state = state.apply(tr));

  expect(state.doc.eq(result ?? document), isTrue);
  if (result != null && result.tag["a"] != null) {
    expect(state.selection.eq(_selFor(result)), isTrue);
  }
}

Selection _selFor(Node document) {
  final a = document.tag["a"];
  if (a != null) {
    final $a = document.resolve(a);
    if ($a.parent.inlineContent) {
      final b = document.tag["b"];
      return TextSelection($a, b != null ? document.resolve(b) : null);
    }
    return NodeSelection($a);
  }
  return Selection.atStart(document);
}
