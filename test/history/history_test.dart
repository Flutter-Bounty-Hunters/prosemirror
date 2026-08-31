import 'package:prosemirror/prosemirror.dart';
import 'package:test/test.dart';

import '../model/support/builders.dart';

void main() {
  group("history >", () {
    test("enables undo", () {
      var state = _mkState();
      state = _type(state, "a");
      state = _type(state, "b");
      expect(state.doc.eq(doc(p("ab"))), isTrue);
      state = _command(state, undo);
      expect(state.doc.eq(doc(p())), isTrue);
    });

    test("enables redo", () {
      var state = _mkState();
      state = _type(state, "a");
      state = _type(state, "b");
      state = _command(state, undo);
      expect(state.doc.eq(doc(p())), isTrue);
      state = _command(state, redo);
      expect(state.doc.eq(doc(p("ab"))), isTrue);
    });

    test("tracks multiple levels of history", () {
      var state = _mkState();
      state = _type(state, "a");
      state = _type(state, "b");
      state = state.apply(state.tr.insertText("c", 1));
      expect(state.doc.eq(doc(p("cab"))), isTrue);
      state = _command(state, undo);
      expect(state.doc.eq(doc(p("ab"))), isTrue);
      state = _command(state, undo);
      expect(state.doc.eq(doc(p())), isTrue);
      state = _command(state, redo);
      expect(state.doc.eq(doc(p("ab"))), isTrue);
      state = _command(state, redo);
      expect(state.doc.eq(doc(p("cab"))), isTrue);
      state = _command(state, undo);
      expect(state.doc.eq(doc(p("ab"))), isTrue);
    });

    test("starts a new event when newGroupDelay elapses", () {
      var state = _mkState(null, _Config(newGroupDelay: 1000));
      state = state.apply(state.tr.insertText("a").setTime(1000));
      state = state.apply(state.tr.insertText("b").setTime(1600));
      expect(undoDepth(state), 1);
      state = state.apply(state.tr.insertText("c").setTime(2700));
      expect(undoDepth(state), 2);
      state = _command(state, undo);
      state = state.apply(state.tr.insertText("d").setTime(2800));
      expect(undoDepth(state), 2);
    });

    test("starts a new event for non-adjacent changes", () {
      var state = _mkState(doc(p("abc")), _Config(newGroupDelay: 1000));
      state = state.apply(state.tr.insertText("x", 1));
      state = state.apply(state.tr.insertText("y", 5));
      expect(undoDepth(state), 2);
    });

    test("doesn't get confused by non-replacement steps when checking "
        "adjacency", () {
      var state = _mkState(doc(p()), _Config(newGroupDelay: 1000));
      state = state.apply(
        state.tr.insertText("x", 1).addMark(1, 2, schema.marks["em"]!.create())
            as Transaction,
      );
      state = state.apply(
        state.tr.insertText("y", 2).addMark(2, 3, schema.marks["em"]!.create())
            as Transaction,
      );
      expect(undoDepth(state), 1);
    });

    test("allows changes that aren't part of the history", () {
      var state = _mkState();
      state = _type(state, "hello");
      state = state.apply(
        state.tr.insertText("oops", 1).setMeta("addToHistory", false),
      );
      state = state.apply(
        state.tr.insertText("!", 10).setMeta("addToHistory", false),
      );
      state = _command(state, undo);
      expect(state.doc.eq(doc(p("oops!"))), isTrue);
    });

    test("doesn't get confused by an undo not adding any redo item", () {
      var state = _mkState();
      state = state.apply(state.tr.insertText("foo"));
      state = state.apply(
        (state.tr.replaceWith(1, 4, schema.text("bar")) as Transaction).setMeta(
          "addToHistory",
          false,
        ),
      );
      state = _command(state, undo);
      state = _command(state, redo);
      expect(state.doc.eq(doc(p("bar"))), isTrue);
    });

    test("can handle complex editing sequences", () {
      _unsyncedComplex(_mkState(), false);
    });

    test("can handle complex editing sequences with compression", () {
      _unsyncedComplex(_mkState(), true);
    });

    test("supports overlapping edits", () {
      var state = _mkState();
      state = _type(state, "hello");
      state = state.apply(closeHistory(state.tr));
      state = state.apply(state.tr.delete(1, 6) as Transaction);
      expect(state.doc.eq(doc(p())), isTrue);
      state = _command(state, undo);
      expect(state.doc.eq(doc(p("hello"))), isTrue);
      state = _command(state, undo);
      expect(state.doc.eq(doc(p())), isTrue);
    });

    test("supports overlapping edits that aren't collapsed", () {
      var state = _mkState();
      state = state.apply(
        state.tr.insertText("h", 1).setMeta("addToHistory", false),
      );
      state = _type(state, "ello");
      state = state.apply(closeHistory(state.tr));
      state = state.apply(state.tr.delete(1, 6) as Transaction);
      expect(state.doc.eq(doc(p())), isTrue);
      state = _command(state, undo);
      expect(state.doc.eq(doc(p("hello"))), isTrue);
      state = _command(state, undo);
      expect(state.doc.eq(doc(p("h"))), isTrue);
    });

    test("supports overlapping unsynced deletes", () {
      var state = _mkState();
      state = _type(state, "hi");
      state = state.apply(closeHistory(state.tr));
      state = _type(state, "hello");
      state = state.apply(
        (state.tr.delete(1, 8) as Transaction).setMeta("addToHistory", false),
      );
      expect(state.doc.eq(doc(p())), isTrue);
      state = _command(state, undo);
      expect(state.doc.eq(doc(p())), isTrue);
    });

    test("can go back and forth through history multiple times", () {
      var state = _mkState();
      state = _type(state, "one");
      state = _type(state, " two");
      state = state.apply(closeHistory(state.tr));
      state = _type(state, " three");
      state = state.apply(state.tr.insertText("zero ", 1));
      state = state.apply(closeHistory(state.tr));
      state = state.apply(state.tr.split(1) as Transaction);
      state = state.apply(
        state.tr.setSelection(TextSelection.create(state.doc, 1)),
      );
      state = _type(state, "top");
      for (var i = 0; i < 6; i++) {
        final redoTurn = i % 2 == 1;
        for (var j = 0; j < 4; j++) {
          state = _command(state, redoTurn ? redo : undo);
        }
        expect(
          state.doc.eq(
            redoTurn ? doc(p("top"), p("zero one two three")) : doc(p()),
          ),
          isTrue,
        );
      }
    });

    test("supports non-tracked changes next to tracked changes", () {
      var state = _mkState();
      state = _type(state, "o");
      state = state.apply(state.tr.split(1) as Transaction);
      state = state.apply(
        state.tr.insertText("zzz", 4).setMeta("addToHistory", false),
      );
      state = _command(state, undo);
      expect(state.doc.eq(doc(p("zzz"))), isTrue);
    });

    test("can go back and forth through history when preserving items", () {
      var state = _mkState();
      state = _type(state, "one");
      state = _type(state, " two");
      state = state.apply(closeHistory(state.tr));
      state = state.apply(
        state.tr
            .insertText("xxx", state.selection.head)
            .setMeta("addToHistory", false),
      );
      state = _type(state, " three");
      state = state.apply(state.tr.insertText("zero ", 1));
      state = state.apply(closeHistory(state.tr));
      state = state.apply(state.tr.split(1) as Transaction);
      state = state.apply(
        state.tr.setSelection(TextSelection.create(state.doc, 1)),
      );
      state = _type(state, "top");
      state = state.apply(
        state.tr.insertText("yyy", 1).setMeta("addToHistory", false),
      );
      for (var i = 0; i < 3; i++) {
        if (i == 2) {
          _compress(state);
        }
        for (var j = 0; j < 4; j++) {
          state = _command(state, undo);
        }
        expect(state.doc.eq(doc(p("yyyxxx"))), isTrue);
        for (var j = 0; j < 4; j++) {
          state = _command(state, redo);
        }
        expect(
          state.doc.eq(doc(p("yyytop"), p("zero one twoxxx three"))),
          isTrue,
        );
      }
    });

    test("restores selection on undo", () {
      var state = _mkState();
      state = _type(state, "hi");
      state = state.apply(closeHistory(state.tr));
      state = state.apply(
        state.tr.setSelection(TextSelection.create(state.doc, 1, 3)),
      );
      final selection = state.selection;
      state = state.apply(
        state.tr.replaceWith(selection.from, selection.to, schema.text("hello"))
            as Transaction,
      );
      final selection2 = state.selection;
      state = _command(state, undo);
      expect(state.selection.eq(selection), isTrue);
      state = _command(state, redo);
      expect(state.selection.eq(selection2), isTrue);
    });

    test("rebases selection on undo", () {
      var state = _mkState();
      state = _type(state, "hi");
      state = state.apply(closeHistory(state.tr));
      state = state.apply(
        state.tr.setSelection(TextSelection.create(state.doc, 1, 3)),
      );
      state = state.apply(
        state.tr.insert(1, schema.text("hello")) as Transaction,
      );
      state = state.apply(
        (state.tr.insert(1, schema.text("---")) as Transaction).setMeta(
          "addToHistory",
          false,
        ),
      );
      state = _command(state, undo);
      expect(state.selection.head, 6);
    });

    test("handles change overwriting in item-preserving mode", () {
      var state = _mkState(null, _Config(preserveItems: true));
      state = _type(state, "a");
      state = _type(state, "b");
      state = state.apply(closeHistory(state.tr));
      state = state.apply(
        state.tr.setSelection(TextSelection.create(state.doc, 1, 3)),
      );
      state = _type(state, "c");
      state = _command(state, undo);
      state = _command(state, undo);
      expect(state.doc.eq(doc(p())), isTrue);
    });

    test("supports querying for the undo and redo depth", () {
      var state = _mkState();
      state = _type(state, "a");
      expect(undoDepth(state), 1);
      expect(redoDepth(state), 0);
      state = state.apply(
        state.tr.insertText("b", 1).setMeta("addToHistory", false),
      );
      expect(undoDepth(state), 1);
      expect(redoDepth(state), 0);
      state = _command(state, undo);
      expect(undoDepth(state), 0);
      expect(redoDepth(state), 1);
      state = _command(state, redo);
      expect(undoDepth(state), 1);
      expect(redoDepth(state), 0);
    });

    test("all functions gracefully handle EditorStates without history", () {
      final state = EditorState.create(EditorStateConfig(schema: schema));
      expect(undoDepth(state), 0);
      expect(redoDepth(state), 0);
      expect(undo.execute(state), isFalse);
      expect(redo.execute(state), isFalse);
    });

    test("truncates history", () {
      var state = _mkState(null, _Config(depth: 2));
      for (var i = 1; i < 40; i++) {
        state = _type(state, "a");
        state = state.apply(closeHistory(state.tr));
        // JS truncated modulo (Dart's `%` is Euclidean, so use `remainder`).
        expect(undoDepth(state), (i - 2).remainder(21) + 2);
      }
    });

    test("supports transactions with multiple steps", () {
      var state = _mkState();
      state = state.apply(state.tr.insertText("a").insertText("b"));
      state = state.apply(state.tr.insertText("c", 1));
      expect(state.doc.eq(doc(p("cab"))), isTrue);
      state = _command(state, undo);
      expect(state.doc.eq(doc(p("ab"))), isTrue);
      state = _command(state, undo);
      expect(state.doc.eq(doc(p())), isTrue);
      state = _command(state, redo);
      expect(state.doc.eq(doc(p("ab"))), isTrue);
      state = _command(state, redo);
      expect(state.doc.eq(doc(p("cab"))), isTrue);
      state = _command(state, undo);
      expect(state.doc.eq(doc(p("ab"))), isTrue);
    });

    test("combines appended transactions in the event started by the base "
        "transaction", () {
      var state = _mkState(
        doc(p("x")),
        _Config(
          plugins: [
            Plugin(
              PluginSpec(
                appendTransaction: (transactions, oldState, newState) {
                  if (newState.doc.content.size == 4) {
                    return newState.tr.insert(1, schema.text("A"))
                        as Transaction;
                  }
                  return null;
                },
              ),
            ),
          ],
        ),
      );
      state = state.apply(state.tr.insert(2, schema.text("I")) as Transaction);
      expect(state.doc.eq(doc(p("AxI"))), isTrue);
      expect(undoDepth(state), 1);
      state = _command(state, undo);
      expect(state.doc.eq(doc(p("x"))), isTrue);
    });

    test("includes transactions appended to undo in the redo history", () {
      var state = _mkState(
        doc(p("x")),
        _Config(
          plugins: [
            Plugin(
              PluginSpec(
                appendTransaction: (transactions, oldState, newState) {
                  final add = transactions[0].getMeta("add");
                  if (add != null) {
                    return newState.tr.insert(1, schema.text(add as String))
                        as Transaction;
                  }
                  return null;
                },
              ),
            ),
          ],
        ),
      );
      state = state.apply(
        (state.tr.insert(2, schema.text("I")) as Transaction).setMeta(
          "add",
          "A",
        ),
      );
      expect(state.doc.eq(doc(p("AxI"))), isTrue);
      undo.execute(state, (tr) => state = state.apply(tr.setMeta("add", "B")));
      expect(state.doc.eq(doc(p("Bx"))), isTrue);
      redo.execute(state, (tr) => state = state.apply(tr.setMeta("add", "C")));
      expect(state.doc.eq(doc(p("CAxI"))), isTrue);
      state = _command(state, undo);
      expect(state.doc.eq(doc(p("Bx"))), isTrue);
    });

    test("doesn't close the history on appended transactions", () {
      var state = _mkState(
        doc(p("x")),
        _Config(
          plugins: [
            Plugin(
              PluginSpec(
                appendTransaction: (transactions, oldState, newState) {
                  final add = transactions[0].getMeta("add");
                  if (add != null) {
                    return newState.tr.insert(1, schema.text(add as String))
                        as Transaction;
                  }
                  return null;
                },
              ),
            ),
          ],
        ),
      );
      state = state.apply(
        (state.tr.insert(2, schema.text("R")) as Transaction).setMeta(
          "add",
          "A",
        ),
      );
      state = state.apply(state.tr.insert(3, schema.text("M")) as Transaction);
      state = _command(state, undo);
      expect(state.doc.eq(doc(p("x"))), isTrue);
    });

    test("supports rebasing", () {
      // This test simulates a collab editing session where the local editor
      // receives a step (`right`) that's on top of the parent step (`base`) of
      // the last local step (`left`).

      // Shared base step
      var state = _mkState();
      state = _type(state, "base");
      state = state.apply(closeHistory(state.tr));
      final baseDoc = state.doc;

      // Local unconfirmed step
      //
      //        - left
      //       /
      // base -
      //       \
      //        - right
      final rightStep = ReplaceStep(
        5,
        5,
        Slice(Fragment.from(schema.text(" right")), 0, 0),
      );
      state = state.apply(state.tr.step(rightStep) as Transaction);
      expect(state.doc.eq(doc(p("base right"))), isTrue);
      expect(undoDepth(state), 2);
      final leftStep = ReplaceStep(
        1,
        1,
        Slice(Fragment.from(schema.text("left ")), 0, 0),
      );

      // Receive remote step and rebase local unconfirmed step
      //
      // base --> left --> right'
      final tr = state.tr;
      tr.step(rightStep.invert(baseDoc));
      tr.step(leftStep);
      tr.step(rightStep.map(tr.mapping.slice(1))!);
      tr.mapping.setMirror(0, tr.steps.length - 1);
      tr.setMeta("addToHistory", false);
      tr.setMeta("rebased", 1);
      state = state.apply(tr);
      expect(state.doc.eq(doc(p("left base right"))), isTrue);
      expect(undoDepth(state), 2);

      // Undo local unconfirmed step
      //
      // base --> left
      state = _command(state, undo);
      expect(state.doc.eq(doc(p("left base"))), isTrue);

      // Redo local unconfirmed step
      //
      // base --> left --> right'
      state = _command(state, redo);
      expect(state.doc.eq(doc(p("left base right"))), isTrue);
    });

    test("properly maps selection when rebasing", () {
      var state = _mkState(doc(p("123456789ABCD")));
      state = state.apply(
        state.tr.setSelection(TextSelection.create(state.doc, 6, 13)),
      );
      state = state.apply(state.tr.delete(6, 13) as Transaction);
      final rebase =
          (state.tr
                      .insert(6, schema.text("6789ABC"))
                      .insert(14, schema.text("E"))
                      .delete(6, 13)
                  as Transaction)
              .setMeta("rebased", 1)
              .setMeta("addToHistory", false);
      rebase.mapping.setMirror(0, 2);
      state = state.apply(rebase);
      state = _command(state, undo);
    });
  });
}

EditorState _mkState([Node? document, _Config? config]) {
  final plugins = <Plugin>[
    config != null
        ? history(
            HistoryOptions(
              depth: config.depth,
              newGroupDelay: config.newGroupDelay,
            ),
          )
        : _plugin,
  ];
  if (config != null && config.preserveItems) {
    plugins.add(Plugin(PluginSpec(extra: {"historyPreserveItems": true})));
  }
  return EditorState.create(
    EditorStateConfig(
      schema: schema,
      doc: document,
      plugins: [...plugins, ...?config?.plugins],
    ),
  );
}

class _Config {
  _Config({
    this.newGroupDelay,
    this.depth,
    this.preserveItems = false,
    this.plugins,
  });

  final int? newGroupDelay;
  final int? depth;
  final bool preserveItems;
  final List<Plugin>? plugins;
}

final Plugin _plugin = history();

EditorState _type(EditorState state, String text) {
  return state.apply(state.tr.insertText(text));
}

EditorState _command(EditorState state, Command command) {
  command.execute(state, (tr) => state = state.apply(tr));
  return state;
}

void _unsyncedComplex(EditorState state, bool doCompress) {
  state = _type(state, "hello");
  state = state.apply(closeHistory(state.tr));
  state = _type(state, "!");
  state = state.apply(
    state.tr.insertText("....", 1).setMeta("addToHistory", false),
  );
  state = state.apply(state.tr.split(3) as Transaction);
  expect(state.doc.eq(doc(p(".."), p("..hello!"))), isTrue);
  state = state.apply(
    (state.tr.split(2) as Transaction).setMeta("addToHistory", false),
  );
  if (doCompress) {
    _compress(state);
  }
  state = _command(state, undo);
  state = _command(state, undo);
  expect(state.doc.eq(doc(p("."), p("...hello"))), isTrue);
  state = _command(state, undo);
  expect(state.doc.eq(doc(p("."), p("..."))), isTrue);
}

void _compress(EditorState state) {
  // NOTE: This is mutating stuff that shouldn't be mutated. Not safe to do
  // outside of these tests.
  (_plugin.getState(state) as HistoryState).done =
      (_plugin.getState(state) as HistoryState).done.compress();
}
