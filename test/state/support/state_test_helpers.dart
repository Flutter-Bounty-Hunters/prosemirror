/// Shared test support for the ported `prosemirror-state` tests.
///
/// This is a faithful Dart port of `prosemirror-state`'s `test/state.ts`. It
/// exposes [selFor] (builds a default selection for a tagged document) and
/// [TestState] (a small mutable wrapper around an [EditorState] that makes
/// writing state/selection tests concise).
///
/// The position `tag` mechanism (`node.tag["a"]`) and the model builders are
/// reused from the existing model test support at
/// `test/model/support/builders.dart`.
library;

import 'package:prosemirror/prosemirror.dart';

import '../../model/support/builders.dart';

/// Builds a default selection for a document produced by the test builders.
///
/// Reads the `<a>`/`<b>` position tags: when `<a>` points into a node with
/// inline content it produces a [TextSelection] (spanning to `<b>` when
/// present), otherwise a [NodeSelection]. Falls back to [Selection.atStart]
/// when there is no `<a>` tag.
Selection selFor(Node doc) {
  final a = doc.tag["a"];
  if (a != null) {
    final $a = doc.resolve(a);
    if ($a.parent.inlineContent) {
      final b = doc.tag["b"];
      return TextSelection($a, b != null ? doc.resolve(b) : null);
    } else {
      return NodeSelection($a);
    }
  }
  return Selection.atStart(doc);
}

/// A mutable wrapper object that makes writing state tests easier.
class TestState {
  TestState({Selection? selection, Node? doc, Schema? schema}) {
    if (selection == null && doc != null) {
      selection = selFor(doc);
    }
    state = EditorState.create(
      EditorStateConfig(selection: selection, doc: doc, schema: schema),
    );
  }

  late EditorState state;

  void apply(Transaction tr) {
    state = state.apply(tr);
  }

  void command(Command cmd) {
    cmd(state, (tr) => apply(tr));
  }

  void type(String text) {
    apply(tr.insertText(text));
  }

  void deleteSelection() {
    apply(state.tr.deleteSelection());
  }

  void textSel(int anchor, [int? head]) {
    final sel = TextSelection.create(state.doc, anchor, head);
    state = state.apply(state.tr.setSelection(sel));
  }

  void nodeSel(int pos) {
    final sel = NodeSelection.create(state.doc, pos);
    state = state.apply(state.tr.setSelection(sel));
  }

  Node get doc => state.doc;

  Selection get selection => state.selection;

  Transaction get tr => state.tr;
}
