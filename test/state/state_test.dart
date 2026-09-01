/// Port of `prosemirror-state`'s `test/test-state.ts`.
library;

import 'dart:convert';

import 'package:prosemirror/prosemirror.dart';
import 'package:test/test.dart';

import 'package:prosemirror/test_builder.dart';

void main() {
  group("State >", () {
    test("creates a default doc", () {
      final state = EditorState.create(EditorStateConfig(schema: schema));
      expect(eq(state.doc, document(p())), isTrue);
    });

    test("creates a default selection", () {
      final state = EditorState.create(EditorStateConfig(doc: document(p("foo"))));
      expect(state.selection.from, 1);
      expect(state.selection.to, 1);
    });

    test("applies transform transactions", () {
      final state = EditorState.create(EditorStateConfig(schema: schema));
      final newState = state.apply(state.tr.insertText("hi"));
      expect(eq(state.doc, document(p())), isTrue);
      expect(eq(newState.doc, document(p("hi"))), isTrue);
      expect(newState.selection.from, 3);
    });

    test("supports plugin fields", () {
      final state = EditorState.create(EditorStateConfig(plugins: [_messageCountPlugin], schema: schema));
      final newState = state.apply(state.tr).apply(state.tr);
      expect(_messageCountPlugin.getState(state), 0);
      expect(_messageCountPlugin.getState(newState), 2);
    });

    test("can be serialized to JSON", () {
      var state = EditorState.create(EditorStateConfig(plugins: [_messageCountPlugin], doc: document(p("ok"))));
      state = state.apply(state.tr.setSelection(TextSelection.create(state.doc, 3)));
      final pluginProps = {"count": _messageCountPlugin};
      final expected = {
        "doc": {
          "type": "doc",
          "content": [
            {
              "type": "paragraph",
              "content": [
                {"type": "text", "text": "ok"},
              ],
            },
          ],
        },
        "selection": {"type": "text", "anchor": 3, "head": 3},
        "count": 1,
      };
      final json = state.toJSON(pluginProps);
      expect(jsonEncode(json), jsonEncode(expected));
      final copy = EditorState.fromJSON(
        EditorStateConfig(plugins: [_messageCountPlugin], schema: schema),
        json,
        pluginProps,
      );
      expect(eq(copy.doc, state.doc), isTrue);
      expect(copy.selection.from, 3);
      expect(_messageCountPlugin.getState(copy), 1);

      final limitedJSON = state.toJSON();
      expect(limitedJSON["doc"], isNotNull);
      expect(limitedJSON["messageCount\$"], isNull);
      final deserialized = EditorState.fromJSON(
        EditorStateConfig(plugins: [_messageCountPlugin], schema: schema),
        limitedJSON,
      );
      expect(_messageCountPlugin.getState(deserialized), 0);
    });

    test("supports specifying and persisting storedMarks", () {
      final state = EditorState.create(EditorStateConfig(doc: document(p("ok")), storedMarks: [schema.mark("em")]));
      expect(state.storedMarks!.length, 1);
      final copy = EditorState.fromJSON(EditorStateConfig(schema: schema), state.toJSON());
      expect(copy.storedMarks!.length, 1);
    });

    test("supports reconfiguration", () {
      final state = EditorState.create(EditorStateConfig(plugins: [_messageCountPlugin], schema: schema));
      expect(_messageCountPlugin.getState(state), 0);
      final without = state.reconfigure();
      expect(_messageCountPlugin.getState(without), isNull);
      expect(without.plugins.length, 0);
      expect(eq(without.doc, document(p())), isTrue);
      final reAdd = without.reconfigure(plugins: [_messageCountPlugin]);
      expect(_messageCountPlugin.getState(reAdd), 0);
      expect(reAdd.plugins.length, 1);
    });

    test("allows plugins to filter transactions", () {
      final state = EditorState.create(EditorStateConfig(plugins: [_transactionPlugin], schema: schema));
      var applied = state.applyTransaction(state.tr.insertText("X"));
      expect(eq(applied.state.doc, document(p("X"))), isTrue);
      expect(applied.transactions.length, 1);
      applied = state.applyTransaction(state.tr.insertText("Y").setMeta("filtered", true));
      expect(applied.state, state);
      expect(applied.transactions.length, 0);
    });

    test("allows plugins to append transactions", () {
      final state = EditorState.create(EditorStateConfig(plugins: [_transactionPlugin], schema: schema));
      final applied = state.applyTransaction(state.tr.insertText("X").setMeta("append", true));
      expect(eq(applied.state.doc, document(p("XA"))), isTrue);
      expect(applied.transactions.length, 2);
    });

    test("stores a reference to a root transaction for appended transactions", () {
      final state = EditorState.create(
        EditorStateConfig(
          schema: schema,
          plugins: [
            Plugin(PluginSpec(appendTransaction: (transactions, oldState, newState) => newState.tr.insertText("Y"))),
          ],
        ),
      );
      final transactions = state.applyTransaction(state.tr.insertText("X")).transactions;
      expect(transactions.length, 2);
      expect(transactions[1].getMeta("appendedTransaction"), transactions[0]);
    });

    test("supports JSON.stringify toJSON arguments", () {
      final someObject = {"someKey": EditorState.create(EditorStateConfig(schema: schema))};
      final encoded = jsonEncode(
        someObject,
        toEncodable: (Object? value) {
          if (value is EditorState) {
            return value.toJSON();
          }
          return value;
        },
      );
      expect(encoded.isNotEmpty, isTrue);
    });
  });

  group("Plugin >", () {
    test("calls prop functions bound to the plugin", () {
      final testProp = _messageCountPlugin.props["testProp"] as Object? Function();
      expect(testProp(), _messageCountPlugin);
    });

    test("can be found by key", () {
      final state = EditorState.create(EditorStateConfig(plugins: [_messageCountPlugin], schema: schema));
      expect(_messageCountKey.get(state), _messageCountPlugin);
      expect(_messageCountKey.getState(state), 0);
    });

    test("generates new keys", () {
      final plugin1 = Plugin(PluginSpec());
      final plugin2 = Plugin(PluginSpec());
      expect(plugin1.key != plugin2.key, isTrue);
      final key1 = PluginKey("foo");
      final key2 = PluginKey("foo");
      expect(key1.key != key2.key, isTrue);
    });
  });
}

final PluginKey _messageCountKey = PluginKey("messageCount");

final Plugin _messageCountPlugin = Plugin(
  PluginSpec(
    key: _messageCountKey,
    state: StateField(
      init: (config, instance) => 0,
      apply: (tr, count, oldState, newState) => (count as int) + 1,
      toJSON: (count) => count,
      fromJSON: (config, value, state) => value,
    ),
    props: <String, Object?>{"testProp": (Plugin self) => self},
  ),
);

final Plugin _transactionPlugin = Plugin(
  PluginSpec(
    filterTransaction: (tr, state) => tr.getMeta("filtered") != true,
    appendTransaction: (trs, oldState, state) {
      final last = trs.isNotEmpty ? trs[trs.length - 1] : null;
      if (last != null && last.getMeta("append") == true) {
        return state.tr.insertText("A");
      }
      return null;
    },
  ),
);
