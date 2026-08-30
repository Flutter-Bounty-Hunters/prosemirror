import 'package:prosemirror/prosemirror.dart';
import 'package:test/test.dart';

import '../model/support/builders.dart';
import 'support/transform_test_helpers.dart';

void main() {
  group("Transform > addMark >", () {
    test("should add a mark", () {
      _addMark(
        doc(p("hello <a>there<b>!")),
        schema.mark("strong"),
        doc(p("hello ", strong("there"), "!")),
      );
    });

    test("should only add a mark once", () {
      _addMark(
        doc(p("hello ", strong("<a>there"), "!<b>")),
        schema.mark("strong"),
        doc(p("hello ", strong("there!"))),
      );
    });

    test("should join overlapping marks", () {
      _addMark(
        doc(p("one <a>two ", em("three<b> four"))),
        schema.mark("strong"),
        doc(p("one ", strong("two ", em("three")), em(" four"))),
      );
    });

    test("should overwrite marks with different attributes", () {
      _addMark(
        doc(p("this is a ", a("<a>link<b>"))),
        schema.mark("link", {"href": "bar"}),
        doc(p("this is a ", a({"href": "bar"}, "link"))),
      );
    });

    test("can add a mark in a nested node", () {
      _addMark(
        doc(
          p("before"),
          blockquote(p("the variable is called <a>i<b>")),
          p("after"),
        ),
        schema.mark("code"),
        doc(
          p("before"),
          blockquote(p("the variable is called ", code("i"))),
          p("after"),
        ),
      );
    });

    test("can add a mark across blocks", () {
      _addMark(
        doc(p("hi <a>this"), blockquote(p("is")), p("a docu<b>ment"), p("!")),
        schema.mark("em"),
        doc(
          p("hi ", em("this")),
          blockquote(p(em("is"))),
          p(em("a docu"), "ment"),
          p("!"),
        ),
      );
    });

    test("does not remove non-excluded marks of the same type", () {
      final schema = Schema(
        SchemaSpec(
          nodes: <String, NodeSpec>{
            "doc": NodeSpec(content: "text*"),
            "text": NodeSpec(),
          },
          marks: <String, MarkSpec>{
            "comment": MarkSpec(
              excludes: "",
              attrs: {"id": const AttributeSpec()},
            ),
          },
        ),
      );
      final tr = Transform(
        schema.node(
          "doc",
          null,
          schema.text("hi", [
            schema.mark("comment", {"id": 10}),
          ]),
        ),
      );
      tr.addMark(0, 2, schema.mark("comment", {"id": 20}));
      expect(tr.doc.firstChild!.marks.length, 2);
    });

    test("can remove multiple excluded marks", () {
      final schema = Schema(
        SchemaSpec(
          nodes: <String, NodeSpec>{
            "doc": NodeSpec(content: "text*"),
            "text": NodeSpec(),
          },
          marks: <String, MarkSpec>{
            "big": MarkSpec(excludes: "small1 small2"),
            "small1": MarkSpec(),
            "small2": MarkSpec(),
          },
        ),
      );
      final tr = Transform(
        schema.node(
          "doc",
          null,
          schema.text("hi", [schema.mark("small1"), schema.mark("small2")]),
        ),
      );
      expect(tr.doc.firstChild!.marks.length, 2);
      tr.addMark(0, 2, schema.mark("big"));
      expect(tr.doc.firstChild!.marks.length, 1);
      expect(tr.doc.firstChild!.marks[0].type.name, "big");
    });
  });

  group("Transform > removeMark >", () {
    test("can cut a gap", () {
      _removeMark(
        doc(p(em("hello <a>world<b>!"))),
        schema.mark("em"),
        doc(p(em("hello "), "world", em("!"))),
      );
    });

    test("doesn't do anything when there's no mark", () {
      _removeMark(
        doc(p(em("hello"), " <a>world<b>!")),
        schema.mark("em"),
        doc(p(em("hello"), " <a>world<b>!")),
      );
    });

    test("can remove marks from nested nodes", () {
      _removeMark(
        doc(p(em("one ", strong("<a>two<b>"), " three"))),
        schema.mark("strong"),
        doc(p(em("one two three"))),
      );
    });

    test("can remove a link", () {
      _removeMark(
        doc(p("<a>hello ", a("link<b>"))),
        schema.mark("link", {"href": "foo"}),
        doc(p("hello link")),
      );
    });

    test("doesn't remove a non-matching link", () {
      _removeMark(
        doc(p("<a>hello ", a("link<b>"))),
        schema.mark("link", {"href": "bar"}),
        doc(p("hello ", a("link"))),
      );
    });

    test("can remove across blocks", () {
      _removeMark(
        doc(
          blockquote(p(em("much <a>em")), p(em("here too"))),
          p("between", em("...")),
          p(em("end<b>")),
        ),
        schema.mark("em"),
        doc(
          blockquote(p(em("much "), "em"), p("here too")),
          p("between..."),
          p("end"),
        ),
      );
    });

    test("can remove everything", () {
      _removeMark(
        doc(
          p("<a>hello, ", em("this is ", strong("much"), " ", a("markup<b>"))),
        ),
        null,
        doc(p("<a>hello, this is much markup")),
      );
    });

    test("can remove more than one mark of the same type from a block", () {
      final schema = Schema(
        SchemaSpec(
          nodes: <String, NodeSpec>{
            "doc": NodeSpec(content: "text*"),
            "text": NodeSpec(),
          },
          marks: <String, MarkSpec>{
            "comment": MarkSpec(
              excludes: "",
              attrs: {"id": const AttributeSpec()},
            ),
          },
        ),
      );
      final tr = Transform(
        schema.node(
          "doc",
          null,
          schema.text("hi", [
            schema.mark("comment", {"id": 1}),
            schema.mark("comment", {"id": 2}),
          ]),
        ),
      );
      expect(tr.doc.firstChild!.marks.length, 2);
      tr.removeMark(0, 2, schema.marks["comment"]);
      expect(tr.doc.firstChild!.marks.length, 0);
    });
  });

  group("Transform > insert >", () {
    test("can insert a break", () {
      _insert(
        doc(p("hello<a>there")),
        schema.node("hard_break"),
        doc(p("hello", br(), "<a>there")),
      );
    });

    test("can insert an empty paragraph at the top", () {
      _insert(
        doc(p("one"), "<a>", p("two<2>")),
        schema.node("paragraph"),
        doc(p("one"), p(), "<a>", p("two<2>")),
      );
    });

    test("can insert two block nodes", () {
      _insert(doc(p("one"), "<a>", p("two<2>")), [
        schema.node("paragraph", null, [schema.text("hi")]),
        schema.node("horizontal_rule"),
      ], doc(p("one"), p("hi"), hr(), "<a>", p("two<2>")));
    });

    test("can insert at the end of a blockquote", () {
      _insert(
        doc(blockquote(p("he<before>y"), "<a>"), p("after<after>")),
        schema.node("paragraph"),
        doc(blockquote(p("he<before>y"), p()), p("after<after>")),
      );
    });

    test("can insert at the start of a blockquote", () {
      _insert(
        doc(blockquote("<a>", p("he<1>y")), p("after<2>")),
        schema.node("paragraph"),
        doc(blockquote(p(), "<a>", p("he<1>y")), p("after<2>")),
      );
    });

    test("will wrap a node with the suitable parent", () {
      _insert(
        doc(p("foo<a>bar")),
        schema.nodes["list_item"]!.createAndFill()!,
        doc(p("foo"), ol(li(p())), p("bar")),
      );
    });
  });

  group("Transform > delete >", () {
    test("can delete a word", () {
      _delete(
        doc(p("<1>one"), "<a>", p("tw<2>o"), "<b>", p("<3>three")),
        doc(p("<1>one"), "<a><2>", p("<3>three")),
      );
    });

    test("preserves content constraints", () {
      _delete(
        doc(blockquote("<a>", p("hi"), "<b>"), p("x")),
        doc(blockquote(p()), p("x")),
      );
    });

    test("preserves positions after the range", () {
      _delete(
        doc(blockquote(p("a"), "<a>", p("b"), "<b>"), p("c<1>")),
        doc(blockquote(p("a")), p("c<1>")),
      );
    });

    test("doesn't join incompatible nodes", () {
      _delete(
        doc(pre("fo<a>o"), p("b<b>ar", img())),
        doc(pre("fo"), p("ar", img())),
      );
    });

    test("doesn't join when marks are incompatible", () {
      _delete(doc(pre("fo<a>o"), p(em("b<b>ar"))), doc(pre("fo"), p(em("ar"))));
    });
  });

  group("Transform > join >", () {
    test("can join blocks", () {
      _join(
        doc(
          blockquote(p("<before>a")),
          "<a>",
          blockquote(p("b")),
          p("after<after>"),
        ),
        doc(blockquote(p("<before>a"), "<a>", p("b")), p("after<after>")),
      );
    });

    test("can join compatible blocks", () {
      _join(doc(h1("foo"), "<a>", p("bar")), doc(h1("foobar")));
    });

    test("can join nested blocks", () {
      _join(
        doc(
          blockquote(
            blockquote(p("a"), p("b<before>")),
            "<a>",
            blockquote(p("c"), p("d<after>")),
          ),
        ),
        doc(
          blockquote(
            blockquote(p("a"), p("b<before>"), "<a>", p("c"), p("d<after>")),
          ),
        ),
      );
    });

    test("can join lists", () {
      _join(
        doc(ol(li(p("one")), li(p("two"))), "<a>", ol(li(p("three")))),
        doc(ol(li(p("one")), li(p("two")), "<a>", li(p("three")))),
      );
    });

    test("can join list items", () {
      _join(
        doc(ol(li(p("one")), li(p("two")), "<a>", li(p("three")))),
        doc(ol(li(p("one")), li(p("two"), "<a>", p("three")))),
      );
    });

    test("can join textblocks", () {
      _join(doc(p("foo"), "<a>", p("bar")), doc(p("foo<a>bar")));
    });

    test("converts newlines to line breaks", () {
      _join(
        _lbDoc(_lbParagraph("one"), "<a>", _lbPre("two\nthree")),
        _lbDoc(_lbParagraph("one<a>two", _lbBr(), "three")),
      );
    });

    test("converts line breaks to newlines", () {
      _join(
        _lbDoc(_lbPre("one"), "<a>", _lbParagraph("two", _lbBr(), "three")),
        _lbDoc(_lbPre("one<a>two\nthree")),
      );
    });
  });

  group("Transform > split >", () {
    test("can split a textblock", () {
      _split(doc(p("foo<a>bar")), doc(p("foo"), p("<a>bar")));
    });

    test("correctly maps positions", () {
      _split(
        doc(p("<1>a"), p("<2>foo<a>bar<3>"), p("<4>b")),
        doc(p("<1>a"), p("<2>foo"), p("<a>bar<3>"), p("<4>b")),
      );
    });

    test("can split two deep", () {
      _split(
        doc(blockquote(blockquote(p("foo<a>bar"))), p("after<1>")),
        doc(
          blockquote(blockquote(p("foo")), blockquote(p("<a>bar"))),
          p("after<1>"),
        ),
        2,
      );
    });

    test("can split three deep", () {
      _split(
        doc(blockquote(blockquote(p("foo<a>bar"))), p("after<1>")),
        doc(
          blockquote(blockquote(p("foo"))),
          blockquote(blockquote(p("<a>bar"))),
          p("after<1>"),
        ),
        3,
      );
    });

    test("can split at end", () {
      _split(doc(blockquote(p("hi<a>"))), doc(blockquote(p("hi"), p("<a>"))));
    });

    test("can split at start", () {
      _split(doc(blockquote(p("<a>hi"))), doc(blockquote(p(), p("<a>hi"))));
    });

    test("can split inside a list item", () {
      _split(
        doc(ol(li(p("one<1>")), li(p("two<a>three")), li(p("four<2>")))),
        doc(ol(li(p("one<1>")), li(p("two"), p("<a>three")), li(p("four<2>")))),
      );
    });

    test("can split a list item", () {
      _split(
        doc(ol(li(p("one<1>")), li(p("two<a>three")), li(p("four<2>")))),
        doc(
          ol(
            li(p("one<1>")),
            li(p("two")),
            li(p("<a>three")),
            li(p("four<2>")),
          ),
        ),
        2,
      );
    });

    test("respects the type param", () {
      _split(doc(h1("hell<a>o!")), doc(h1("hell"), p("<a>o!")), null, [
        (type: schema.nodes["paragraph"]!, attrs: null),
      ]);
    });

    test("preserves content constraints before", () {
      _split(doc(blockquote("<a>", p("x"))), "fail");
    });

    test("preserves content constraints after", () {
      _split(doc(blockquote(p("x"), "<a>")), "fail");
    });
  });

  group("Transform > lift >", () {
    test("can lift a block out of the middle of its parent", () {
      _lift(
        doc(blockquote(p("<before>one"), p("<a>two"), p("<after>three"))),
        doc(
          blockquote(p("<before>one")),
          p("<a>two"),
          blockquote(p("<after>three")),
        ),
      );
    });

    test("can lift a block from the start of its parent", () {
      _lift(
        doc(blockquote(p("<a>two"), p("<after>three"))),
        doc(p("<a>two"), blockquote(p("<after>three"))),
      );
    });

    test("can lift a block from the end of its parent", () {
      _lift(
        doc(blockquote(p("<before>one"), p("<a>two"))),
        doc(blockquote(p("<before>one")), p("<a>two")),
      );
    });

    test("can lift a single child", () {
      _lift(doc(blockquote(p("<a>t<in>wo"))), doc(p("<a>t<in>wo")));
    });

    test("can lift multiple blocks", () {
      _lift(
        doc(blockquote(blockquote(p("on<a>e"), p("tw<b>o")), p("three"))),
        doc(blockquote(p("on<a>e"), p("tw<b>o"), p("three"))),
      );
    });

    test("finds a valid range from a lopsided selection", () {
      _lift(
        doc(p("start"), blockquote(blockquote(p("a"), p("<a>b")), p("<b>c"))),
        doc(p("start"), blockquote(p("a"), p("<a>b")), p("<b>c")),
      );
    });

    test("can lift from a nested node", () {
      _lift(
        doc(
          blockquote(
            blockquote(
              p("<1>one"),
              p("<a>two"),
              p("<3>three"),
              p("<b>four"),
              p("<5>five"),
            ),
          ),
        ),
        doc(
          blockquote(
            blockquote(p("<1>one")),
            p("<a>two"),
            p("<3>three"),
            p("<b>four"),
            blockquote(p("<5>five")),
          ),
        ),
      );
    });

    test("can lift from a list", () {
      _lift(
        doc(ul(li(p("one")), li(p("two<a>")), li(p("three")))),
        doc(ul(li(p("one"))), p("two<a>"), ul(li(p("three")))),
      );
    });

    test("can lift from the end of a list", () {
      _lift(
        doc(ul(li(p("a")), li(p("b<a>")), "<1>")),
        doc(ul(li(p("a"))), p("b<a>"), "<1>"),
      );
    });
  });

  group("Transform > wrap >", () {
    test("can wrap in a blockquote", () {
      _wrap(
        doc(p("one"), p("<a>two"), p("three")),
        doc(p("one"), blockquote(p("<a>two")), p("three")),
        "blockquote",
      );
    });

    test("can wrap two paragraphs", () {
      _wrap(
        doc(p("one<1>"), p("<a>two"), p("<b>three"), p("four<4>")),
        doc(p("one<1>"), blockquote(p("<a>two"), p("three")), p("four<4>")),
        "blockquote",
      );
    });

    test("can wrap in a list", () {
      _wrap(
        doc(p("<a>one"), p("<b>two")),
        doc(ol(li(p("<a>one"), p("<b>two")))),
        "ordered_list",
      );
    });

    test("can wrap in a nested list", () {
      _wrap(
        doc(
          ol(
            li(p("<1>one")),
            li(p("..."), p("<a>two"), p("<b>three")),
            li(p("<4>four")),
          ),
        ),
        doc(
          ol(
            li(p("<1>one")),
            li(p("..."), ol(li(p("<a>two"), p("<b>three")))),
            li(p("<4>four")),
          ),
        ),
        "ordered_list",
      );
    });

    test("includes half-covered parent nodes", () {
      _wrap(
        doc(blockquote(p("<1>one"), p("two<a>")), p("three<b>")),
        doc(blockquote(blockquote(p("<1>one"), p("two<a>")), p("three<b>"))),
        "blockquote",
      );
    });
  });

  group("Transform > setBlockType >", () {
    test("can change a single textblock", () {
      _setBlockType(doc(p("am<a> i")), doc(h2("am i")), "heading", {
        "level": 2,
      });
    });

    test("can change multiple blocks", () {
      _setBlockType(
        doc(h1("<a>hello"), p("there"), p("<b>you"), p("end")),
        doc(pre("hello"), pre("there"), pre("you"), p("end")),
        "code_block",
      );
    });

    test("can change a wrapped block", () {
      _setBlockType(
        doc(blockquote(p("one<a>"), p("two<b>"))),
        doc(blockquote(h1("one<a>"), h1("two<b>"))),
        "heading",
        {"level": 1},
      );
    });

    test("clears markup when necessary", () {
      _setBlockType(
        doc(p("hello<a> ", em("world"))),
        doc(pre("hello world")),
        "code_block",
      );
    });

    test("removes non-allowed nodes", () {
      _setBlockType(
        doc(p("<a>one", img(), "two", img(), "three")),
        doc(pre("onetwothree")),
        "code_block",
      );
    });

    test("removes newlines in non-code", () {
      _setBlockType(
        doc(pre("<a>one\ntwo\nthree")),
        doc(p("one two three")),
        "paragraph",
      );
    });

    test("only clears markup when needed", () {
      _setBlockType(
        doc(p("hello<a> ", em("world"))),
        doc(h1("hello<a> ", em("world"))),
        "heading",
        {"level": 1},
      );
    });

    test("works after another step", () {
      final d = doc(p("f<x>oob<y>ar"), p("baz<a>"));
      final tr = Transform(d).delete(_tag(d, "x"), _tag(d, "y"));
      final pos = tr.mapping.map(_tag(d, "a"));
      tr.setBlockType(pos, pos, schema.nodes["heading"]!, {"level": 1});
      testTransform(tr, doc(p("f<x><y>ar"), h1("baz<a>")));
    });

    test("skips nodes that can't be changed due to constraints", () {
      _setBlockType(
        doc(p("<a>hello", img()), p("okay"), ul(li(p("foo<b>")))),
        doc(pre("<a>hello"), pre("okay"), ul(li(p("foo<b>")))),
        "code_block",
      );
    });

    test("converts newlines to linebreak replacements when appropriate", () {
      _setBlockType(
        _lbDoc(_lbPre("<a>one\ntwo\nthree")),
        _lbDoc(_lbParagraph("<a>one", _lbBr(), "two", _lbBr(), "three")),
        "paragraph",
      );

      _setBlockType(
        _lbDoc(_lbParagraph("<a>one\ntwo")),
        _lbDoc(_lbPre("<a>one\ntwo")),
        "code_block",
      );
    });

    test("converts linebreak replacements to newlines when appropriate", () {
      _setBlockType(
        _lbDoc(_lbParagraph("<a>one", _lbBr(), "two", _lbBr(), "three")),
        _lbDoc(_lbPre("<a>one\ntwo\nthree")),
        "code_block",
      );

      _setBlockType(
        _lbDoc(_lbParagraph("<a>one", _lbBr(), "two", _lbBr(), "three")),
        _lbDoc(_lbHeading1("<a>one", _lbBr(), "two", _lbBr(), "three")),
        "heading",
        {"level": 1},
      );
    });

    test("can base attributes on previous attributes", () {
      _setBlockType(
        doc("<a>", h1("a"), p("b"), "<b>"),
        doc(h2("a"), h1("b")),
        "heading",
        (Node node) => <String, Object?>{
          "level": ((node.attrs["level"] as int?) ?? 0) + 1,
        },
      );
    });
  });

  group("Transform > setNodeMarkup >", () {
    test("can change a textblock", () {
      _setNodeMarkup(doc("<a>", p("foo")), doc(h1("foo")), "heading", {
        "level": 1,
      });
    });

    test("can change an inline node", () {
      _setNodeMarkup(
        doc(p("foo<a>", img(), "bar")),
        doc(p("foo", img({"src": "bar", "alt": "y"}), "bar")),
        "image",
        {"src": "bar", "alt": "y"},
      );
    });
  });

  group("Transform > replace >", () {
    test("can delete text", () {
      _replace(doc(p("hell<a>o y<b>ou")), null, doc(p("hell<a><b>ou")));
    });

    test("can join blocks", () {
      _replace(doc(p("hell<a>o"), p("y<b>ou")), null, doc(p("hell<a><b>ou")));
    });

    test("can delete right-leaning lopsided regions", () {
      _replace(
        doc(blockquote(p("ab<a>c")), "<b>", p("def")),
        null,
        doc(blockquote(p("ab<a>")), "<b>", p("def")),
      );
    });

    test("can delete left-leaning lopsided regions", () {
      _replace(
        doc(p("abc"), "<a>", blockquote(p("d<b>ef"))),
        null,
        doc(p("abc"), "<a>", blockquote(p("<b>ef"))),
      );
    });

    test("can overwrite text", () {
      _replace(
        doc(p("hell<a>o y<b>ou")),
        doc(p("<a>i k<b>")),
        doc(p("hell<a>i k<b>ou")),
      );
    });

    test("can insert text", () {
      _replace(
        doc(p("hell<a><b>o")),
        doc(p("<a>i k<b>")),
        doc(p("helli k<a><b>o")),
      );
    });

    test("can add a textblock", () {
      _replace(
        doc(p("hello<a>you")),
        doc("<a>", p("there"), "<b>"),
        doc(p("hello"), p("there"), p("<a>you")),
      );
    });

    test("can insert while joining textblocks", () {
      _replace(
        doc(h1("he<a>llo"), p("arg<b>!")),
        doc(p("1<a>2<b>3")),
        doc(h1("he2!")),
      );
    });

    test("will match open list items", () {
      _replace(
        doc(ol(li(p("one<a>")), li(p("three")))),
        doc(ol(li(p("<a>half")), li(p("two")), "<b>")),
        doc(ol(li(p("onehalf")), li(p("two")), li(p("three")))),
      );
    });

    test("merges blocks across deleted content", () {
      _replace(doc(p("a<a>"), p("b"), p("<b>c")), null, doc(p("a<a><b>c")));
    });

    test("can merge text down from nested nodes", () {
      _replace(
        doc(h1("wo<a>ah"), blockquote(p("ah<b>ha"))),
        null,
        doc(h1("wo<a><b>ha")),
      );
    });

    test("can merge text up into nested nodes", () {
      _replace(
        doc(blockquote(p("foo<a>bar")), p("middle"), h1("quux<b>baz")),
        null,
        doc(blockquote(p("foo<a><b>baz"))),
      );
    });

    test("will join multiple levels when possible", () {
      _replace(
        doc(
          blockquote(
            ul(
              li(p("a")),
              li(p("b<a>")),
              li(p("c")),
              li(p("<b>d")),
              li(p("e")),
            ),
          ),
        ),
        null,
        doc(blockquote(ul(li(p("a")), li(p("b<a><b>d")), li(p("e"))))),
      );
    });

    test("can replace a piece of text", () {
      _replace(
        doc(p("he<before>llo<a> w<after>orld")),
        doc(p("<a> big<b>")),
        doc(p("he<before>llo big w<after>orld")),
      );
    });

    test("respects open empty nodes at the edges", () {
      _replace(
        doc(p("one<a>two")),
        doc(p("a<a>"), p("hello"), p("<b>b")),
        doc(p("one"), p("hello"), p("<a>two")),
      );
    });

    test("can completely overwrite a paragraph", () {
      _replace(
        doc(p("one<a>"), p("t<inside>wo"), p("<b>three<end>")),
        doc(p("a<a>"), p("TWO"), p("<b>b")),
        doc(p("one<a>"), p("TWO"), p("<inside>three<end>")),
      );
    });

    test("joins marks", () {
      _replace(
        doc(p("foo ", em("bar<a>baz"), "<b> quux")),
        doc(p("foo ", em("xy<a>zzy"), " foo<b>")),
        doc(p("foo ", em("barzzy"), " foo quux")),
      );
    });

    test("can replace text with a break", () {
      _replace(
        doc(p("foo<a>b<inside>b<b>bar")),
        doc(p("<a>", br(), "<b>")),
        doc(p("foo", br(), "<inside>bar")),
      );
    });

    test("can join different blocks", () {
      _replace(doc(h1("hell<a>o"), p("by<b>e")), null, doc(h1("helle")));
    });

    test("can restore a list parent", () {
      _replace(
        doc(h1("hell<a>o"), "<b>"),
        doc(ol(li(p("on<a>e")), li(p("tw<b>o")))),
        doc(h1("helle"), ol(li(p("tw")))),
      );
    });

    test("can restore a list parent and join text after it", () {
      _replace(
        doc(h1("hell<a>o"), p("yo<b>u")),
        doc(ol(li(p("on<a>e")), li(p("tw<b>o")))),
        doc(h1("helle"), ol(li(p("twu")))),
      );
    });

    test("can insert into an empty block", () {
      _replace(
        doc(p("a"), p("<a>"), p("b")),
        doc(p("x<a>y<b>z")),
        doc(p("a"), p("y<a>"), p("b")),
      );
    });

    test("doesn't change the nesting of blocks after the selection", () {
      _replace(
        doc(p("one<a>"), p("two"), p("three")),
        doc(p("outside<a>"), blockquote(p("inside<b>"))),
        doc(p("one"), blockquote(p("inside")), p("two"), p("three")),
      );
    });

    test("can close a parent node", () {
      _replace(
        doc(blockquote(p("b<a>c"), p("d<b>e"), p("f"))),
        doc(blockquote(p("x<a>y")), p("after"), "<b>"),
        doc(blockquote(p("b<a>y")), p("after"), blockquote(p("<b>e"), p("f"))),
      );
    });

    test("accepts lopsided regions", () {
      _replace(
        doc(blockquote(p("b<a>c"), p("d<b>e"), p("f"))),
        doc(blockquote(p("x<a>y")), p("z<b>")),
        doc(blockquote(p("b<a>y")), p("z<b>e"), blockquote(p("f"))),
      );
    });

    test("can close nested parent nodes", () {
      _replace(
        doc(
          blockquote(
            blockquote(p("one"), p("tw<a>o"), p("t<b>hree<3>"), p("four<4>")),
          ),
        ),
        doc(ol(li(p("hello<a>world")), li(p("bye"))), p("ne<b>xt")),
        doc(
          blockquote(
            blockquote(
              p("one"),
              p("tw<a>world"),
              ol(li(p("bye"))),
              p("ne<b>hree<3>"),
              p("four<4>"),
            ),
          ),
        ),
      );
    });

    test("will close open nodes to the right", () {
      _replace(
        doc(p("x"), "<a>"),
        doc("<a>", ul(li(p("a")), li("<b>", p("b")))),
        doc(p("x"), ul(li(p("a")), li(p())), "<a>"),
      );
    });

    test("can delete the whole document", () {
      _replace(doc("<a>", h1("hi"), p("you"), "<b>"), null, doc(p()));
    });

    test("preserves an empty parent to the left", () {
      _replace(
        doc(blockquote("<a>", p("hi")), p("b<b>x")),
        doc(p("<a>hi<b>")),
        doc(blockquote(p("hix"))),
      );
    });

    test("drops an empty parent to the right", () {
      _replace(
        doc(p("x<a>hi"), blockquote(p("yy"), "<b>"), p("c")),
        doc(p("<a>hi<b>")),
        doc(p("xhi"), p("c")),
      );
    });

    test("drops an empty node at the start of the slice", () {
      _replace(
        doc(p("<a>x")),
        doc(blockquote(p("hi"), "<a>"), p("b<b>")),
        doc(p(), p("bx")),
      );
    });

    test("drops an empty node at the end of the slice", () {
      _replace(
        doc(p("<a>x")),
        doc(p("b<a>"), blockquote("<b>", p("hi"))),
        doc(p(), blockquote(p()), p("x")),
      );
    });

    test("does nothing when given an unfittable slice", () {
      _replace(
        p("<a>x"),
        Slice(Fragment.from([blockquote(), hr()]), 0, 0),
        p("x"),
      );
    });

    test("doesn't drop content when things only fit at the top level", () {
      _replace(
        doc(p("foo"), "<a>", p("bar<b>")),
        ol(li(p("<a>a")), li(p("b<b>"))),
        doc(p("foo"), p("a"), ol(li(p("b")))),
      );
    });

    test("preserves openEnd when top isn't placed", () {
      _replace(
        doc(ul(li(p("ab<a>cd")), li(p("ef<b>gh")))),
        doc(ul(li(p("ABCD")), li(p("EFGH")))).slice(5, 13, true),
        doc(ul(li(p("abCD")), li(p("EFgh")))),
      );
    });

    test("will auto-close a list item when it fits in a list", () {
      _replace(
        doc(ul(li(p("foo")), "<a>", li(p("bar")))),
        ul(li(p("a<a>bc")), li(p("de<b>f"))),
        doc(ul(li(p("foo")), li(p("bc")), li(p("de")), li(p("bar")))),
      );
    });

    test("finds the proper openEnd value when unwrapping a deep slice", () {
      _replace(
        doc("<a>", p(), "<b>"),
        doc(blockquote(blockquote(blockquote(p("hi"))))).slice(3, 6, true),
        doc(p("hi")),
      );
    });

    test("preserves marks on block nodes", () {
      final tr = Transform(
        _marksSchema.node("doc", null, [
          _marksSchema.node(
            "paragraph",
            null,
            [_marksSchema.text("hey")],
            [_marksSchema.mark("em")],
          ),
          _marksSchema.node(
            "paragraph",
            null,
            [_marksSchema.text("ok")],
            [_marksSchema.mark("strong")],
          ),
        ]),
      );
      tr.replace(2, 7, tr.doc.slice(2, 7));
      expect(eq(tr.doc, tr.before), isTrue);
    });

    test("preserves marks on open slice block nodes", () {
      final tr = Transform(
        _marksSchema.node("doc", null, [
          _marksSchema.node("paragraph", null, [_marksSchema.text("a")]),
        ]),
      );
      tr.replace(
        3,
        3,
        _marksSchema
            .node("doc", null, [
              _marksSchema.node(
                "paragraph",
                null,
                [_marksSchema.text("b")],
                [_marksSchema.mark("em")],
              ),
            ])
            .slice(1, 3),
      );
      expect(tr.doc.childCount, 2);
      expect(tr.doc.lastChild!.marks.length, 1);
    });

    test("can unwrap a paragraph when replacing into a strict schema", () {
      final tr = Transform(
        _hbDoc(_hbHeading("Head"), _hbBody(_hbParagraph("Content"))),
      );
      tr.replace(0, tr.doc.content.size, tr.doc.slice(7, 16));
      expect(
        eq(tr.doc, _hbDoc(_hbHeading("Content"), _hbBody(_hbParagraph()))),
        isTrue,
      );
    });

    test("can unwrap a body after a placed node", () {
      final tr = Transform(
        _hbDoc(_hbHeading("Head"), _hbBody(_hbParagraph("Content"))),
      );
      tr.replace(7, 7, tr.doc.slice(0, tr.doc.content.size));
      expect(
        eq(
          tr.doc,
          _hbDoc(
            _hbHeading("Head"),
            _hbBody(
              _hbHeading("Head"),
              _hbParagraph("Content"),
              _hbParagraph("Content"),
            ),
          ),
        ),
        isTrue,
      );
    });

    test(
      "can wrap a paragraph in a body, even when it's not the first node",
      () {
        final tr = Transform(
          _hbDoc(
            _hbHeading("Head"),
            _hbBody(_hbParagraph("One"), _hbParagraph("Two")),
          ),
        );
        tr.replace(0, tr.doc.content.size, tr.doc.slice(8, 16));
        expect(
          eq(tr.doc, _hbDoc(_hbHeading("One"), _hbBody(_hbParagraph("Two")))),
          isTrue,
        );
      },
    );

    test(
      "can split a fragment and place its children in different parents",
      () {
        final tr = Transform(
          _hbDoc(
            _hbHeading("Head"),
            _hbBody(_hbHeading("One"), _hbParagraph("Two")),
          ),
        );
        tr.replace(0, tr.doc.content.size, tr.doc.slice(7, 17));
        expect(
          eq(tr.doc, _hbDoc(_hbHeading("One"), _hbBody(_hbParagraph("Two")))),
          isTrue,
        );
      },
    );

    test("will insert filler nodes before a node when necessary", () {
      final tr = Transform(
        _hbDoc(_hbHeading("Head"), _hbBody(_hbParagraph("One"))),
      );
      tr.replace(0, tr.doc.content.size, tr.doc.slice(6, tr.doc.content.size));
      expect(
        eq(tr.doc, _hbDoc(_hbHeading(), _hbBody(_hbParagraph("One")))),
        isTrue,
      );
    });

    test("doesn't fail when moving text would solve an unsatisfied content constraint", () {
      final s = Schema(
        SchemaSpec(
          nodes: schema.spec.nodes.append(<String, NodeSpec>{
            "title": NodeSpec(content: "text*"),
            "doc": NodeSpec(content: "title? block*"),
          }),
        ),
      );
      final tr = Transform(
        s.node("doc", null, s.node("title", null, s.text("hi"))),
      );
      tr.replace(
        1,
        1,
        s
            .node("bullet_list", null, [
              s.node(
                "list_item",
                null,
                s.node("paragraph", null, s.text("one")),
              ),
              s.node(
                "list_item",
                null,
                s.node("paragraph", null, s.text("two")),
              ),
            ])
            .slice(2, 12),
      );
      expect(tr.steps.length, greaterThan(0));
    });

    test("doesn't fail when pasting a half-open slice with a title and a code block into an empty title", () {
      final s = Schema(
        SchemaSpec(
          nodes: schema.spec.nodes.append(<String, NodeSpec>{
            "title": NodeSpec(content: "text*"),
            "doc": NodeSpec(content: "title? block*"),
          }),
        ),
      );
      final tr = Transform(s.node("doc", null, [s.node("title", null, [])]));
      tr.replace(
        1,
        1,
        s
            .node("doc", null, [
              s.node("title", null, s.text("title")),
              s.node("code_block", null, s.text("two")),
            ])
            .slice(1),
      );
      expect(tr.steps.length, greaterThan(0));
    });

    test("doesn't fail when pasting a half-open slice with a heading and a code block into an empty title", () {
      final s = Schema(
        SchemaSpec(
          nodes: schema.spec.nodes.append(<String, NodeSpec>{
            "title": NodeSpec(content: "text*"),
            "doc": NodeSpec(content: "title? block*"),
          }),
        ),
      );
      final tr = Transform(s.node("doc", null, [s.node("title")]));
      tr.replace(
        1,
        1,
        s
            .node("doc", null, [
              s.node("heading", {"level": 1}, [s.text("heading")]),
              s.node("code_block", null, [s.text("code")]),
            ])
            .slice(1),
      );
      expect(tr.steps.length, greaterThan(0));
    });

    test("can handle replacing in nodes with fixed content", () {
      final s = Schema(
        SchemaSpec(
          nodes: <String, NodeSpec>{
            "doc": NodeSpec(content: "block+"),
            "a": NodeSpec(content: "inline*"),
            "b": NodeSpec(content: "inline*"),
            "block": NodeSpec(content: "a b"),
            "text": NodeSpec(group: "inline"),
          },
        ),
      );

      final document = s.node("doc", null, [
        s.node("block", null, [
          s.node("a", null, [s.text("aa")]),
          s.node("b", null, [s.text("bb")]),
        ]),
      ]);
      final from = 3;
      final to = document.content.size;
      expect(
        eq(
          Transform(document).replace(from, to, document.slice(from, to)).doc,
          document,
        ),
        isTrue,
      );
    });

    test("keeps isolating nodes together", () {
      final s = Schema(
        SchemaSpec(
          nodes: schema.spec.nodes.append(<String, NodeSpec>{
            "iso": NodeSpec(group: "block", content: "block+", isolating: true),
          }),
        ),
      );
      final document = s.node("doc", null, [
        s.node("paragraph", null, [s.text("one")]),
      ]);
      final iso = Fragment.from(
        s.node("iso", null, [s.node("paragraph", null, s.text("two"))]),
      );
      expect(
        eq(
          Transform(document).replace(2, 3, Slice(iso, 2, 0)).doc,
          s.node("doc", null, [
            s.node("paragraph", null, [s.text("o")]),
            s.node("iso", null, [s.node("paragraph", null, s.text("two"))]),
            s.node("paragraph", null, [s.text("e")]),
          ]),
        ),
        isTrue,
      );
      expect(
        eq(
          Transform(document).replace(2, 3, Slice(iso, 2, 2)).doc,
          s.node("doc", null, [
            s.node("paragraph", null, [s.text("otwoe")]),
          ]),
        ),
        isTrue,
      );
    });
  });

  group("Transform > replaceRange >", () {
    test("replaces inline content", () {
      _replaceRange(
        doc(p("foo<a>b<b>ar")),
        p("<a>xx<b>"),
        doc(p("foo<a>xx<b>ar")),
      );
    });

    test("replaces an empty paragraph with a heading", () {
      _replaceRange(doc(p("<a>")), doc(h1("<a>text<b>")), doc(h1("text")));
    });

    test("replaces a fully selected paragraph with a heading", () {
      _replaceRange(
        doc(p("<a>abc<b>")),
        doc(h1("<a>text<b>")),
        doc(h1("text")),
      );
    });

    test("recreates a list when overwriting a paragraph", () {
      _replaceRange(
        doc(p("<a>")),
        doc(ul(li(p("<a>foobar<b>")))),
        doc(ul(li(p("foobar")))),
      );
    });

    test("drops context when it doesn't fit", () {
      _replaceRange(
        doc(ul(li(p("<a>")), li(p("b")))),
        doc(h1("<a>h<b>")),
        doc(ul(li(p("h<a>")), li(p("b")))),
      );
    });

    test("can replace a node when endpoints are in different children", () {
      _replaceRange(
        doc(
          p("a"),
          ul(li(p("<a>b")), li(p("c"), blockquote(p("d<b>")))),
          p("e"),
        ),
        doc(h1("<a>x<b>")),
        doc(p("a"), h1("x"), p("e")),
      );
    });

    test(
      "keeps defining context when inserting at the start of a textblock",
      () {
        _replaceRange(
          doc(p("<a>foo")),
          doc(ul(li(p("<a>one")), li(p("two<b>")))),
          doc(ul(li(p("one")), li(p("twofoo")))),
        );
      },
    );

    test(
      "keeps defining context when it doesn't matches the parent markup",
      () {
        final spec = NodeSpec(
          content: "block+",
          group: "block",
          definingForContent: true,
          definingAsContext: false,
          attrs: {"color": const AttributeSpec(defaultValue: "black")},
        );
        final s = Schema(
          SchemaSpec(
            nodes: schema.spec.nodes.update("blockquote", spec),
            marks: schema.spec.marks,
          ),
        );
        final b1 = NodeBuilder(s.nodes["blockquote"]!, const <String, Object?>{
          "color": "#100",
        });
        final b2 = NodeBuilder(s.nodes["blockquote"]!, const <String, Object?>{
          "color": "#200",
        });
        final b3 = NodeBuilder(s.nodes["blockquote"]!, const <String, Object?>{
          "color": "#300",
        });
        final b4 = NodeBuilder(s.nodes["blockquote"]!, const <String, Object?>{
          "color": "#400",
        });
        final b5 = NodeBuilder(s.nodes["blockquote"]!, const <String, Object?>{
          "color": "#500",
        });
        final b6 = NodeBuilder(s.nodes["blockquote"]!, const <String, Object?>{
          "color": "#600",
        });
        final p = NodeBuilder(s.nodes["paragraph"]!, const <String, Object?>{});
        final localDoc = NodeBuilder(
          s.nodes["doc"]!,
          const <String, Object?>{},
        );

        final source = localDoc(b1(p("<a>b1")), b2(p("b2<b>")));

        final before1 = [b3(p("b3")), b4(p("<a>"))];
        final before2 = [b5(p("b5"), before1[0], before1[1])];
        final before3 = [b6(p("b6"), before2[0])];

        final expect1 = [b3(p("b3")), b1(p("b1")), b2(p("b2"))];
        final expect2 = [b5(p("b5"), expect1[0], expect1[1], expect1[2])];
        final expect3 = [b6(p("b6"), expect2[0])];

        _replaceRange(
          localDoc(before1[0], before1[1]),
          source,
          localDoc(expect1[0], expect1[1], expect1[2]),
        );
        _replaceRange(localDoc(before2[0]), source, localDoc(expect2[0]));
        _replaceRange(localDoc(before3[0]), source, localDoc(expect3[0]));
      },
    );

    test("drops defining context when it matches the parent structure", () {
      _replaceRange(
        doc(blockquote(p("<a>"))),
        doc(blockquote(p("<a>one<b>"))),
        doc(blockquote(p("one"))),
      );
    });

    test("drops defining context when it matches the parent structure in a nested context", () {
      _replaceRange(
        doc(ul(li(p("list1"), blockquote(p("<a>"))))),
        doc(blockquote(p("<a>one<b>"))),
        doc(ul(li(p("list1"), blockquote(p("one"))))),
      );
    });

    test("drops defining context when it matches the parent structure in a deep nested context", () {
      _replaceRange(
        doc(ul(li(p("list1"), ul(li(p("list2"), blockquote(p("<a>"))))))),
        doc(blockquote(p("<a>one<b>"))),
        doc(ul(li(p("list1"), ul(li(p("list2"), blockquote(p("one"))))))),
      );
    });

    test("closes open nodes at the start", () {
      _replaceRange(
        doc("<a>", p("abc"), "<b>"),
        doc(ul(li("<a>")), p("def"), "<b>"),
        doc(ul(li(p())), p("def")),
      );
    });
  });

  group("Transform > replaceRangeWith >", () {
    test("can insert an inline node", () {
      _replaceRangeWith(doc(p("fo<a>o")), img(), doc(p("fo", img(), "<a>o")));
    });

    test("can replace content with an inline node", () {
      _replaceRangeWith(doc(p("<a>fo<b>o")), img(), doc(p("<a>", img(), "o")));
    });

    test("can replace a block node with an inline node", () {
      _replaceRangeWith(
        doc("<a>", blockquote(p("a")), "<b>"),
        img(),
        doc(p(img)),
      );
    });

    test("can replace a block node with a block node", () {
      _replaceRangeWith(doc("<a>", blockquote(p("a")), "<b>"), hr(), doc(hr()));
    });

    test("can insert a block quote in the middle of text", () {
      _replaceRangeWith(
        doc(p("foo<a>bar")),
        hr(),
        doc(p("foo"), hr(), p("bar")),
      );
    });

    test("can replace empty parents with a block node", () {
      _replaceRangeWith(doc(blockquote(p("<a>"))), hr(), doc(blockquote(hr())));
    });

    test("can move an inserted block forward out of parent nodes", () {
      _replaceRangeWith(doc(h1("foo<a>")), hr(), doc(h1("foo"), hr()));
    });

    test("can move an inserted block backward out of parent nodes", () {
      _replaceRangeWith(
        doc(p("a"), blockquote(p("<a>b"))),
        hr(),
        doc(p("a"), blockquote(hr, p("b"))),
      );
    });
  });

  group("Transform > deleteRange >", () {
    test("deletes the given range", () {
      _deleteRange(doc(p("fo<a>o"), p("b<b>ar")), doc(p("fo<a><b>ar")));
    });

    test("deletes empty parent nodes", () {
      _deleteRange(
        doc(blockquote(ul(li("<a>", p("foo"), "<b>")), p("x"))),
        doc(blockquote("<a><b>", p("x"))),
      );
    });

    test("doesn't delete parent nodes that can be empty", () {
      _deleteRange(doc(p("<a>foo<b>")), doc(p("<a><b>")));
    });

    test("is okay with deleting empty ranges", () {
      _deleteRange(doc(p("<a><b>")), doc(p("<a><b>")));
    });

    test("will delete a whole covered node even if selection ends are in different nodes", () {
      _deleteRange(
        doc(ul(li(p("<a>foo")), li(p("bar<b>"))), p("hi")),
        doc(p("hi")),
      );
    });

    test("leaves wrapping textblock when deleting all text in it", () {
      _deleteRange(doc(p("a"), p("<a>b<b>")), doc(p("a"), p()));
    });

    test("expands to cover the whole parent node", () {
      _deleteRange(
        doc(p("a"), blockquote(blockquote(p("<a>foo")), p("bar<b>")), p("b")),
        doc(p("a"), p("b")),
      );
    });

    test("expands to cover the whole document", () {
      _deleteRange(
        doc(h1("<a>foo"), p("bar"), blockquote(p("baz<b>"))),
        doc(p()),
      );
    });

    test("doesn't expand beyond same-depth textblocks", () {
      _deleteRange(doc(h1("<a>foo"), p("bar"), p("baz<b>")), doc(h1()));
    });

    test(
      "deletes the open token when deleting from start to past end of block",
      () {
        _deleteRange(doc(h1("<a>foo"), p("b<b>ar")), doc(p("ar")));
      },
    );

    test("doesn't delete the open token when the range end is at end of its own block", () {
      _deleteRange(
        doc(p("one"), h1("<a>two"), blockquote(p("three<b>")), p("four")),
        doc(p("one"), h1(), p("four")),
      );
    });

    test("doesn't break text-joining by inappropriate expansion", () {
      _deleteRange(
        doc(ol(li(p("<a>One"), ol(li(p("Tw<b>o")))))),
        doc(ol(li(p("o")))),
      );
    });

    test("will delete entire blocks when deleting from the start of one textblock to another", () {
      _deleteRange(
        doc(
          blockquote(ol(li(p("a")), li(p("<a>b")), li(p("c")))),
          p("x"),
          p("<b>y"),
        ),
        doc(blockquote(ol(li(p("a")))), p("y")),
      );
    });
  });

  group("Transform > addNodeMark >", () {
    test("adds a mark", () {
      _addNodeMark(
        doc(p("<a>", img())),
        schema.mark("em"),
        doc(p("<a>", em(img()))),
      );
    });

    test("doesn't duplicate a mark", () {
      _addNodeMark(
        doc(p("<a>", em(img()))),
        schema.mark("em"),
        doc(p("<a>", em(img()))),
      );
    });

    test("replaces a mark", () {
      _addNodeMark(
        doc(p("<a>", a(img()))),
        schema.mark("link", {"href": "x"}),
        doc(p("<a>", a({"href": "x"}, img()))),
      );
    });
  });

  group("Transform > removeNodeMark >", () {
    test("removes a mark", () {
      _removeNodeMark(
        doc(p("<a>", em(img()))),
        schema.mark("em"),
        doc(p("<a>", img())),
      );
    });

    test("doesn't do anything when there is no mark", () {
      _removeNodeMark(
        doc(p("<a>", img())),
        schema.mark("em"),
        doc(p("<a>", img())),
      );
    });

    test("can remove a mark from multiple marks", () {
      _removeNodeMark(
        doc(p("<a>", em(a(img())))),
        schema.mark("em"),
        doc(p("<a>", a(img()))),
      );
    });

    test("can remove multiple instances of a mark type", () {
      final s = Schema(
        SchemaSpec(
          nodes: <String, NodeSpec>{
            "doc": NodeSpec(content: "p+", marks: "comment"),
            "p": NodeSpec(content: "text*"),
            "text": NodeSpec(),
          },
          marks: <String, MarkSpec>{
            "comment": MarkSpec(
              excludes: "",
              attrs: {"id": const AttributeSpec()},
            ),
          },
        ),
      );
      final document = s.node("doc", null, [
        s.node(
          "p",
          null,
          [s.text("abc")],
          [
            s.mark("comment", {"id": 1}),
            s.mark("comment", {"id": 2}),
          ],
        ),
      ]);
      testTransform(
        Transform(document).removeNodeMark(0, s.marks["comment"]!),
        s.node("doc", null, [
          s.node("p", null, [s.text("abc")]),
        ]),
      );
    });
  });

  group("Transform > setNodeAttribute >", () {
    test("sets an attribute", () {
      _setNodeAttribute(doc("<a>", h1("a")), "level", 2, doc("<a>", h2("a")));
    });
  });

  group("Transform > setDocAttribute >", () {
    test("sets an attribute", () {
      _setDocAttribute(
        _docAttrDoc(),
        "meta",
        "hello",
        _docAttrDoc({"meta": "hello"}),
      );
    });
  });

  group("Transform > changedRange >", () {
    test("returns null when there are no changes", () {
      final tr = Transform(doc(p("hello")));
      expect(_changedRange(tr), isNull);
      tr.addMark(1, 3, schema.mark("strong"));
      expect(_changedRange(tr), isNull);
    });

    test("returns a range when something changed", () {
      final tr = Transform(doc(p("ab"))).insert(3, schema.text("c"));
      expect(_changedRange(tr), "3-4");
    });

    test("can handle multiple steps that affect each other's position", () {
      final tr = Transform(doc(p("ab")))
          .insert(3, schema.text("c"))
          .insert(2, schema.text("d"))
          .insert(1, schema.text("e"));
      expect(_changedRange(tr), "1-6");
    });

    test("properly adjusts for deletions before an earlier step", () {
      final tr = Transform(doc(p("abcde")))
          .insert(6, schema.text("f"))
          .delete(1, 4);
      expect(_changedRange(tr), "1-4");
    });
  });
}

void _addMark(Node document, Mark mark, Node expected) {
  testTransform(
    Transform(document).addMark(_tag(document, "a"), _tag(document, "b"), mark),
    expected,
  );
}

void _removeMark(Node document, Object? mark, Node expected) {
  testTransform(
    Transform(document)
        .removeMark(_tag(document, "a"), _tag(document, "b"), mark),
    expected,
  );
}

void _insert(Node document, Object nodes, Node expected) {
  testTransform(
    Transform(document).insert(_tag(document, "a"), nodes),
    expected,
  );
}

void _delete(Node document, Node expected) {
  testTransform(
    Transform(document).delete(_tag(document, "a"), _tag(document, "b")),
    expected,
  );
}

void _join(Node document, Node expected) {
  testTransform(Transform(document).join(_tag(document, "a")), expected);
}

void _split(
  Node document,
  Object expected, [
  int? depth,
  List<({NodeType type, Attrs? attrs})>? typesAfter,
]) {
  if (expected == "fail") {
    expect(
      () =>
          Transform(document)
              .split(_tag(document, "a"), depth ?? 1, typesAfter),
      throwsA(anything),
    );
  } else {
    testTransform(
      Transform(document).split(_tag(document, "a"), depth ?? 1, typesAfter),
      expected as Node,
    );
  }
}

void _lift(Node document, Node expected) {
  final range = document
      .resolve(_tag(document, "a"))
      .blockRange(
        document.resolve(_tagOrNull(document, "b") ?? _tag(document, "a")),
      );
  testTransform(Transform(document).lift(range!, liftTarget(range)!), expected);
}

void _wrap(Node document, Node expected, String type, [Attrs? attrs]) {
  final range = document
      .resolve(_tag(document, "a"))
      .blockRange(
        document.resolve(_tagOrNull(document, "b") ?? _tag(document, "a")),
      );
  testTransform(
    Transform(document)
        .wrap(range!, findWrapping(range, schema.nodes[type]!, attrs)!),
    expected,
  );
}

void _setBlockType(
  Node document,
  Node expected,
  String nodeType, [
  Object? attrs,
]) {
  testTransform(
    Transform(document).setBlockType(
      _tag(document, "a"),
      _tagOrNull(document, "b") ?? _tag(document, "a"),
      document.type.schema.nodes[nodeType]!,
      attrs,
    ),
    expected,
  );
}

void _setNodeMarkup(Node document, Node expected, String type, [Attrs? attrs]) {
  testTransform(
    Transform(document)
        .setNodeMarkup(_tag(document, "a"), schema.nodes[type], attrs),
    expected,
  );
}

void _replace(Node document, Object? source, Node expected) {
  final Slice slice;
  if (source == null) {
    slice = Slice.empty;
  } else if (source is Slice) {
    slice = source;
  } else {
    final node = source as Node;
    slice = node.slice(_tag(node, "a"), _tag(node, "b"));
  }
  testTransform(
    Transform(document).replace(
      _tag(document, "a"),
      _tagOrNull(document, "b") ?? _tag(document, "a"),
      slice,
    ),
    expected,
  );
}

void _replaceRange(Node document, Node source, Node expected) {
  final slice = source.slice(_tag(source, "a"), _tag(source, "b"), true);
  testTransform(
    Transform(document).replaceRange(
      _tag(document, "a"),
      _tagOrNull(document, "b") ?? _tag(document, "a"),
      slice,
    ),
    expected,
  );
}

void _replaceRangeWith(Node document, Node node, Node expected) {
  testTransform(
    Transform(document).replaceRangeWith(
      _tag(document, "a"),
      _tagOrNull(document, "b") ?? _tag(document, "a"),
      node,
    ),
    expected,
  );
}

void _deleteRange(Node document, Node expected) {
  testTransform(
    Transform(document).deleteRange(
      _tag(document, "a"),
      _tagOrNull(document, "b") ?? _tag(document, "a"),
    ),
    expected,
  );
}

void _addNodeMark(Node document, Mark mark, Node expected) {
  testTransform(
    Transform(document).addNodeMark(_tag(document, "a"), mark),
    expected,
  );
}

void _removeNodeMark(Node document, Object mark, Node expected) {
  testTransform(
    Transform(document).removeNodeMark(_tag(document, "a"), mark),
    expected,
  );
}

void _setNodeAttribute(
  Node document,
  String attr,
  Object? value,
  Node expected,
) {
  testTransform(
    Transform(document).setNodeAttribute(_tag(document, "a"), attr, value),
    expected,
  );
}

void _setDocAttribute(
  Node document,
  String attr,
  Object? value,
  Node expected,
) {
  testTransform(Transform(document).setDocAttribute(attr, value), expected);
}

String? _changedRange(Transform tr) {
  final change = tr.changedRange();
  return change == null ? null : "${change.from}-${change.to}";
}

int _tag(Node node, String name) {
  final value = _tagOrNull(node, name);
  if (value == null) {
    throw StateError("Missing tag $name on $node");
  }
  return value;
}

int? _tagOrNull(Node node, String name) => node.tag[name];

// A schema that allows marks on top-level block nodes.
final Schema _marksSchema = Schema(
  SchemaSpec(
    nodes: schema.spec.nodes.update(
      "doc",
      NodeSpec(content: "block+", marks: "_"),
    ),
    marks: schema.spec.marks,
  ),
);

// A schema that enforces a heading and a body at the top level.
final Schema _headingBodySchema = Schema(
  SchemaSpec(
    nodes: schema.spec.nodes.append(<String, NodeSpec>{
      "doc": NodeSpec(content: "heading body"),
      "body": NodeSpec(content: "block+"),
    }),
  ),
);

final NodeBuilder _hbDoc = NodeBuilder(
  _headingBodySchema.nodes["doc"]!,
  const <String, Object?>{},
);
final NodeBuilder _hbParagraph = NodeBuilder(
  _headingBodySchema.nodes["paragraph"]!,
  const <String, Object?>{},
);
final NodeBuilder _hbBody = NodeBuilder(
  _headingBodySchema.nodes["body"]!,
  const <String, Object?>{},
);
final NodeBuilder _hbHeading = NodeBuilder(
  _headingBodySchema.nodes["heading"]!,
  const <String, Object?>{"level": 1},
);

// A schema whose hard_break acts as a linebreak replacement.
final Schema _linebreakSchema = Schema(
  SchemaSpec(
    nodes: schema.spec.nodes.update("hard_break", _linebreakHardBreakSpec()),
  ),
);

NodeSpec _linebreakHardBreakSpec() {
  final original = schema.spec.nodes.get("hard_break")!;
  return NodeSpec(
    content: original.content,
    marks: original.marks,
    group: original.group,
    inline: original.inline,
    atom: original.atom,
    attrs: original.attrs,
    selectable: original.selectable,
    draggable: original.draggable,
    code: original.code,
    whitespace: original.whitespace,
    definingAsContext: original.definingAsContext,
    definingForContent: original.definingForContent,
    defining: original.defining,
    isolating: original.isolating,
    toDebugString: original.toDebugString,
    leafText: original.leafText,
    linebreakReplacement: true,
  );
}

final NodeBuilder _lbDoc = NodeBuilder(
  _linebreakSchema.nodes["doc"]!,
  const <String, Object?>{},
);
final NodeBuilder _lbParagraph = NodeBuilder(
  _linebreakSchema.nodes["paragraph"]!,
  const <String, Object?>{},
);
final NodeBuilder _lbPre = NodeBuilder(
  _linebreakSchema.nodes["code_block"]!,
  const <String, Object?>{},
);
final NodeBuilder _lbBr = NodeBuilder(
  _linebreakSchema.nodes["hard_break"]!,
  const <String, Object?>{},
);
final NodeBuilder _lbHeading1 = NodeBuilder(
  _linebreakSchema.nodes["heading"]!,
  const <String, Object?>{"level": 1},
);

// A schema whose top node carries a settable `meta` attribute.
final Schema _docAttrSchema = Schema(
  SchemaSpec(
    nodes: <String, NodeSpec>{
      "doc": NodeSpec(
        content: "text*",
        attrs: {"meta": const AttributeSpec(defaultValue: null)},
      ),
      "text": NodeSpec(),
    },
  ),
);

final NodeBuilder _docAttrDoc = NodeBuilder(
  _docAttrSchema.nodes["doc"]!,
  const <String, Object?>{},
);
