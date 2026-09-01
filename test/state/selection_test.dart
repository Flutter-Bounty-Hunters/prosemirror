/// Port of `prosemirror-state`'s `test/test-selection.ts`.
library;

import 'package:prosemirror/prosemirror.dart';
import 'package:test/test.dart';

import 'package:prosemirror/test_builder.dart';

import 'support/state_test_helpers.dart';

void main() {
  group("Selection >", () {
    test("should follow changes", () {
      final state = TestState(doc: document(p("hi")), schema: schema);
      state.apply(state.tr.insertText("xy", 1));
      expect(state.selection.head, 3);
      expect(state.selection.anchor, 3);
      state.apply(state.tr.insertText("zq", 1));
      expect(state.selection.head, 5);
      expect(state.selection.anchor, 5);
      state.apply(state.tr.insertText("uv", 7));
      expect(state.selection.head, 5);
      expect(state.selection.anchor, 5);
    });

    test("should move after inserted content", () {
      final state = TestState(doc: document(p("hi")), schema: schema);
      state.textSel(2, 3);
      state.apply(state.tr.insertText("o"));
      expect(state.selection.head, 3);
      expect(state.selection.anchor, 3);
    });

    test("moves after an inserted leaf node", () {
      final state = TestState(doc: document(p("foobar")), schema: schema);
      state.textSel(4);
      state.apply(state.tr.replaceSelectionWith(schema.node("horizontal_rule")));
      expect(eq(state.doc, document(p("foo"), hr(), p("bar"))), isTrue);
      expect(state.selection.head, 7);
      state.textSel(10);
      state.apply(state.tr.replaceSelectionWith(schema.node("horizontal_rule")));
      expect(eq(state.doc, document(p("foo"), hr(), p("bar"), hr())), isTrue);
      expect(state.selection.from, 11);
    });

    test("allows typing over a leaf node", () {
      final state = TestState(doc: document(p("a"), "<a>", hr(), p("b")), schema: schema);
      state.nodeSel(3);
      state.apply(state.tr.replaceSelectionWith(schema.text("x")));
      expect(eq(state.doc, document(p("a"), p("x"), p("b"))), isTrue);
      expect(state.selection.head, 5);
      expect(state.selection.anchor, 5);
    });

    test("allows deleting a selected block", () {
      final state = TestState(doc: document(p("foo"), ul(li(p("bar")), li(p("baz")), li(p("quux")))), schema: schema);
      state.nodeSel(0);
      state.deleteSelection();
      expect(eq(state.doc, document(ul(li(p("bar")), li(p("baz")), li(p("quux"))))), isTrue);
      expect(state.selection.head, 3);
      state.nodeSel(2);
      state.deleteSelection();
      expect(eq(state.doc, document(ul(li(p("baz")), li(p("quux"))))), isTrue);
      expect(state.selection.head, 3);
      state.nodeSel(9);
      state.deleteSelection();
      expect(eq(state.doc, document(ul(li(p("baz"))))), isTrue);
      expect(state.selection.head, 6);
      state.nodeSel(0);
      state.deleteSelection();
      expect(eq(state.doc, document(p())), isTrue);
    });

    test("preserves the marks of a deleted selection", () {
      final state = TestState(doc: document(p("foo", em("<a>bar<b>"), "baz")));
      state.deleteSelection();
      expect(state.state.storedMarks!.length, 1);
    });

    test("doesn't preserve non-inclusive marks of a deleted selection", () {
      final state = TestState(doc: document(p("foo", a(em("<a>bar<b>")), "baz")));
      state.deleteSelection();
      expect(state.state.storedMarks!.length, 1);
    });

    test("doesn't preserve marks when deleting a selection at the end of a block", () {
      final state = TestState(doc: document(p("foo", em("bar<a>")), p("b<b>az")));
      state.deleteSelection();
      expect(state.state.storedMarks, isNull);
    });

    test("drops non-inclusive marks at the end of a deleted span when appropriate", () {
      final state = TestState(doc: document(p("foo", a("ba", em("<a>r<b>")), "baz")));
      state.deleteSelection();
      expect(state.state.storedMarks!.map((mark) => mark.type.name).join(","), "em");
    });

    test("keeps non-inclusive marks when still inside them", () {
      final state = TestState(doc: document(p("foo", a("b", em("<a>a<b>"), "r"), "baz")));
      state.deleteSelection();
      expect(state.state.storedMarks!.length, 2);
    });

    test("preserves marks when typing over marked text", () {
      final state = TestState(doc: document(p("foo ", em("<a>bar<b>"), " baz")));
      state.apply(state.tr.insertText("quux"));
      expect(eq(state.doc, document(p("foo ", em("quux"), " baz"))), isTrue);
      state.apply(state.tr.insertText("bar", 5, 9));
      expect(eq(state.doc, document(p("foo ", em("bar"), " baz"))), isTrue);
    });

    test("allows deleting a leaf", () {
      final state = TestState(doc: document(p("a"), hr(), hr(), p("b")), schema: schema);
      state.nodeSel(3);
      state.deleteSelection();
      expect(eq(state.doc, document(p("a"), hr(), p("b"))), isTrue);
      expect(state.selection.from, 3);
      state.deleteSelection();
      expect(eq(state.doc, document(p("a"), p("b"))), isTrue);
      expect(state.selection.head, 4);
    });

    test("properly handles deleting the selection", () {
      final state = TestState(doc: document(p("foo", img(), "bar"), blockquote(p("hi")), p("ay")), schema: schema);
      state.nodeSel(4);
      state.apply(state.tr.deleteSelection());
      expect(eq(state.doc, document(p("foobar"), blockquote(p("hi")), p("ay"))), isTrue);
      expect(state.selection.head, 4);
      state.nodeSel(9);
      state.apply(state.tr.deleteSelection());
      expect(eq(state.doc, document(p("foobar"), p("ay"))), isTrue);
      expect(state.selection.from, 9);
      state.nodeSel(8);
      state.apply(state.tr.deleteSelection());
      expect(eq(state.doc, document(p("foobar"))), isTrue);
      expect(state.selection.from, 7);
    });

    test("can replace inline selections", () {
      final state = TestState(doc: document(p("foo", img(), "bar", img(), "baz")), schema: schema);
      state.nodeSel(4);
      state.apply(state.tr.replaceSelectionWith(schema.node("hard_break")));
      expect(eq(state.doc, document(p("foo", br(), "bar", img(), "baz"))), isTrue);
      expect(state.selection.head, 5);
      expect(state.selection.empty, isTrue);
      state.nodeSel(8);
      state.apply(state.tr.insertText("abc"));
      expect(eq(state.doc, document(p("foo", br(), "barabcbaz"))), isTrue);
      expect(state.selection.head, 11);
      expect(state.selection.empty, isTrue);
      state.nodeSel(0);
      state.apply(state.tr.insertText("xyz"));
      expect(eq(state.doc, document(p("xyz"))), isTrue);
    });

    test("can replace a block selection", () {
      final state = TestState(doc: document(p("abc"), hr(), hr(), blockquote(p("ow"))), schema: schema);
      state.nodeSel(5);
      state.apply(state.tr.replaceSelectionWith(schema.node("code_block")));
      expect(eq(state.doc, document(p("abc"), pre(), hr(), blockquote(p("ow")))), isTrue);
      expect(state.selection.from, 7);
      state.nodeSel(8);
      state.apply(state.tr.replaceSelectionWith(schema.node("paragraph")));
      expect(eq(state.doc, document(p("abc"), pre(), hr(), p())), isTrue);
      expect(state.selection.from, 9);
    });

    test("puts the cursor after the inserted text when inserting a list item", () {
      final state = TestState(doc: document(p("<a>abc")));
      final source = document(ul(li(p("<a>def<b>"))));
      state.apply(state.tr.replaceSelection(source.slice(source.tag["a"]!, source.tag["b"]!, true)));
      expect(state.selection.from, 6);
    });
  });

  group("TextSelection.between >", () {
    test("uses arguments when possible", () {
      final testDocument = document(p("f<a>o<b>o"));
      final selection = TextSelection.between(
        testDocument.resolve(testDocument.tag["b"]!),
        testDocument.resolve(testDocument.tag["a"]!),
      );
      expect(selection.anchor, testDocument.tag["b"]);
      expect(selection.head, testDocument.tag["a"]);
    });

    test("will adjust when necessary", () {
      final testDocument = document("<a>", p("foo"));
      final selection = TextSelection.between(
        testDocument.resolve(testDocument.tag["a"]!),
        testDocument.resolve(testDocument.tag["a"]!),
      );
      expect(selection.anchor, 1);
    });

    test("uses bias when adjusting", () {
      final testDocument = document(p("foo"), "<a>", p("bar"));
      final pos = testDocument.resolve(testDocument.tag["a"]!);
      final selectionUp = TextSelection.between(pos, pos, -1);
      expect(selectionUp.anchor, 4);
      final selectionDown = TextSelection.between(pos, pos, 1);
      expect(selectionDown.anchor, 6);
    });

    test("will fall back to a node selection", () {
      final testDocument = document(hr, "<a>");
      final selection = TextSelection.between(
        testDocument.resolve(testDocument.tag["a"]!),
        testDocument.resolve(testDocument.tag["a"]!),
      );
      expect((selection as NodeSelection).node, testDocument.firstChild);
    });

    test("will collapse towards the other argument", () {
      final testDocument = document("<a>", p("foo"), "<b>");
      var selection = TextSelection.between(
        testDocument.resolve(testDocument.tag["a"]!),
        testDocument.resolve(testDocument.tag["b"]!),
      );
      expect(selection.anchor, 1);
      expect(selection.head, 4);
      selection = TextSelection.between(
        testDocument.resolve(testDocument.tag["b"]!),
        testDocument.resolve(testDocument.tag["a"]!),
      );
      expect(selection.anchor, 4);
      expect(selection.head, 1);
    });
  });
}
