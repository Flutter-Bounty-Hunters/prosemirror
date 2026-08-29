/// The test `Schema` used by the ported prosemirror-model tests.
///
/// This mirrors `prosemirror-test-builder`'s schema, which is
/// `schema-basic`'s nodes extended with the `schema-list` nodes (via
/// [addListNodes]) plus `schema-basic`'s marks. All DOM-only spec fields
/// (`toDOM`, `parseDOM`, and friends) are intentionally omitted, since this
/// port is non-DOM.
///
/// The node/mark specs are transcribed from:
///  - `schema-basic/src/schema-basic.ts`
///  - `schema-list/src/schema-list.ts`
library;

import 'package:prosemirror/prosemirror.dart';

/// The test schema: schema-basic nodes + list nodes + schema-basic marks.
final Schema schema = Schema(
  SchemaSpec(
    nodes: addListNodes(
      OrderedMap<NodeSpec>.from(_basicNodes),
      "paragraph block*",
      "block",
    ),
    marks: _basicMarks,
  ),
);

/// Adds the list-related node types to a node spec map.
///
/// Faithful to `schema-list`'s `addListNodes`: it appends `ordered_list`,
/// `bullet_list`, and `list_item`. `itemContent` becomes the content
/// expression for list items, and `listGroup` (when given) becomes the group
/// of the two list container nodes.
OrderedMap<NodeSpec> addListNodes(
  OrderedMap<NodeSpec> nodes,
  String itemContent, [
  String? listGroup,
]) {
  return nodes.append(<String, NodeSpec>{
    "ordered_list": NodeSpec(
      attrs: {
        "order": const AttributeSpec(defaultValue: 1, validate: "number"),
      },
      content: "list_item+",
      group: listGroup,
    ),
    "bullet_list": NodeSpec(content: "list_item+", group: listGroup),
    "list_item": NodeSpec(content: itemContent, defining: true),
  });
}

/// The schema-basic node specs (DOM fields omitted), in significant order.
final Map<String, NodeSpec> _basicNodes = {
  "doc": NodeSpec(content: "block+"),
  "paragraph": NodeSpec(content: "inline*", group: "block"),
  "blockquote": NodeSpec(content: "block+", group: "block", defining: true),
  "horizontal_rule": NodeSpec(group: "block"),
  "heading": NodeSpec(
    attrs: {"level": const AttributeSpec(defaultValue: 1, validate: "number")},
    content: "inline*",
    group: "block",
    defining: true,
  ),
  "code_block": NodeSpec(
    content: "text*",
    marks: "",
    group: "block",
    code: true,
    defining: true,
  ),
  "text": NodeSpec(group: "inline"),
  "image": NodeSpec(
    inline: true,
    attrs: {
      "src": const AttributeSpec(validate: "string"),
      "alt": const AttributeSpec(defaultValue: null, validate: "string|null"),
      "title": const AttributeSpec(defaultValue: null, validate: "string|null"),
    },
    group: "inline",
    draggable: true,
  ),
  "hard_break": NodeSpec(inline: true, group: "inline", selectable: false),
};

/// The schema-basic mark specs (DOM fields omitted), in significant order.
final Map<String, MarkSpec> _basicMarks = {
  "link": MarkSpec(
    attrs: {
      "href": const AttributeSpec(validate: "string"),
      "title": const AttributeSpec(defaultValue: null, validate: "string|null"),
    },
    inclusive: false,
  ),
  "em": MarkSpec(),
  "strong": MarkSpec(),
  "code": MarkSpec(code: true),
};
