import 'package:prosemirror/prosemirror.dart';
import 'package:test/test.dart';

void main() {
  group("Basic schema > nodes >", () {
    test("exposes exactly the nine expected node types", () {
      const expectedNames = {
        "doc",
        "paragraph",
        "blockquote",
        "horizontal_rule",
        "heading",
        "code_block",
        "text",
        "image",
        "hard_break",
      };

      expect(basicSchema.nodes.keys.toSet(), expectedNames);
      expect(basicSchemaNodes.keys.toSet(), expectedNames);
      expect(basicSchema.nodes.length, 9);
    });

    test("doc requires block content", () {
      expect(basicSchema.nodes["doc"]!.spec.content, "block+");

      // An empty doc violates `block+`.
      expect(() => basicSchema.nodes["doc"]!.createChecked(), throwsA(isA<RangeError>()));

      // A doc containing a paragraph satisfies `block+`.
      final paragraph = basicSchema.node("paragraph");
      expect(() => basicSchema.node("doc", null, [paragraph]), returnsNormally);
    });

    test("paragraph is a block textblock with inline content", () {
      final paragraph = basicSchema.nodes["paragraph"]!;

      expect(paragraph.spec.content, "inline*");
      expect(paragraph.spec.group, "block");
      expect(paragraph.isTextblock, isTrue);
    });

    test("heading is a defining block textblock with inline content", () {
      final heading = basicSchema.nodes["heading"]!;

      expect(heading.spec.content, "inline*");
      expect(heading.spec.group, "block");
      expect(heading.isTextblock, isTrue);
      expect(heading.spec.defining, isTrue);
    });

    test("blockquote is defining", () {
      final blockquote = basicSchema.nodes["blockquote"]!;

      expect(blockquote.spec.content, "block+");
      expect(blockquote.spec.group, "block");
      expect(blockquote.spec.defining, isTrue);
    });

    test("horizontal_rule is a block leaf", () {
      final horizontalRule = basicSchema.nodes["horizontal_rule"]!;

      expect(horizontalRule.isLeaf, isTrue);
      expect(horizontalRule.spec.group, "block");
      expect(horizontalRule.isInline, isFalse);
    });

    test("image is an inline leaf", () {
      final image = basicSchema.nodes["image"]!;

      expect(image.isLeaf, isTrue);
      expect(image.isInline, isTrue);
      expect(image.spec.group, "inline");
    });

    test("hard_break is an inline leaf", () {
      final hardBreak = basicSchema.nodes["hard_break"]!;

      expect(hardBreak.isLeaf, isTrue);
      expect(hardBreak.isInline, isTrue);
      expect(hardBreak.spec.group, "inline");
    });

    test("code_block is a code block that disallows marks", () {
      final codeBlock = basicSchema.nodes["code_block"]!;

      expect(codeBlock.spec.content, "text*");
      expect(codeBlock.spec.code, isTrue);
      expect(codeBlock.spec.defining, isTrue);
      expect(codeBlock.spec.marks, "");
      expect(codeBlock.allowsMarkType(basicSchema.marks["em"]!), isFalse);
    });

    test("text is inline", () {
      expect(basicSchema.nodes["text"]!.isInline, isTrue);
      expect(basicSchema.nodes["text"]!.spec.group, "inline");
    });
  });

  group("Basic schema > marks >", () {
    test("exposes exactly the four expected mark types", () {
      const expectedNames = {"link", "em", "strong", "code"};

      expect(basicSchema.marks.keys.toSet(), expectedNames);
      expect(basicSchemaMarks.keys.toSet(), expectedNames);
      expect(basicSchema.marks.length, 4);
    });

    test("code is a code mark", () {
      expect(basicSchema.marks["code"]!.spec.code, isTrue);
    });

    test("link is non-inclusive", () {
      expect(basicSchema.marks["link"]!.spec.inclusive, isFalse);
    });

    test("em and strong exist without attributes", () {
      expect(basicSchema.marks["em"]!.spec.attrs, anyOf(isNull, isEmpty));
      expect(basicSchema.marks["strong"]!.spec.attrs, anyOf(isNull, isEmpty));
    });
  });

  group("Basic schema > attributes >", () {
    test("heading level defaults to 1", () {
      expect(basicSchema.node("heading").attrs["level"], 1);
    });

    test("image requires src and defaults alt and title to null", () {
      // Missing the required `src` attribute fails.
      expect(() => basicSchema.nodes["image"]!.createChecked(), throwsA(isA<RangeError>()));

      // Providing `src` succeeds, and `alt`/`title` default to null.
      final image = basicSchema.nodes["image"]!.createChecked({"src": "image.png"});
      expect(image.attrs["src"], "image.png");
      expect(image.attrs["alt"], isNull);
      expect(image.attrs["title"], isNull);
    });

    test("image with a non-string src fails validation", () {
      final image = basicSchema.nodes["image"]!.createChecked({"src": 123});

      expect(image.check, throwsA(predicate((error) => error.toString().contains("Expected value of type string"))));
    });

    test("link requires href and defaults title to null", () {
      // Missing the required `href` attribute fails.
      expect(() => basicSchema.marks["link"]!.create(), throwsA(isA<RangeError>()));

      // Providing `href` succeeds, and `title` defaults to null.
      final link = basicSchema.marks["link"]!.create({"href": "https://x.dev"});
      expect(link.attrs["href"], "https://x.dev");
      expect(link.attrs["title"], isNull);
    });
  });

  group("Basic schema > documents >", () {
    test("a representative document validates and round-trips", () {
      final document = _buildRepresentativeDocument();

      expect(document.check, returnsNormally);

      final roundTripped = basicSchema.nodeFromJSON(document.toJSON());
      expect(roundTripped.toJSON(), equals(document.toJSON()));
    });
  });
}

Node _buildRepresentativeDocument() {
  return basicSchema.node("doc", null, [
    basicSchema.node("heading", {"level": 2}, [basicSchema.text("Title")]),
    basicSchema.node("paragraph", null, [
      basicSchema.text("Hello "),
      basicSchema.node("image", {"src": "image.png"}),
      basicSchema.node("hard_break"),
      basicSchema.text("world"),
    ]),
    basicSchema.node("blockquote", null, [
      basicSchema.node("paragraph", null, [basicSchema.text("Quoted")]),
    ]),
    basicSchema.node("horizontal_rule"),
    basicSchema.node("code_block", null, [basicSchema.text("code();")]),
  ]);
}
