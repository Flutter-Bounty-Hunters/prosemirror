import 'package:prosemirror/prosemirror.dart';

void main() {
  // Create a new document — the smallest valid doc is one empty paragraph.
  final startingDocument = schema.node("doc", null, [schema.node("paragraph")]);

  // A Transform is seeded with the starting document. Each method below records
  // a step and advances `transform.doc`; the methods return the Transform, so
  // in real code they chain (`transform.insert(...).insert(...)`).
  final transform = Transform(startingDocument);

  // Insert a paragraph of text — position 1 is inside the empty paragraph, so
  // this drops inline text into it.
  transform.insert(1, schema.text("This is the opening paragraph of text."));
  _printStep(transform, "Inserted a paragraph of text");

  // Insert an image — `image` is an inline leaf, so it rides in its own
  // paragraph, appended at the current end of the document.
  transform.insert(transform.doc.content.size, _createParagraphNodeWithImage());
  _printStep(transform, "Inserted an image (wrapped in a paragraph)");

  // Insert three bullet points.
  transform.insert(
    transform.doc.content.size,
    schema.node("bullet_list", null, [
      _createListItemNode("First bullet point"),
      _createListItemNode("Second bullet point"),
      _createListItemNode("Third bullet point"),
    ]),
  );
  _printStep(transform, "Inserted three bullet points");

  // Insert a final paragraph.
  transform.insert(
    transform.doc.content.size,
    schema.node("paragraph", null, [schema.text("This is the final paragraph.")]),
  );
  _printStep(transform, "Inserted a final paragraph");

  final document = transform.doc;

  // Prove the result is a schema-valid document (runs our content matcher).
  document.check();
  print("\nFinal document is schema-valid. ✅");
  print("Document size (positions): ${document.content.size}");

  _demonstrateTransformAbilities(transform, startingDocument);
}

/// Shows the three things a Transform gives you over a raw `Node.replace`:
/// a recorded step list, invertibility (undo), and position mapping.
void _demonstrateTransformAbilities(Transform transform, Node startingDocument) {
  print("\n--- What the transform layer adds ---");

  // 1. The change is recorded as discrete, replayable steps.
  print("Steps recorded: ${transform.steps.length}");

  // 2. Invertibility → undo. Inverting every step (against the document it was
  //    applied to) and replaying them in reverse rebuilds the original doc.
  final undo = Transform(transform.doc);
  for (var index = transform.steps.length - 1; index >= 0; index--) {
    undo.step(transform.steps[index].invert(transform.docs[index]));
  }
  print("Undo returns to the starting document: ${undo.doc.eq(startingDocument)}");

  // 3. Position mapping. The caret used to sit at position 1 (inside the first,
  //    empty paragraph). After all those insertions, the transform can tell us
  //    where that position moved to — no manual bookkeeping required.
  final mappedCaret = transform.mapping.map(1);
  print("A caret at old position 1 now maps to position $mappedCaret");
}

Node _createParagraphNodeWithImage() {
  return schema.node("paragraph", null, [
    schema.node("image", {"src": "sunset.png", "alt": "A sunset over the sea"}),
  ]);
}

Node _createListItemNode(String text) {
  return schema.node("list_item", null, [
    schema.node("paragraph", null, [schema.text(text)]),
  ]);
}

void _printStep(Transform transform, String label) {
  print("$label:");
  print("  ${transform.doc}");
}

/// A minimal schema (a non-DOM subset of prosemirror-schema-basic + list nodes):
/// a document of blocks, paragraphs of inline content, an inline image, and
/// bullet lists of list items. Identical to example/model/compose_document.dart.
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
