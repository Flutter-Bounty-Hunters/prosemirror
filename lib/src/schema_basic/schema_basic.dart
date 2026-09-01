import 'package:prosemirror/prosemirror.dart';

/// Specs for the nodes defined in the basic schema.
final Map<String, NodeSpec> basicSchemaNodes = {
  // The top level document node.
  "doc": NodeSpec(content: "block+"),

  // A plain paragraph textblock.
  "paragraph": NodeSpec(content: "inline*", group: "block"),

  // A blockquote wrapping one or more blocks.
  "blockquote": NodeSpec(content: "block+", group: "block", defining: true),

  // A horizontal rule.
  "horizontal_rule": NodeSpec(group: "block"),

  // A heading textblock, with a `level` attribute that should hold the number
  // 1 to 6.
  "heading": NodeSpec(
    attrs: {"level": AttributeSpec(defaultValue: 1, validate: "number")},
    content: "inline*",
    group: "block",
    defining: true,
  ),

  // A code listing. Disallows marks or non-text inline nodes.
  "code_block": NodeSpec(content: "text*", marks: "", group: "block", code: true, defining: true),

  // The text node.
  "text": NodeSpec(group: "inline"),

  // An inline image node.
  "image": NodeSpec(
    inline: true,
    attrs: {
      "src": AttributeSpec(validate: "string"),
      "alt": AttributeSpec(defaultValue: null, validate: "string|null"),
      "title": AttributeSpec(defaultValue: null, validate: "string|null"),
    },
    group: "inline",
    draggable: true,
  ),

  // A hard line break.
  "hard_break": NodeSpec(inline: true, group: "inline", selectable: false),
};

/// Specs for the marks in the basic schema.
final Map<String, MarkSpec> basicSchemaMarks = {
  // A link, with `href` and `title` attributes.
  "link": MarkSpec(
    attrs: {
      "href": AttributeSpec(validate: "string"),
      "title": AttributeSpec(defaultValue: null, validate: "string|null"),
    },
    inclusive: false,
  ),

  // An emphasis mark.
  "em": MarkSpec(),

  // A strong mark.
  "strong": MarkSpec(),

  // A code font mark.
  "code": MarkSpec(code: true),
};

/// The basic schema, roughly corresponding to the document schema used by
/// CommonMark, minus the list elements.
final Schema basicSchema = Schema(SchemaSpec(nodes: basicSchemaNodes, marks: basicSchemaMarks));
