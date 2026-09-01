import 'package:prosemirror/prosemirror.dart';

/// Document schema for the data model used by CommonMark.
final Schema markdownSchema = Schema(SchemaSpec(nodes: markdownSchemaNodes, marks: markdownSchemaMarks));

/// Specs for the nodes defined by the markdown schema.
final Map<String, NodeSpec> markdownSchemaNodes = {
  "doc": NodeSpec(content: "block+"),
  "paragraph": NodeSpec(content: "inline*", group: "block"),
  "blockquote": NodeSpec(content: "block+", group: "block"),
  "horizontal_rule": NodeSpec(group: "block"),
  "heading": NodeSpec(
    attrs: {"level": AttributeSpec(defaultValue: 1, validate: "number")},
    content: "(text | image)*",
    group: "block",
    defining: true,
  ),
  "code_block": NodeSpec(
    attrs: {"params": AttributeSpec(defaultValue: "", validate: "string")},
    content: "text*",
    group: "block",
    code: true,
    defining: true,
    marks: "",
  ),
  "ordered_list": NodeSpec(
    attrs: {
      "order": AttributeSpec(defaultValue: 1, validate: "number"),
      "tight": AttributeSpec(defaultValue: false, validate: "boolean"),
    },
    content: "list_item+",
    group: "block",
  ),
  "bullet_list": NodeSpec(
    attrs: {"tight": AttributeSpec(defaultValue: false, validate: "boolean")},
    content: "list_item+",
    group: "block",
  ),
  "list_item": NodeSpec(content: "block+", defining: true),
  "text": NodeSpec(group: "inline"),
  "image": NodeSpec(
    attrs: {
      "src": AttributeSpec(validate: "string"),
      "alt": AttributeSpec(defaultValue: null, validate: "string|null"),
      "title": AttributeSpec(defaultValue: null, validate: "string|null"),
    },
    inline: true,
    group: "inline",
    draggable: true,
  ),
  "hard_break": NodeSpec(inline: true, group: "inline", selectable: false),
};

/// Specs for the marks defined by the markdown schema.
final Map<String, MarkSpec> markdownSchemaMarks = {
  "em": MarkSpec(),
  "strong": MarkSpec(),
  "link": MarkSpec(
    attrs: {
      "href": AttributeSpec(validate: "string"),
      "title": AttributeSpec(defaultValue: null, validate: "string|null"),
    },
    inclusive: false,
  ),
  "code": MarkSpec(code: true),
};
