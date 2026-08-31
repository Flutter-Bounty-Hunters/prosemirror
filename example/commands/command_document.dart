import 'package:prosemirror/prosemirror.dart';

void main() {
  // Step 1 - Create a new editor state.
  // A doc must contain at least one block ("block+"), so the smallest valid new
  // document is a single empty paragraph.
  final draft = _CommandDraft(
    EditorState.create(
      EditorStateConfig(
        doc: schema.node("doc", null, [schema.node("paragraph")]),
      ),
    ),
  );

  final wrapParagraphInBulletList = autoJoin(
    wrapIn(schema.nodes["bullet_list"]!),
    ["bullet_list"],
  );

  _printDocument("1. New document (one empty paragraph)", draft.document);

  // Step 2 - Insert a paragraph of text.
  // The commands package works on an EditorState, so ordinary content insertion
  // goes through transactions and block-level editing goes through commands.
  draft.insertText("This is the opening paragraph of text.");
  _printDocument("2. Inserted a paragraph of text", draft.document);

  // Step 3 - Insert an image.
  // `splitBlock` creates the next paragraph, then a transaction inserts the
  // inline image node into that paragraph.
  _expectCommand("splitBlock", splitBlock.execute(draft.state, draft.dispatch));
  draft.insertNode(
    schema.node("image", {"src": "sunset.png", "alt": "A sunset over the sea"}),
  );
  _printDocument(
    "3. Inserted an image (wrapped in a paragraph)",
    draft.document,
  );

  // Step 4 - Insert three bullet points.
  // Draft each bullet as a normal paragraph, use `wrapIn` to turn it into a
  // one-item list, and use `autoJoin` to merge adjacent bullet lists.
  _expectCommand("splitBlock", splitBlock.execute(draft.state, draft.dispatch));
  draft.insertText("First bullet point");
  draft.selectCurrentTextblock();
  _expectCommand(
    "autoJoin(wrapIn(bullet_list))",
    wrapParagraphInBulletList.execute(draft.state, draft.dispatch),
  );

  draft.select(Selection.atEnd(draft.document));
  _expectCommand("splitBlock", splitBlock.execute(draft.state, draft.dispatch));
  _expectCommand(
    "liftEmptyBlock",
    liftEmptyBlock.execute(draft.state, draft.dispatch),
  );
  draft.insertText("Second bullet point");
  draft.selectCurrentTextblock();
  _expectCommand(
    "autoJoin(wrapIn(bullet_list))",
    wrapParagraphInBulletList.execute(draft.state, draft.dispatch),
  );

  draft.select(Selection.atEnd(draft.document));
  _expectCommand("splitBlock", splitBlock.execute(draft.state, draft.dispatch));
  _expectCommand(
    "liftEmptyBlock",
    liftEmptyBlock.execute(draft.state, draft.dispatch),
  );
  draft.insertText("Third bullet point");
  draft.selectCurrentTextblock();
  _expectCommand(
    "autoJoin(wrapIn(bullet_list))",
    wrapParagraphInBulletList.execute(draft.state, draft.dispatch),
  );
  _printDocument("4. Inserted three bullet points", draft.document);

  // Step 5 - Insert a final paragraph.
  // At the end of a list item, Enter creates another list item. Running
  // `liftEmptyBlock` from that empty item lifts it out to a regular paragraph.
  draft.select(Selection.atEnd(draft.document));
  _expectCommand("splitBlock", splitBlock.execute(draft.state, draft.dispatch));
  _expectCommand(
    "liftEmptyBlock",
    liftEmptyBlock.execute(draft.state, draft.dispatch),
  );
  draft.insertText("This is the final paragraph.");
  _printDocument("5. Inserted a final paragraph", draft.document);

  // Prove the result is a schema-valid document (runs our content matcher).
  draft.document.check();
  print("\nFinal document is schema-valid.");
  print("Document size (positions): ${draft.document.content.size}");
}

void _expectCommand(String name, bool applied) {
  if (!applied) {
    throw StateError("$name did not apply.");
  }
}

class _CommandDraft {
  _CommandDraft(this.state);

  EditorState state;

  Node get document => state.doc;

  void dispatch(Transaction tr) {
    state = state.apply(tr);
  }

  void insertText(String text) {
    state = state.apply(state.tr.insertText(text));
  }

  void insertNode(Node node) {
    state = state.apply(state.tr.replaceSelectionWith(node));
  }

  void selectCurrentTextblock() {
    final position = state.selection.$from;
    setTextSelection(position.start(), position.end());
  }

  void select(Selection selection) {
    state = state.apply(state.tr.setSelection(selection));
  }

  void setTextSelection(int from, int to) {
    select(TextSelection.create(state.doc, from, to));
  }
}

void _printDocument(String label, Node document) {
  print("$label:");
  print("  ${document.toString()}");
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
        attrs: <String, AttributeSpec>{
          "src": AttributeSpec(),
          "alt": AttributeSpec(defaultValue: null),
        },
      ),
      "text": NodeSpec(group: "inline"),
    },
  ),
);
