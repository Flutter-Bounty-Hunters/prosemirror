import 'package:prosemirror/prosemirror.dart';

void main() {
  // Step 1 — Create a new document.
  // A doc must contain at least one block ("block+"), so the smallest valid new
  // document is a single empty paragraph.
  var document = schema.node("doc", null, [schema.node("paragraph")]);
  _printDocument("1. New document (one empty paragraph)", document);

  // Step 2 — Insert a paragraph of text.
  // Position 1 is inside that first, empty paragraph. We insert inline text there.
  final openingText = schema.text("This is the opening paragraph of text.");
  document = document.replace(1, 1, Slice(Fragment.from(openingText), 0, 0));
  _printDocument("2. Inserted a paragraph of text", document);

  // Step 3 — Insert an image.
  // `image` is an inline leaf node, so it lives inside a paragraph of its own.
  final imageParagraph = schema.node("paragraph", null, [
    schema.node("image", {"src": "sunset.png", "alt": "A sunset over the sea"}),
  ]);
  document = _appendNodes(document, [imageParagraph]);
  _printDocument("3. Inserted an image (wrapped in a paragraph)", document);

  // Step 4 — Insert three bullet points.
  final bulletList = schema.node("bullet_list", null, [
    _createBulletNode("First bullet point"),
    _createBulletNode("Second bullet point"),
    _createBulletNode("Third bullet point"),
  ]);
  document = _appendNodes(document, [bulletList]);
  _printDocument("4. Inserted three bullet points", document);

  // Step 5 — Insert a final paragraph.
  final finalParagraph = schema.node("paragraph", null, [schema.text("This is the final paragraph.")]);
  document = _appendNodes(document, [finalParagraph]);
  _printDocument("5. Inserted a final paragraph", document);

  // Prove the result is a schema-valid document (runs our content matcher).
  document.check();
  print("\nFinal document is schema-valid. ✅");
  print("Document size (positions): ${document.content.size}");
}

/// Inserts [blocks] at the very end of [document] using the replace primitive.
///
/// The end of a node's content is the position `content.size`; replacing the
/// empty range there with a fully-closed slice (open depth 0 on both sides)
/// appends whole blocks.
Node _appendNodes(Node document, List<Node> blocks) {
  final end = document.content.size;
  return document.replace(end, end, Slice(Fragment.fromArray(blocks), 0, 0));
}

/// Builds one bullet: a `list_item` wrapping a paragraph of [text].
Node _createBulletNode(String text) {
  return schema.node("list_item", null, [
    schema.node("paragraph", null, [schema.text(text)]),
  ]);
}

void _printDocument(String label, Node document) {
  print("$label:");
  print("  ${document.toString()}");
}

/// A minimal schema (a non-DOM subset of prosemirror-schema-basic + list nodes):
/// a document of blocks, paragraphs of inline content, an inline image, and
/// bullet lists of list items.
final Schema schema = Schema(
  SchemaSpec(
    nodes: <String, NodeSpec>{
      "doc": NodeSpec(content: "block+"),
      "paragraph": NodeSpec(content: "inline*", group: "block"),
      "bullet_list": NodeSpec(content: "list_item+", group: "block"),
      "list_item": NodeSpec(content: "paragraph block*", defining: true),
      "image": NodeSpec(
        group: "inline",
        inline: true,
        attrs: <String, AttributeSpec>{"src": AttributeSpec(), "alt": AttributeSpec(defaultValue: null)},
      ),
      "text": NodeSpec(group: "inline"),
    },
  ),
);
