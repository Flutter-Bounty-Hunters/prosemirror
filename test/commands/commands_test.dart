/// Port of `prosemirror-commands`'s `test/test-commands.ts`.
library;

import 'package:prosemirror/prosemirror.dart';
import 'package:test/test.dart';

import 'package:prosemirror/test_builder.dart';

void main() {
  group("Join backward >", () {
    test("can join paragraphs", () {
      _apply(document(p("hi"), p("<a>there")), joinBackward, document(p("hithere")));
    });

    test("can join out of a nested node", () {
      _apply(document(p("hi"), blockquote(p("<a>there"))), joinBackward, document(p("hi"), p("there")));
    });

    test("moves a block into an adjacent wrapper", () {
      _apply(document(blockquote(p("hi")), p("<a>there")), joinBackward, document(blockquote(p("hi"), p("there"))));
    });

    test("moves a block into an adjacent wrapper from another wrapper", () {
      _apply(
        document(blockquote(p("hi")), blockquote(p("<a>there"))),
        joinBackward,
        document(blockquote(p("hi"), p("there"))),
      );
    });

    test("joins the wrapper to a subsequent one if applicable", () {
      _apply(
        document(blockquote(p("hi")), p("<a>there"), blockquote(p("x"))),
        joinBackward,
        document(blockquote(p("hi"), p("there"), p("x"))),
      );
    });

    test("moves a block into a list item", () {
      _apply(document(ul(li(p("hi"))), p("<a>there")), joinBackward, document(ul(li(p("hi")), li(p("there")))));
    });

    test("joins lists", () {
      _apply(document(ul(li(p("hi"))), ul(li(p("<a>there")))), joinBackward, document(ul(li(p("hi")), li(p("there")))));
    });

    test("joins list items", () {
      _apply(document(ul(li(p("hi")), li(p("<a>there")))), joinBackward, document(ul(li(p("hi"), p("there")))));
    });

    test("lifts out of a list at the start", () {
      _apply(document(ul(li(p("<a>there")))), joinBackward, document(p("<a>there")));
    });

    test("joins lists before and after", () {
      _apply(
        document(ul(li(p("hi"))), p("<a>there"), ul(li(p("x")))),
        joinBackward,
        document(ul(li(p("hi")), li(p("there")), li(p("x")))),
      );
    });

    test("deletes leaf nodes before", () {
      _apply(document(hr(), p("<a>there")), joinBackward, document(p("there")));
    });

    test("lifts before it deletes", () {
      _apply(document(hr(), blockquote(p("<a>there"))), joinBackward, document(hr(), p("there")));
    });

    test("does nothing at start of doc", () {
      _apply(document(p("<a>foo")), joinBackward, null);
    });

    test("can join single-textblock-child nodes", () {
      final s = Schema(
        SchemaSpec(
          nodes: {
            "text": NodeSpec(inline: true),
            "doc": NodeSpec(content: "block+"),
            "block": NodeSpec(content: "para"),
            "para": NodeSpec(content: "text*"),
          },
        ),
      );
      final document = s.node("doc", null, [
        s.node("block", null, [
          s.node("para", null, [s.text("a")]),
        ]),
        s.node("block", null, [
          s.node("para", null, [s.text("b")]),
        ]),
      ]);
      var state = EditorState.create(
        EditorStateConfig(doc: document, selection: TextSelection.between(document.resolve(7), document.resolve(7))),
      );

      expect(joinBackward.execute(state, (tr) => state = state.apply(tr)), isTrue);
      expect(state.doc.toString(), 'doc(block(para("ab")))');
    });

    test("doesn't return true on empty blocks that can't be deleted", () {
      _apply(document(p("a"), ul(li(p("<a>"), ul(li("b"))))), joinBackward, null);
    });

    test("doesn't join surrounding nodes of different types", () {
      _apply(
        document(ul(li(p("a"))), p("<a>"), ol(li(p("b")))),
        joinBackward,
        document(ul(li(p("a")), li(p("<a>"))), ol(li(p("b")))),
      );
    });
  });

  group("Join textblock backward >", () {
    test("can join paragraphs", () {
      _apply(document(p("hi"), p("<a>there")), joinTextblockBackward, document(p("hi<a>there")));
    });

    test("can join if second block is wrapped", () {
      _apply(document(p("hi"), ul(li(p("<a>there")))), joinTextblockBackward, document(p("hi<a>there")));
    });

    test("can join if first block is wrapped", () {
      _apply(
        document(blockquote(p("hi")), p("<a>there")),
        joinTextblockBackward,
        document(blockquote(p("hi<a>there"))),
      );
    });

    test("does nothing at start of doc", () {
      _apply(document(p("<a>foo")), joinTextblockBackward, null);
    });

    test("can join if inside a nested block", () {
      _apply(
        document(blockquote(blockquote(p("hi")), p("<a>there"))),
        joinTextblockBackward,
        document(blockquote(blockquote(p("hi<a>there")))),
      );
    });
  });

  group("Select node backward >", () {
    test("selects the node before the cut", () {
      _apply(
        document(blockquote(p("a")), blockquote(p("<a>b"))),
        selectNodeBackward,
        document("<a>", blockquote(p("a")), blockquote(p("b"))),
      );
    });

    test("does nothing when not at the start of the textblock", () {
      _apply(document(p("a<a>b")), selectNodeBackward, null);
    });
  });

  group("Delete selection >", () {
    test("deletes part of a text node", () {
      _apply(document(p("f<a>o<b>o")), deleteSelection, document(p("fo")));
    });

    test("can delete across blocks", () {
      _apply(document(p("f<a>oo"), p("ba<b>r")), deleteSelection, document(p("fr")));
    });

    test("deletes node selections", () {
      _apply(document(p("foo"), "<a>", hr()), deleteSelection, document(p("foo")));
    });

    test("moves selection after deleted node", () {
      _apply(
        document(p("a"), "<a>", p("b"), blockquote(p("c"))),
        deleteSelection,
        document(p("a"), blockquote(p("<a>c"))),
      );
    });

    test("moves selection before deleted node at end", () {
      _apply(document(p("a"), "<a>", p("b")), deleteSelection, document(p("a<a>")));
    });
  });

  group("Join forward >", () {
    test("joins two textblocks", () {
      _apply(document(p("foo<a>"), p("bar")), joinForward, document(p("foobar")));
    });

    test("keeps type of second node when first is empty", () {
      _apply(document(p("x"), p("<a>"), h1("hi")), joinForward, document(p("x"), h1("<a>hi")));
    });

    test("clears nodes from joined node that wouldn't be allowed", () {
      _apply(document(pre("foo<a>"), p("bar", img())), joinForward, document(pre("foo<a>bar")));
    });

    test("does nothing at the end of the document", () {
      _apply(document(p("foo<a>")), joinForward, null);
    });

    test("deletes a leaf node after the current block", () {
      _apply(document(p("foo<a>"), hr(), p("bar")), joinForward, document(p("foo"), p("bar")));
    });

    test("pulls the next block into the current list item", () {
      _apply(document(ul(li(p("a<a>")), li(p("b")))), joinForward, document(ul(li(p("a"), p("b")))));
    });

    test("joins two blocks inside of a list item", () {
      _apply(document(ul(li(p("a<a>"), p("b")))), joinForward, document(ul(li(p("ab")))));
    });

    test("pulls the next block into a blockquote", () {
      _apply(document(blockquote(p("foo<a>")), p("bar")), joinForward, document(blockquote(p("foo<a>"), p("bar"))));
    });

    test("joins two blockquotes", () {
      _apply(
        document(blockquote(p("hi<a>")), blockquote(p("there"))),
        joinForward,
        document(blockquote(p("hi"), p("there"))),
      );
    });

    test("pulls the next block outside of a wrapping blockquote", () {
      _apply(document(p("foo<a>"), blockquote(p("bar"))), joinForward, document(p("foo"), p("bar")));
    });

    test("joins two lists", () {
      _apply(document(ul(li(p("hi<a>"))), ul(li(p("there")))), joinForward, document(ul(li(p("hi")), li(p("there")))));
    });

    test("does nothing in a nested node at the end of the document", () {
      _apply(document(ul(li(p("there<a>")))), joinForward, null);
    });

    test("deletes a leaf node at the end of the document", () {
      _apply(document(p("there<a>"), hr()), joinForward, document(p("there")));
    });

    test("moves before it deletes a leaf node", () {
      _apply(document(blockquote(p("there<a>")), hr()), joinForward, document(blockquote(p("there"), hr())));
    });

    test("does nothing when it can't join", () {
      _apply(document(p("foo<a>"), ul(li(p("bar"), ul(li(p("baz")))))), joinForward, null);
    });
  });

  group("Join textblock forward >", () {
    test("can join paragraphs", () {
      _apply(document(p("hi<a>"), p("there")), joinTextblockForward, document(p("hi<a>there")));
    });

    test("can join if second block is wrapped", () {
      _apply(document(p("hi<a>"), ul(li(p("there")))), joinTextblockForward, document(p("hi<a>there")));
    });

    test("can join if first block is wrapped", () {
      _apply(document(blockquote(p("hi<a>")), p("there")), joinTextblockForward, document(blockquote(p("hi<a>there"))));
    });

    test("does nothing at end of doc", () {
      _apply(document(p("foo<a>")), joinTextblockForward, null);
    });
  });

  group("Select node forward >", () {
    test("selects the next node", () {
      _apply(
        document(p("foo<a>"), ul(li(p("bar"), ul(li(p("baz")))))),
        selectNodeForward,
        document(p("foo<a>"), "<a>", ul(li(p("bar"), ul(li(p("baz")))))),
      );
    });

    test("does nothing at end of document", () {
      _apply(document(p("foo<a>")), selectNodeForward, null);
    });
  });

  group("Join up >", () {
    test("joins identical parent blocks", () {
      _apply(
        document(blockquote(p("foo")), blockquote(p("<a>bar"))),
        joinUp,
        document(blockquote(p("foo"), p("<a>bar"))),
      );
    });

    test("does nothing in the first block", () {
      _apply(document(blockquote(p("<a>foo")), blockquote(p("bar"))), joinUp, null);
    });

    test("joins lists", () {
      _apply(document(ul(li(p("foo"))), ul(li(p("<a>bar")))), joinUp, document(ul(li(p("foo")), li(p("bar")))));
    });

    test("joins list items", () {
      _apply(document(ul(li(p("foo")), li(p("<a>bar")))), joinUp, document(ul(li(p("foo"), p("bar")))));
    });

    test("doesn't look at ancestors when a block is selected", () {
      _apply(document(ul(li(p("foo")), li("<a>", p("bar")))), joinUp, null);
    });

    test("can join selected block nodes", () {
      _apply(document(ul(li(p("foo")), "<a>", li(p("bar")))), joinUp, document(ul("<a>", li(p("foo"), p("bar")))));
    });
  });

  group("Join down >", () {
    test("joins parent blocks", () {
      _apply(
        document(blockquote(p("foo<a>")), blockquote(p("bar"))),
        joinDown,
        document(blockquote(p("foo<a>"), p("bar"))),
      );
    });

    test("doesn't join with the block before", () {
      _apply(document(blockquote(p("foo")), blockquote(p("<a>bar"))), joinDown, null);
    });

    test("joins lists", () {
      _apply(document(ul(li(p("foo<a>"))), ul(li(p("bar")))), joinDown, document(ul(li(p("foo")), li(p("bar")))));
    });

    test("joins list items", () {
      _apply(document(ul(li(p("<a>foo")), li(p("bar")))), joinDown, document(ul(li(p("foo"), p("bar")))));
    });

    test("doesn't look at parent nodes of a selected node", () {
      _apply(document(ul(li("<a>", p("foo")), li(p("bar")))), joinDown, null);
    });

    test("can join selected nodes", () {
      _apply(document(ul("<a>", li(p("foo")), li(p("bar")))), joinDown, document(ul("<a>", li(p("foo"), p("bar")))));
    });
  });

  group("Lift >", () {
    test("lifts out of a parent block", () {
      _apply(document(blockquote(p("<a>foo"))), lift, document(p("<a>foo")));
    });

    test("splits the parent block when necessary", () {
      _apply(
        document(blockquote(p("foo"), p("<a>bar"), p("baz"))),
        lift,
        document(blockquote(p("foo")), p("bar"), blockquote(p("baz"))),
      );
    });

    test("can lift out of a list", () {
      _apply(document(ul(li(p("<a>foo")))), lift, document(p("foo")));
    });

    test("does nothing for a top-level block", () {
      _apply(document(p("<a>foo")), lift, null);
    });

    test("lifts out of the innermost parent", () {
      _apply(document(blockquote(ul(li(p("foo<a>"))))), lift, document(blockquote(p("foo<a>"))));
    });

    test("can lift a node selection", () {
      _apply(document(blockquote("<a>", ul(li(p("foo"))))), lift, document("<a>", ul(li(p("foo")))));
    });

    test("lifts out of a nested list", () {
      _apply(
        document(ul(li(p("one"), ul(li(p("<a>sub1")), li(p("sub2")))), li(p("two")))),
        lift,
        document(ul(li(p("one"), p("<a>sub1"), ul(li(p("sub2")))), li(p("two")))),
      );
    });
  });

  group("Newline in code >", () {
    test("inserts a newline in a code block", () {
      _apply(document(pre("foo<a>bar")), newlineInCode, document(pre("foo\nbar")));
    });

    test("does nothing outside a code block", () {
      _apply(document(p("foo<a>bar")), newlineInCode, null);
    });
  });

  group("Exit code >", () {
    test("creates a paragraph after a code block", () {
      _apply(document(pre("foo<a>")), exitCode, document(pre("foo"), p("<a>")));
    });

    test("does nothing outside a code block", () {
      _apply(document(p("foo<a>")), exitCode, null);
    });
  });

  group("Wrap in >", () {
    final wrap = wrapIn(schema.nodes["blockquote"]!);

    test("can wrap a paragraph", () {
      _apply(document(p("fo<a>o")), wrap, document(blockquote(p("foo"))));
    });

    test("wraps multiple paragraphs", () {
      _apply(
        document(p("fo<a>o"), p("bar"), p("ba<b>z"), p("quux")),
        wrap,
        document(blockquote(p("foo"), p("bar"), p("baz")), p("quux")),
      );
    });

    test("wraps an already wrapped node", () {
      _apply(document(blockquote(p("fo<a>o"))), wrap, document(blockquote(blockquote(p("foo")))));
    });

    test("can wrap a node selection", () {
      _apply(document("<a>", ul(li(p("foo")))), wrap, document(blockquote(ul(li(p("foo"))))));
    });
  });

  group("Split block >", () {
    test("splits a paragraph at the end", () {
      _apply(document(p("foo<a>")), splitBlock, document(p("foo"), p()));
    });

    test("splits a paragraph in the middle", () {
      _apply(document(p("foo<a>bar")), splitBlock, document(p("foo"), p("bar")));
    });

    test("splits a paragraph from a heading", () {
      _apply(document(h1("foo<a>")), splitBlock, document(h1("foo"), p()));
    });

    test("splits a heading in two when in the middle", () {
      _apply(document(h1("foo<a>bar")), splitBlock, document(h1("foo"), h1("bar")));
    });

    test("deletes selected content", () {
      _apply(document(p("fo<a>ob<b>ar")), splitBlock, document(p("fo"), p("ar")));
    });

    test("splits a parent block when a node is selected", () {
      _apply(
        document(ol(li(p("a")), "<a>", li(p("b")), li(p("c")))),
        splitBlock,
        document(ol(li(p("a"))), ol(li(p("b")), li(p("c")))),
      );
    });

    test("doesn't split the parent block when at the start", () {
      _apply(document(ol("<a>", li(p("a")), li(p("b")), li(p("c")))), splitBlock, null);
    });

    test("splits off a normal paragraph at the start of a textblock", () {
      _apply(document(h1("<a>foo")), splitBlock, document(p(), h1("foo")));
    });

    test("splits a heading when a double heading isn't allowed", () {
      _apply(
        _headingDocument(4),
        splitBlock,
        _headingSchema.node("doc", null, [
          _headingSchema.node("heading", {"level": 1}, _headingSchema.text("foo")),
          _headingSchema.node("paragraph", null, _headingSchema.text("bar")),
        ]),
      );
    });

    test("won't reset the type of an empty leftover when forbidden", () {
      _apply(
        _headingDocument(1),
        splitBlock,
        _headingSchema.node("doc", null, [
          _headingSchema.node("heading", {"level": 1}),
          _headingSchema.node("paragraph", null, _headingSchema.text("foobar")),
        ]),
      );
    });

    test("can split an inline node", () {
      final initial = _tagNode(
        _headingSchema.node("doc", null, [
          _headingSchema.node(
            "heading",
            {"level": 1},
            [_headingSchema.node("span", null, _headingSchema.text("abcd"))],
          ),
        ]),
        {"a": 4},
      );

      _apply(
        initial,
        splitBlock,
        _headingSchema.node("doc", null, [
          _headingSchema.node("heading", {"level": 1}, _headingSchema.node("span", null, _headingSchema.text("ab"))),
          _headingSchema.node("paragraph", null, _headingSchema.node("span", null, _headingSchema.text("cd"))),
        ]),
      );
    });

    test("prefers textblocks", () {
      final s = Schema(
        SchemaSpec(
          nodes: {
            "text": NodeSpec(),
            "para": NodeSpec(content: "text*"),
            "section": NodeSpec(content: "para+"),
            "doc": NodeSpec(content: "para* section*"),
          },
        ),
      );
      final initial = _tagNode(
        s.node("doc", null, [
          s.node("para", null, [s.text("hello")]),
        ]),
        {"a": 3},
      );

      _apply(
        initial,
        splitBlock,
        s.node("doc", null, [
          s.node("para", null, [s.text("he")]),
          s.node("para", null, [s.text("llo")]),
        ]),
      );
    });

    test("can handle selection deletion dropping wrapper nodes", () {
      _apply(document(ul(li(p(), pre("<a>0")), li(p("<b>")))), splitBlock, document(ul(li(p()), li(p(), p()))));
    });
  });

  group("Split block as >", () {
    test("splits to the appropriate type", () {
      _apply(
        document(p("on<a>e")),
        splitBlockAs(
          (node, atEnd, position) => SplitBlockType(type: node.type.schema.nodes["heading"]!, attrs: {"level": 1}),
        ),
        document(p("on"), h1("<a>e")),
      );
    });

    test("passes an end-of-block flag", () {
      _apply(
        document(p("one<a>")),
        splitBlockAs(
          (node, atEnd, position) => atEnd ? SplitBlockType(type: node.type.schema.nodes["code_block"]!) : null,
        ),
        document(p("one"), pre("<a>")),
      );
    });
  });

  group("Split block keep marks >", () {
    test("keeps marks when used after marked text", () {
      var state = _makeState(document(p(strong("foo<a>"), "bar")));
      splitBlockKeepMarks.execute(state, (tr) => state = state.apply(tr));
      expect(state.storedMarks!.length, 1);
    });

    test("preserves the stored marks", () {
      var state = _makeState(document(p(em("foo<a>"))));
      toggleMark(schema.marks["strong"]!).execute(state, (tr) => state = state.apply(tr));
      splitBlockKeepMarks.execute(state, (tr) => state = state.apply(tr));
      expect(state.storedMarks!.length, 2);
    });
  });

  group("Lift empty block >", () {
    test("splits the parent block when there are siblings before", () {
      _apply(
        document(blockquote(p("foo"), p("<a>"), p("bar"))),
        liftEmptyBlock,
        document(blockquote(p("foo")), blockquote(p(), p("bar"))),
      );
    });

    test("lifts the last child out of its parent", () {
      _apply(document(blockquote(p("foo"), p("<a>"))), liftEmptyBlock, document(blockquote(p("foo")), p()));
    });

    test("lifts an only child", () {
      _apply(
        document(blockquote(p("foo")), blockquote(p("<a>"))),
        liftEmptyBlock,
        document(blockquote(p("foo")), p("<a>")),
      );
    });

    test("does not violate schema constraints", () {
      _apply(document(ul(li(p("<a>foo"), blockquote(p("bar"))))), liftEmptyBlock, null);
    });

    test("lifts out of a list", () {
      _apply(document(ul(li(p("hi")), li(p("<a>")))), liftEmptyBlock, document(ul(li(p("hi"))), p()));
    });
  });

  group("Create paragraph near >", () {
    test("creates a paragraph before a selected node at the start", () {
      _apply(document("<a>", hr(), hr()), createParagraphNear, document(p(), hr(), hr()));
    });

    test("creates a paragraph after a lone selected node", () {
      _apply(document("<a>", hr()), createParagraphNear, document(hr(), p()));
    });

    test("creates a paragraph after selected nodes not at the start", () {
      _apply(document(p(), "<a>", hr()), createParagraphNear, document(p(), hr(), p()));
    });
  });

  group("Set block type >", () {
    final setHeading = setBlockType(schema.nodes["heading"]!, {"level": 1});
    final setParagraph = setBlockType(schema.nodes["paragraph"]!);
    final setCode = setBlockType(schema.nodes["code_block"]!);

    test("can change the type of a paragraph", () {
      _apply(document(p("fo<a>o")), setHeading, document(h1("foo")));
    });

    test("can change the type of a code block", () {
      _apply(document(pre("fo<a>o")), setHeading, document(h1("foo")));
    });

    test("can make a heading into a paragraph", () {
      _apply(document(h1("fo<a>o")), setParagraph, document(p("foo")));
    });

    test("preserves marks", () {
      _apply(document(h1("fo<a>o", em("bar"))), setParagraph, document(p("foo", em("bar"))));
    });

    test("acts on node selections", () {
      _apply(document("<a>", h1("foo")), setParagraph, document(p("foo")));
    });

    test("can make a block a code block", () {
      _apply(document(h1("fo<a>o")), setCode, document(pre("foo")));
    });

    test("clears marks when necessary", () {
      _apply(document(p("fo<a>o", em("bar"))), setCode, document(pre("foobar")));
    });

    test("acts on multiple blocks when possible", () {
      _apply(
        document(p("a<a>bc"), p("def"), ul(li(p("ghi"), p("jk<b>l")))),
        setCode,
        document(pre("a<a>bc"), pre("def"), ul(li(p("ghi"), pre("jk<b>l")))),
      );
    });

    test("returns false when all textblocks already have this type", () {
      _apply(document(pre("a<a>bc"), pre("de<b>f")), setCode, null);
    });

    test("returns false when the selected blocks can't be changed", () {
      _apply(document(ul(p("a<a>b<b>c"), p("def"))), setCode, null);
    });
  });

  group("Select parent node >", () {
    test("selects the whole textblock", () {
      _apply(
        document(ul(li(p("foo"), p("b<a>ar")), li(p("baz")))),
        selectParentNode,
        document(ul(li(p("foo"), "<a>", p("bar")), li(p("baz")))),
      );
    });

    test("goes one level up when on a block", () {
      _apply(
        document(ul(li(p("foo"), "<a>", p("bar")), li(p("baz")))),
        selectParentNode,
        document(ul("<a>", li(p("foo"), p("bar")), li(p("baz")))),
      );
    });

    test("goes further up", () {
      _apply(
        document(ul("<a>", li(p("foo"), p("bar")), li(p("baz")))),
        selectParentNode,
        document("<a>", ul(li(p("foo"), p("bar")), li(p("baz")))),
      );
    });

    test("stops at the top level", () {
      _apply(
        document("<a>", ul(li(p("foo"), p("bar")), li(p("baz")))),
        selectParentNode,
        document("<a>", ul(li(p("foo"), p("bar")), li(p("baz")))),
      );
    });
  });

  group("Select all >", () {
    test("selects the whole document", () {
      var state = _makeState(document(p("one<a>"), p("two")));
      expect(selectAll.execute(state, (tr) => state = state.apply(tr)), isTrue);
      expect(state.selection, isA<AllSelection>());
      expect(state.selection.from, 0);
      expect(state.selection.to, state.doc.content.size);
    });
  });

  group("Auto join >", () {
    test("joins lists when deleting a paragraph between them", () {
      _apply(
        document(ul(li(p("a"))), "<a>", p("b"), ul(li(p("c")))),
        autoJoin(deleteSelection, ["bullet_list"]),
        document(ul(li(p("a")), li(p("c")))),
      );
    });

    test("doesn't join lists when deleting an item inside of them", () {
      _apply(
        document(ul(li(p("a")), "<a>", li(p("b"))), ul(li(p("c")))),
        autoJoin(deleteSelection, ["bullet_list"]),
        document(ul(li(p("a"))), ul(li(p("c")))),
      );
    });

    test("joins lists when wrapping a paragraph after them in a list", () {
      _apply(
        document(ul(li(p("a"))), p("b<a>")),
        autoJoin(wrapIn(schema.nodes["bullet_list"]!), ["bullet_list"]),
        document(ul(li(p("a")), li(p("b")))),
      );
    });

    test("joins lists when wrapping a paragraph between them in a list", () {
      _apply(
        document(ul(li(p("a"))), p("b<a>"), ul(li(p("c")))),
        autoJoin(wrapIn(schema.nodes["bullet_list"]!), ["bullet_list"]),
        document(ul(li(p("a")), li(p("b")), li(p("c")))),
      );
    });

    test("joins lists when lifting a list between them", () {
      _apply(
        document(ul(li(p("a"))), blockquote("<a>", ul(li(p("b")))), ul(li(p("c")))),
        autoJoin(lift, ["bullet_list"]),
        document(ul(li(p("a")), li(p("b")), li(p("c")))),
      );
    });
  });

  group("Toggle mark >", () {
    final toggleEm = toggleMark(schema.marks["em"]!);
    final toggleStrong = toggleMark(schema.marks["strong"]!);
    final toggleEmWithoutRemoval = toggleMark(
      schema.marks["em"]!,
      null,
      const ToggleMarkOptions(removeWhenPresent: false),
    );

    test("can add a mark", () {
      _apply(document(p("one <a>two<b>")), toggleEm, document(p("one ", em("two"))));
    });

    test("can stack marks", () {
      _apply(document(p("one <a>tw", strong("o<b>"))), toggleEm, document(p("one ", em("tw", strong("o")))));
    });

    test("can remove marks", () {
      _apply(document(p(em("one <a>two<b>"))), toggleEm, document(p(em("one "), "two")));
    });

    test("can toggle pending marks", () {
      var state = _makeState(document(p("hell<a>o")));
      toggleEm.execute(state, (tr) => state = state.apply(tr));
      expect(state.storedMarks!.length, 1);
      toggleStrong.execute(state, (tr) => state = state.apply(tr));
      expect(state.storedMarks!.length, 2);
      toggleEm.execute(state, (tr) => state = state.apply(tr));
      expect(state.storedMarks!.length, 1);
    });

    test("skips whitespace at selection ends when adding marks", () {
      _apply(document(p("one<a> two  <b>three")), toggleEm, document(p("one ", em("two"), "  three")));
    });

    test("doesn't skip whitespace-only selections", () {
      _apply(document(p("one<a> <b>two")), toggleEm, document(p("one", em(" "), "two")));
    });

    test("includes whitespace when asked", () {
      _apply(
        document(p("one<a> two  <b>three")),
        toggleMark(schema.marks["em"]!, null, const ToggleMarkOptions(includeWhitespace: true)),
        document(p("one", em(" two  "), "three")),
      );
    });

    test("can add marks with remove-when-present off", () {
      _apply(document(p("<a>", em("one"), " two<b>")), toggleEmWithoutRemoval, document(p(em("one two"))));
      _apply(document(p("<a>three<b>")), toggleEmWithoutRemoval, document(p(em("three"))));
    });

    test("can remove marks with remove-when-present off", () {
      _apply(document(p(em("o<a>ne two<b>"))), toggleEmWithoutRemoval, document(p(em("o"), "ne two")));
    });

    test("can remove marks with trailing space when remove-when-present is off", () {
      _apply(
        document(p(em("o<a>ne two"), "  <b>three")),
        toggleEmWithoutRemoval,
        document(p(em("o"), "ne two  three")),
      );
    });

    test("enters inline atoms by default", () {
      final builders = _footnoteBuilders();

      _apply(
        builders.document(builders.paragraph("h<a>ello", builders.footnote("okay"), "<b>")),
        toggleMark(builders.schema.marks["em"]!),
        builders.document(
          builders.paragraph("h", builders.emphasized("ello", builders.footnote(builders.emphasized("okay")))),
        ),
      );
    });

    test("doesn't enter inline atoms to add a mark when told not to", () {
      final builders = _footnoteBuilders();

      _apply(
        builders.document(builders.paragraph("h<a>ello", builders.footnote("okay"), "<b>")),
        toggleMark(builders.schema.marks["em"]!, null, const ToggleMarkOptions(enterInlineAtoms: false)),
        builders.document(builders.paragraph("h", builders.emphasized("ello", builders.footnote("okay")))),
      );
    });

    test("can apply styles inside inline atoms", () {
      final builders = _footnoteBuilders();

      _apply(
        builders.document(builders.paragraph("hello", builders.footnote("o<a>kay<b>"))),
        toggleMark(builders.schema.marks["em"]!, null, const ToggleMarkOptions(enterInlineAtoms: false)),
        builders.document(builders.paragraph("hello", builders.footnote("o", builders.emphasized("kay")))),
      );
    });

    test("can add a mark even if already active inside an inline atom", () {
      final builders = _footnoteBuilders();

      _apply(
        builders.document(builders.paragraph("h<a>ello", builders.footnote(builders.emphasized("okay")), "<b>")),
        toggleMark(builders.schema.marks["em"]!, null, const ToggleMarkOptions(enterInlineAtoms: false)),
        builders.document(
          builders.paragraph("h", builders.emphasized("ello", builders.footnote(builders.emphasized("okay")))),
        ),
      );
    });

    test("doesn't enter inline atoms to remove a mark when told not to", () {
      final builders = _footnoteBuilders();

      _apply(
        builders.document(
          builders.paragraph(builders.emphasized("h<a>ello", builders.footnote(builders.emphasized("okay")), "<b>")),
        ),
        toggleMark(builders.schema.marks["em"]!, null, const ToggleMarkOptions(enterInlineAtoms: false)),
        builders.document(
          builders.paragraph(builders.emphasized("h"), "ello", builders.footnote(builders.emphasized("okay"))),
        ),
      );
    });
  });

  group("Select textblock boundaries >", () {
    test("can move the cursor when the selection is empty", () {
      _apply(document(p("one <a>two")), selectTextblockStart, document(p("<a>one two")));
      _apply(document(p("one <a>two")), selectTextblockEnd, document(p("one two<a>")));
    });

    test("can move the cursor when the selection is not empty", () {
      _apply(document(p("one <a>two<b>")), selectTextblockStart, document(p("<a>one two")));
      _apply(document(p("one <a>two<b>")), selectTextblockEnd, document(p("one two<a>")));
    });

    test("can move the cursor when selection crosses text blocks", () {
      _apply(
        document(p("one <a>two"), p("three<b> four")),
        selectTextblockStart,
        document(p("<a>one two"), p("three four")),
      );

      _apply(
        document(p("one <a>two"), p("three<b> four")),
        selectTextblockEnd,
        document(p("one two"), p("three four<a>")),
      );
    });
  });

  group("Command chaining >", () {
    test("runs commands until one succeeds", () {
      final counter = _CommandCallCounter();
      final command = chainCommands([
        _CountingCommand(counter, false),
        _CountingCommand(counter, true),
        _CountingCommand(counter, true),
      ]);

      expect(command.execute(_makeState(document(p("<a>")))), isTrue);
      expect(counter.calls, 2);
    });
  });

  group("Base keymaps >", () {
    test("include upstream command bindings", () {
      expect(pcBaseKeymap["Enter"], isNotNull);
      expect(pcBaseKeymap["Mod-Enter"], same(exitCode));
      expect(pcBaseKeymap["Mod-a"], same(selectAll));
      expect(macBaseKeymap["Ctrl-a"], same(selectTextblockStart));
      expect(macBaseKeymap["Ctrl-e"], same(selectTextblockEnd));
      expect(identical(baseKeymap, pcBaseKeymap) || identical(baseKeymap, macBaseKeymap), isTrue);
    });
  });
}

void _apply(Node initial, Command command, Node? expected) {
  var state = _makeState(initial);
  command.execute(state, (tr) => state = state.apply(tr));

  expect(eq(state.doc, expected ?? initial), isTrue);
  if (expected != null && _tags(expected).containsKey("a")) {
    expect(state.selection.eq(_selectionFor(expected)), isTrue);
  }
}

EditorState _makeState(Node document) {
  return EditorState.create(EditorStateConfig(doc: document, selection: _selectionFor(document)));
}

Selection _selectionFor(Node document) {
  final a = _tags(document)["a"];
  if (a != null) {
    final $a = document.resolve(a);
    if ($a.parent.inlineContent) {
      final b = _tags(document)["b"];
      return TextSelection($a, b != null ? document.resolve(b) : null);
    }
    return NodeSelection($a);
  }
  return Selection.atStart(document);
}

Map<String, int> _tags(Node node) {
  return node.tag.isNotEmpty ? node.tag : _commandNodeTags[node] ?? const {};
}

Node _tagNode(Node node, Map<String, int> tags) {
  _commandNodeTags[node] = tags;
  return node;
}

Node _headingDocument(int a) {
  return _tagNode(
    _headingSchema.node("doc", null, [
      _headingSchema.node("heading", {"level": 1}, _headingSchema.text("foobar")),
    ]),
    {"a": a},
  );
}

final Schema _headingSchema = Schema(
  SchemaSpec(
    nodes: schema.spec.nodes
        .update("heading", NodeSpec(content: "inline*"))
        .update("doc", NodeSpec(content: "heading block*"))
        .addToEnd("span", NodeSpec(inline: true, group: "inline", content: "inline*")),
  ),
);

_SchemaBuilders _footnoteBuilders() {
  final footnoteSchema = Schema(
    SchemaSpec(
      nodes: {
        "text": NodeSpec(inline: true),
        "doc": NodeSpec(content: "para+"),
        "footnote": NodeSpec(content: "text*", atom: true, inline: true),
        "para": NodeSpec(content: "(text | footnote)*"),
      },
      marks: {"em": MarkSpec()},
    ),
  );
  return _SchemaBuilders(
    schema: footnoteSchema,
    document: _CommandNodeBuilder(footnoteSchema.nodes["doc"]!),
    paragraph: _CommandNodeBuilder(footnoteSchema.nodes["para"]!),
    footnote: _CommandNodeBuilder(footnoteSchema.nodes["footnote"]!),
    emphasized: _CommandMarkBuilder(footnoteSchema.marks["em"]!),
  );
}

class _SchemaBuilders {
  _SchemaBuilders({
    required this.schema,
    required this.document,
    required this.paragraph,
    required this.footnote,
    required this.emphasized,
  });

  final Schema schema;
  final _CommandNodeBuilder document;
  final _CommandNodeBuilder paragraph;
  final _CommandNodeBuilder footnote;
  final _CommandMarkBuilder emphasized;
}

class _CommandNodeBuilder {
  _CommandNodeBuilder(this.type);

  final NodeType type;

  Node call([
    Object? child0,
    Object? child1,
    Object? child2,
    Object? child3,
    Object? child4,
    Object? child5,
    Object? child6,
    Object? child7,
    Object? child8,
    Object? child9,
  ]) {
    final flattened = _flatten(
      type.schema,
      [
        child0,
        child1,
        child2,
        child3,
        child4,
        child5,
        child6,
        child7,
        child8,
        child9,
      ].where((child) => child != null).toList(),
    );
    final node = type.create(null, flattened.nodes);
    if (flattened.tags != null) {
      _commandNodeTags[node] = flattened.tags!;
    }
    return node;
  }
}

class _CommandMarkBuilder {
  _CommandMarkBuilder(this.type);

  final MarkType type;

  _CommandFlatContent call([
    Object? child0,
    Object? child1,
    Object? child2,
    Object? child3,
    Object? child4,
    Object? child5,
    Object? child6,
    Object? child7,
    Object? child8,
    Object? child9,
  ]) {
    final mark = type.create();
    final flattened = _flatten(
      type.schema,
      [
        child0,
        child1,
        child2,
        child3,
        child4,
        child5,
        child6,
        child7,
        child8,
        child9,
      ].where((child) => child != null).toList(),
      (node) {
        final marks = mark.addToSet(node.marks);
        return marks.length > node.marks.length ? node.mark(marks) : node;
      },
    );
    return _CommandFlatContent(flattened.nodes, flattened.tags);
  }
}

_FlattenResult _flatten(Schema schema, List<Object?> children, [Node Function(Node) transform = _identity]) {
  final result = <Node>[];
  var position = 0;
  Map<String, int>? tags;

  for (final child in children) {
    if (child is String) {
      var consumed = 0;
      final text = StringBuffer();
      for (final match in _tagPattern.allMatches(child)) {
        text.write(child.substring(consumed, match.start));
        position += match.start - consumed;
        consumed = match.end;
        tags ??= <String, int>{};
        tags[match.group(1)!] = position;
      }
      text.write(child.substring(consumed));
      position += child.length - consumed;
      final value = text.toString();
      if (value.isNotEmpty) {
        result.add(transform(schema.text(value)));
      }
      continue;
    }

    List<Node>? flatNodes;
    Map<String, int>? childTags;
    var isTextChild = false;
    if (child is _CommandFlatContent) {
      flatNodes = child.nodes;
      childTags = child.tags;
    } else if (child is Node) {
      childTags = _tags(child);
      isTextChild = child.isText;
    }

    if (childTags != null && childTags.isNotEmpty) {
      tags ??= <String, int>{};
      final offset = (flatNodes != null || isTextChild) ? 0 : 1;
      childTags.forEach((id, value) {
        tags![id] = value + offset + position;
      });
    }

    if (flatNodes != null) {
      for (final node in flatNodes) {
        final transformed = transform(node);
        position += transformed.nodeSize;
        result.add(transformed);
      }
    } else {
      final node = transform(child as Node);
      position += node.nodeSize;
      result.add(node);
    }
  }

  return _FlattenResult(result, tags);
}

class _CommandFlatContent {
  _CommandFlatContent(this.nodes, this.tags);

  final List<Node> nodes;
  final Map<String, int>? tags;
}

class _FlattenResult {
  _FlattenResult(this.nodes, this.tags);

  final List<Node> nodes;
  final Map<String, int>? tags;
}

class _CommandCallCounter {
  int calls = 0;
}

class _CountingCommand implements Command {
  _CountingCommand(this.counter, this.result);

  final _CommandCallCounter counter;
  final bool result;

  @override
  bool execute(EditorState state, [void Function(Transaction tr)? dispatch, Object? view]) {
    counter.calls++;
    return result;
  }
}

Node _identity(Node node) => node;

final RegExp _tagPattern = RegExp(r'<(\w+)>');
final Expando<Map<String, int>> _commandNodeTags = Expando<Map<String, int>>();
