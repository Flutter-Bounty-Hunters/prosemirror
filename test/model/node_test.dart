import 'dart:convert';

import 'package:prosemirror/prosemirror.dart';
import 'package:test/test.dart';

import 'package:prosemirror/test_builder.dart';

void main() {
  group("Node > toString >", () {
    test("nests", () {
      expect(
        document(ul(li(p("hey"), p()), li(p("foo")))).toString(),
        'doc(bullet_list(list_item(paragraph("hey"), paragraph), list_item(paragraph("foo"))))',
      );
    });

    test("shows inline children", () {
      expect(document(p("foo", img(), br(), "bar")).toString(), 'doc(paragraph("foo", image, hard_break, "bar"))');
    });

    test("shows marks", () {
      expect(
        document(p("foo", em("bar", strong("quux")), code("baz"))).toString(),
        'doc(paragraph("foo", em("bar"), em(strong("quux")), code("baz")))',
      );
    });
  });

  group("Node > cut >", () {
    test("extracts a full block", () {
      _cut(document(p("foo"), "<a>", p("bar"), "<b>", p("baz")), document(p("bar")));
    });

    test("cuts text", () {
      _cut(document(p("0"), p("foo<a>bar<b>baz"), p("2")), document(p("bar")));
    });

    test("cuts deeply", () {
      _cut(
        document(blockquote(ul(li(p("a"), p("b<a>c")), li(p("d")), "<b>", li(p("e"))), p("3"))),
        document(blockquote(ul(li(p("c")), li(p("d"))))),
      );
    });

    test("works from the left", () {
      _cut(document(blockquote(p("foo<b>bar"))), document(blockquote(p("foo"))));
    });

    test("works to the right", () {
      _cut(document(blockquote(p("foo<a>bar"))), document(blockquote(p("bar"))));
    });

    test("preserves marks", () {
      _cut(
        document(p("foo", em("ba<a>r", img(), strong("baz"), br()), "qu<b>ux", code("xyz"))),
        document(p(em("r", img(), strong("baz"), br()), "qu")),
      );
    });
  });

  group("Node > nodesBetween >", () {
    test("iterates over text", () {
      _between(document(p("foo<a>bar<b>baz")), ["paragraph", "foobarbaz"]);
    });

    test("descends multiple levels", () {
      _between(document(blockquote(ul(li(p("f<a>oo")), p("b"), "<b>"), p("c"))), [
        "blockquote",
        "bullet_list",
        "list_item",
        "paragraph",
        "foo",
        "paragraph",
        "b",
      ]);
    });

    test("iterates over inline nodes", () {
      _between(document(p(em("x"), "f<a>oo", em("bar", img(), strong("baz"), br()), "quux", code("xy<b>z"))), [
        "paragraph",
        "foo",
        "bar",
        "image",
        "baz",
        "hard_break",
        "quux",
        "xyz",
      ]);
    });
  });

  group("Node > textBetween >", () {
    test("works when passing a custom function as leafText", () {
      final d = document(p("foo", img(), br()));
      expect(
        d.textBetween(0, d.content.size, '', (node) {
          if (node.type.name == 'image') {
            return '<image>';
          }
          if (node.type.name == 'hard_break') {
            return '<break>';
          }
          return "";
        }),
        'foo<image><break>',
      );
    });

    test("works with leafText", () {
      final d = _customContactDoc();
      expect(d.textBetween(0, d.content.size), 'Hello Alice <alice@example.com>');
    });

    test("should ignore leafText when passing a custom leafText", () {
      final d = _customContactDoc();
      expect(d.textBetween(0, d.content.size, '', '<anonymous>'), 'Hello <anonymous>');
    });

    test("adds block separator around empty paragraphs", () {
      expect(document(p("one"), p(), p("two")).textBetween(0, 12, "\n"), "one\n\ntwo");
    });

    test("adds block separator around leaf nodes", () {
      expect(document(p("one"), hr(), hr(), p("two")).textBetween(0, 12, "\n", "---"), "one\n---\n---\ntwo");
    });

    test("doesn't add block separator around non-rendered leaf nodes", () {
      expect(document(p("one"), hr(), hr(), p("two")).textBetween(0, 12, "\n"), "one\ntwo");
    });
  });

  group("Node > textContent >", () {
    test("works on a whole doc", () {
      expect(document(p("foo")).textContent, "foo");
    });

    test("works on a text node", () {
      expect(schema.text("foo").textContent, "foo");
    });

    test("works on a nested element", () {
      expect(document(ul(li(p("hi")), li(p(em("a"), "b")))).textContent, "hiab");
    });
  });

  group("Node > check >", () {
    test("notices invalid content", () {
      expect(() => document(li("x")).check(), throwsA(_matches(r'Invalid content for node doc')));
    });

    test("notices marks in wrong places", () {
      expect(
        () => document(schema.nodes["paragraph"]!.create(null, <Node>[], [schema.marks["em"]!.create()])).check(),
        throwsA(_matches(r'Invalid content for node doc')),
      );
    });

    test("notices incorrect sets of marks", () {
      expect(
        () => schema.text("a", [schema.marks["em"]!.create(), schema.marks["em"]!.create()]).check(),
        throwsA(_matches(r'Invalid collection of marks')),
      );
    });

    test("notices wrong attribute types", () {
      expect(
        () => schema.nodes["image"]!.create({"src": true}).check(),
        throwsA(_matches(r'Expected value of type string for attribute src on type image, got boolean')),
      );
    });
  });

  group("Node > from >", () {
    test("wraps a single node", () {
      _from(schema.node("paragraph"), document(p()));
    });

    test("wraps an array", () {
      _from([schema.node("hard_break"), schema.text("foo")], p(br, "foo"));
    });

    test("preserves a fragment", () {
      _from(document(p("foo")).content, document(p("foo")));
    });

    test("accepts null", () {
      _from(null, p());
    });

    test("joins adjacent text", () {
      _from([schema.text("a"), schema.text("b")], p("ab"));
    });
  });

  group("Node > toJSON >", () {
    test("can serialize a simple node", () {
      _roundTrip(document(p("foo")));
    });

    test("can serialize marks", () {
      _roundTrip(document(p("foo", em("bar", strong("baz")), " ", a("x"))));
    });

    test("can serialize inline leaf nodes", () {
      _roundTrip(document(p("foo", em(img(), "bar"))));
    });

    test("can serialize block leaf nodes", () {
      _roundTrip(document(p("a"), hr(), p("b"), p()));
    });

    test("can serialize nested nodes", () {
      _roundTrip(document(blockquote(ul(li(p("a"), p("b")), li(p(img()))), p("c")), p("d")));
    });
  });

  group("Node > default toString >", () {
    test("has the default toString method for text", () {
      expect(schema.text("hello").toString(), '"hello"');
    });

    test("has the default toString method for a leaf node", () {
      expect(br().toString(), "hard_break");
    });

    test("can be redefined from NodeSpec by specifying a toDebugString method", () {
      expect(_customSchema.text("hello").toString(), "custom_text");
    });

    test("is respected by Fragment", () {
      expect(
        Fragment.fromArray([
          _customSchema.text("hello"),
          _customSchema.nodes["hard_break"]!.createChecked(),
          _customSchema.text("world"),
        ]).toString(),
        "<custom_text, custom_hard_break, custom_text>",
      );
    });
  });

  group("Node > leafText >", () {
    test("customizes the textContent of a leaf node", () {
      final contact = _customSchema.nodes["contact"]!.createChecked({"name": "Bob", "email": "bob@example.com"});
      final paragraph = _customSchema.nodes["paragraph"]!.createChecked({}, [_customSchema.text('Hello '), contact]);

      expect(contact.textContent, "Bob <bob@example.com>");
      expect(paragraph.textContent, "Hello Bob <bob@example.com>");
    });
  });
}

void _cut(Node document, Node expected) {
  expect(document.cut(document.tag["a"] ?? 0, document.tag["b"]).eq(expected), isTrue);
}

void _between(Node document, List<String> nodeNames) {
  var index = 0;
  document.nodesBetween(document.tag["a"]!, document.tag["b"]!, (node, pos, parent, childIndex) {
    if (index == nodeNames.length) {
      fail("More nodes iterated than listed (${node.type.name})");
    }
    final compare = node.isText ? node.text! : node.type.name;
    if (compare != nodeNames[index++]) {
      fail("Expected ${jsonEncode(nodeNames[index - 1])}, got ${jsonEncode(compare)}");
    }
    if (!node.isText && !identical(document.nodeAt(pos), node)) {
      fail("Pos $pos does not point at node $node ${document.nodeAt(pos)}");
    }
    return null;
  });
}

void _from(Object? argument, Node expected) {
  expect(expected.copy(Fragment.from(argument)).eq(expected), isTrue);
}

void _roundTrip(Node document) {
  expect(schema.nodeFromJSON(document.toJSON()).eq(document), isTrue);
}

Node _customContactDoc() {
  return _customSchema.nodes["doc"]!.createChecked({}, [
    _customSchema.nodes["paragraph"]!.createChecked({}, [
      _customSchema.text("Hello "),
      _customSchema.nodes["contact"]!.createChecked({"name": "Alice", "email": "alice@example.com"}),
    ]),
  ]);
}

Matcher _matches(String pattern) {
  return predicate((error) => RegExp(pattern).hasMatch(error.toString()));
}

/// A small custom schema used to exercise `toDebugString` and `leafText`.
final Schema _customSchema = Schema(
  SchemaSpec(
    nodes: {
      "doc": NodeSpec(content: "paragraph+"),
      "paragraph": NodeSpec(content: "(text|contact)*"),
      "text": NodeSpec(toDebugString: (node) => "custom_text"),
      "contact": NodeSpec(
        inline: true,
        attrs: {"name": const AttributeSpec(), "email": const AttributeSpec()},
        leafText: (node) => "${node.attrs["name"]} <${node.attrs["email"]}>",
      ),
      "hard_break": NodeSpec(toDebugString: (node) => "custom_hard_break"),
    },
  ),
);
