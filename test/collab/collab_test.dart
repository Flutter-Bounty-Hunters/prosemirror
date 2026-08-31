import 'package:prosemirror/prosemirror.dart';
import 'package:test/test.dart';

import '../model/support/builders.dart';

void main() {
  group("Collaboration >", () {
    test("converges for simple changes", () {
      final server = _DummyServer();
      server.type(0, "hi");
      server.type(1, "ok", 3);
      server.type(0, "!", 5);
      server.type(1, "...", 1);
      server.expectConverged("...hiok!");
    });

    test("converges for multiple local changes", () {
      final server = _DummyServer();
      server.type(0, "hi");
      server.delay(0, () {
        server.type(0, "A");
        server.type(1, "X");
        server.type(0, "B");
        server.type(1, "Y");
      });
      server.expectConverged("hiXYAB");
    });

    test("converges with three peers", () {
      final server = _DummyServer(peerCount: 3);
      server.type(0, "A");
      server.type(1, "U");
      server.type(2, "X");
      server.type(0, "B");
      server.type(1, "V");
      server.type(2, "C");
      server.expectConverged("AUXBVC");
    });

    test("converges with three peers and multiple steps", () {
      final server = _DummyServer(peerCount: 3);
      server.type(0, "A");
      server.delay(1, () {
        server.type(1, "U");
        server.type(2, "X");
        server.type(0, "B");
        server.type(1, "V");
        server.type(2, "C");
      });
      server.expectConverged("AXBCUV");
    });

    test("supports undo", () {
      final server = _DummyServer();
      server.type(0, "A");
      server.type(1, "B");
      server.type(0, "C");
      server.undo(1);
      server.expectConverged("AC");
      server.type(1, "D");
      server.type(0, "E");
      server.expectConverged("ACDE");
    });

    test("supports redo", () {
      final server = _DummyServer();
      server.type(0, "A");
      server.type(1, "B");
      server.type(0, "C");
      server.undo(1);
      server.redo(1);
      server.type(1, "D");
      server.type(0, "E");
      server.expectConverged("ABCDE");
    });

    test("supports deep undo", () {
      final server = _DummyServer(document: doc(p("hello"), p("bye")));
      server.update(0, _selectNear(6));
      server.update(1, _selectNear(11));
      server.type(0, "!");
      server.type(1, "!");
      server.update(0, (state) => closeHistory(state.tr));
      server.delay(0, () {
        server.type(0, " ...");
        server.type(1, " ,,,");
      });
      server.update(0, (state) => closeHistory(state.tr));
      server.type(0, "*");
      server.type(1, "*");
      server.undo(0);
      server.expectConverged(doc(p("hello! ..."), p("bye! ,,,*")));
      server.undo(0);
      server.undo(0);
      server.expectConverged(doc(p("hello"), p("bye! ,,,*")));
      server.redo(0);
      server.redo(0);
      server.redo(0);
      server.expectConverged(doc(p("hello! ...*"), p("bye! ,,,*")));
      server.undo(0);
      server.undo(0);
      server.expectConverged(doc(p("hello!"), p("bye! ,,,*")));
      server.undo(1);
      server.expectConverged(doc(p("hello!"), p("bye")));
    });

    test("supports undo with clashing events", () {
      final server = _DummyServer(document: doc(p("hello")));
      server.update(0, _selectNear(6));
      server.type(0, "A");
      server.delay(0, () {
        server.type(0, "B", 4);
        server.type(0, "C", 5);
        server.type(0, "D", 1);
        server.update(1, (state) => state.tr.delete(2, 5) as Transaction);
      });
      server.expectConverged("DhoA");
      server.undo(0);
      server.undo(0);
      server.expectConverged("ho");
      expect(server.states[0].selection.head, 3);
    });

    test("handles conflicting steps", () {
      final server = _DummyServer(document: doc(p("abcde")));
      server.delay(0, () {
        server.update(0, (state) => state.tr.delete(3, 4) as Transaction);
        server.type(0, "x");
        server.update(1, (state) => state.tr.delete(2, 5) as Transaction);
      });
      server.undo(0);
      server.undo(0);
      server.expectConverged(doc(p("ae")));
    });

    test("can undo simultaneous typing", () {
      final server = _DummyServer(document: doc(p("A"), p("B")));
      server.update(0, _selectNear(2));
      server.update(1, _selectNear(5));
      server.delay(0, () {
        server.type(0, "1");
        server.type(0, "2");
        server.type(1, "x");
        server.type(1, "y");
      });
      server.expectConverged(doc(p("A12"), p("Bxy")));
      server.undo(0);
      server.expectConverged(doc(p("A"), p("Bxy")));
      server.undo(1);
      server.expectConverged(doc(p("A"), p("B")));
    });

    test("tracks configured version and client identity", () {
      var state = _createCollabState(
        config: const CollabConfig(version: 7, clientID: "client-a"),
      );

      expect(getVersion(state), 7);
      expect(sendableSteps(state), isNull);

      state = state.apply(state.tr.insertText("A"));
      final sendable = sendableSteps(state);

      expect(sendable, isNotNull);
      expect(sendable!.version, 7);
      expect(sendable.clientID, "client-a");
      expect(sendable.steps, hasLength(1));
      expect(sendable.origins, hasLength(1));
      expect(sendable.origins.single.steps, sendable.steps);
    });

    test("confirms local steps received from the authority", () {
      var state = _createCollabState(
        config: const CollabConfig(version: 3, clientID: "client-a"),
      );
      state = state.apply(state.tr.insertText("A"));

      final sendable = sendableSteps(state)!;
      state = state.apply(
        receiveTransaction(state, sendable.steps, [sendable.clientID]),
      );

      expect(getVersion(state), 4);
      expect(sendableSteps(state), isNull);
      expect(state.doc.eq(doc(p("A"))), isTrue);
    });

    test("applies remote steps outside the undo history", () {
      final state = _createCollabState();
      final remoteTransaction = state.tr.insertText("A");
      final received = receiveTransaction(state, remoteTransaction.steps, [
        "remote-client",
      ]);
      final updated = state.apply(received);

      expect(received.getMeta("addToHistory"), isFalse);
      expect(getVersion(updated), 1);
      expect(updated.doc.eq(doc(p("A"))), isTrue);
    });

    test("maps text selections backward on request", () {
      var state = _createCollabState(document: doc(p("ab")));
      state = state.apply(
        state.tr.setSelection(TextSelection.create(state.doc, 2)),
      );

      final remoteTransaction = state.tr.insertText("X", 2);
      final received = receiveTransaction(state, remoteTransaction.steps, [
        "remote-client",
      ], const ReceiveTransactionOptions(mapSelectionBackward: true));
      final updated = state.apply(received);

      expect(updated.doc.eq(doc(p("aXb"))), isTrue);
      expect(updated.selection.head, 2);
    });
  });
}

final Plugin _historyPlugin = history();
final Command _undoHistoryCommand = undo;
final Command _redoHistoryCommand = redo;

Transaction Function(EditorState state) _selectNear(int position) {
  return (state) {
    return state.tr.setSelection(Selection.near(state.doc.resolve(position)));
  };
}

EditorState _createCollabState({
  CollabConfig config = const CollabConfig(),
  Node? document,
}) {
  final plugin = collab(config);
  return EditorState.create(
    EditorStateConfig(
      doc: document,
      schema: schema,
      plugins: [_historyPlugin, plugin],
    ),
  );
}

class _DummyServer {
  _DummyServer({Node? document, int peerCount = 2}) {
    for (var peerIndex = 0; peerIndex < peerCount; peerIndex++) {
      final plugin = collab();
      plugins.add(plugin);
      states.add(
        EditorState.create(
          EditorStateConfig(
            doc: document,
            schema: schema,
            plugins: [_historyPlugin, plugin],
          ),
        ),
      );
    }
  }

  final List<EditorState> states = <EditorState>[];
  final List<Plugin> plugins = <Plugin>[];
  final List<Step> steps = <Step>[];
  final List<Object> clientIDs = <Object>[];
  final List<int> delayed = <int>[];

  void sync(int peerIndex) {
    final state = states[peerIndex];
    final version = getVersion(state);
    if (version != steps.length) {
      states[peerIndex] = state.apply(
        receiveTransaction(
          state,
          steps.sublist(version),
          clientIDs.sublist(version),
        ),
      );
    }
  }

  void send(int peerIndex) {
    final sendable = sendableSteps(states[peerIndex]);
    if (sendable != null && sendable.version == steps.length) {
      steps.addAll(sendable.steps);
      for (var stepIndex = 0; stepIndex < sendable.steps.length; stepIndex++) {
        clientIDs.add(sendable.clientID);
      }
    }
  }

  void broadcast(int peerIndex) {
    if (delayed.contains(peerIndex)) {
      return;
    }
    sync(peerIndex);
    send(peerIndex);
    for (var index = 0; index < states.length; index++) {
      if (index != peerIndex) {
        sync(index);
      }
    }
  }

  void update(
    int peerIndex,
    Transaction Function(EditorState state) transactionBuilder,
  ) {
    states[peerIndex] = states[peerIndex].apply(
      transactionBuilder(states[peerIndex]),
    );
    broadcast(peerIndex);
  }

  void type(int peerIndex, String text, [int? position]) {
    update(peerIndex, (state) {
      return state.tr.insertText(text, position ?? state.selection.head);
    });
  }

  void undo(int peerIndex) {
    undoCommand(peerIndex, _undoHistoryCommand);
  }

  void redo(int peerIndex) {
    undoCommand(peerIndex, _redoHistoryCommand);
  }

  void undoCommand(int peerIndex, Command command) {
    command.execute(states[peerIndex], (transaction) {
      update(peerIndex, (_) => transaction);
    });
  }

  void expectConverged(Object document) {
    final expected = document is String ? doc(p(document)) : document as Node;
    for (final state in states) {
      expect(state.doc.eq(expected), isTrue);
    }
  }

  void delay(int peerIndex, void Function() callback) {
    delayed.add(peerIndex);
    callback();
    delayed.removeLast();
    broadcast(peerIndex);
  }
}
