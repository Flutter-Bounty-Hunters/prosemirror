import 'package:prosemirror/prosemirror.dart';
import 'package:prosemirror/tables.dart';
import 'package:prosemirror/test_builder.dart' show builders, NodeBuilder, NodeTags;

export 'package:prosemirror/test_builder.dart' show eq, NodeBuilder, NodeTags;

final Schema _schema = Schema(
  SchemaSpec(
    nodes: basicSchema.spec.nodes.append(
      tableNodes(
        TableNodesOptions(
          tableGroup: "block",
          cellContent: "block+",
          cellAttributes: {"test": CellAttributes(defaultValue: "default")},
        ),
      ),
    ),
    marks: basicSchema.spec.marks,
  ),
);

final Map<String, dynamic> _nodeBuilders = builders(_schema, {
  "p": {"nodeType": "paragraph"},
  "tr": {"nodeType": "table_row"},
  "td": {"nodeType": "table_cell"},
  "th": {"nodeType": "table_header"},
});

final NodeBuilder doc = _nodeBuilders["doc"] as NodeBuilder;
final NodeBuilder table = _nodeBuilders["table"] as NodeBuilder;
final NodeBuilder tr = _nodeBuilders["tr"] as NodeBuilder;
final NodeBuilder p = _nodeBuilders["p"] as NodeBuilder;
final NodeBuilder td = _nodeBuilders["td"] as NodeBuilder;
final NodeBuilder th = _nodeBuilders["th"] as NodeBuilder;

Node c(int colspan, int rowspan, [String text = "x"]) {
  return td({"colspan": colspan, "rowspan": rowspan}, p(text));
}

final Node c11 = c(1, 1);
final Node cEmpty = td(p());
final Node cCursor = td(p("x<cursor>"));
final Node cCursorBefore = td(p("<cursor>x"));
final Node cAnchor = td(p("x<anchor>"));
final Node cHead = td(p("x<head>"));

Node h(int colspan, int rowspan, [String text = "x"]) {
  return th({"colspan": colspan, "rowspan": rowspan}, p(text));
}

final Node h11 = h(1, 1);
final Node hEmpty = th(p());
final Node hCursor = th(p("x<cursor>"));

Selection selectionFor(Node document) {
  final cursor = document.tag["cursor"];
  if (cursor != null) {
    return TextSelection(document.resolve(cursor));
  }

  final $anchor = _resolveCell(document, document.tag["anchor"]);
  if ($anchor != null) {
    return CellSelection($anchor, _resolveCell(document, document.tag["head"]));
  }

  final node = document.tag["node"];
  if (node != null) {
    return NodeSelection(document.resolve(node));
  }

  throw StateError(
    "No selection found in document. Please tag the document with <cursor>, <node> or <anchor> and <head>",
  );
}

ResolvedPos? _resolveCell(Node document, int? tag) {
  if (tag == null) {
    return null;
  }
  return cellAround(document.resolve(tag));
}
