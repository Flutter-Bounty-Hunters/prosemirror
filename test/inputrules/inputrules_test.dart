import 'package:prosemirror/prosemirror.dart';
import 'package:test/test.dart';

import '../model/support/builders.dart';

void main() {
  group("Input rules >", () {
    group("text replacement >", () {
      test("turns a double dash into an em dash", () {
        final result = _type(doc(p("foo-<a>")), [emDash], "-");
        expect(result.eq(doc(p("foo—"))), isTrue);
      });

      test("turns three dots into an ellipsis", () {
        final result = _type(doc(p("foo..<a>")), [ellipsis], ".");
        expect(result.eq(doc(p("foo…"))), isTrue);
      });

      test("uses an opening double quote at a word boundary", () {
        final result = _type(doc(p("<a>")), smartQuotes, "\"");
        expect(result.eq(doc(p("“"))), isTrue);
      });

      test("uses a closing double quote mid word", () {
        final result = _type(doc(p("foo<a>")), smartQuotes, "\"");
        expect(result.eq(doc(p("foo”"))), isTrue);
      });

      test("uses an opening single quote at a word boundary", () {
        final result = _type(doc(p("<a>")), smartQuotes, "'");
        expect(result.eq(doc(p("‘"))), isTrue);
      });

      test("uses a closing single quote mid word", () {
        final result = _type(doc(p("foo<a>")), smartQuotes, "'");
        expect(result.eq(doc(p("foo’"))), isTrue);
      });
    });

    group("code exclusion >", () {
      test("does not fire inside a code mark", () {
        final result = _type(doc(p(code("a-<a>b"))), [emDash], "-");
        expect(result.eq(doc(p(code("a-b")))), isTrue);
      });

      test("fires in normal text", () {
        final result = _type(doc(p("a-<a>b")), [emDash], "-");
        expect(result.eq(doc(p("a—b"))), isTrue);
      });
    });

    group("wrappingInputRule >", () {
      test("wraps a paragraph in a blockquote", () {
        final rule = wrappingInputRule(
          RegExp(r'^\s*>\s$'),
          schema.nodes["blockquote"]!,
        );
        final result = _type(doc(p("><a>")), [rule], " ");
        expect(result.eq(doc(blockquote(p()))), isTrue);
      });

      test("joins an adjacent blockquote above", () {
        final rule = wrappingInputRule(
          RegExp(r'^\s*>\s$'),
          schema.nodes["blockquote"]!,
        );
        final result = _type(doc(blockquote(p("hi")), p("><a>")), [rule], " ");
        expect(result.eq(doc(blockquote(p("hi"), p()))), isTrue);
      });
    });

    group("textblockTypeInputRule >", () {
      test("turns a paragraph into a level one heading", () {
        final rule = textblockTypeInputRule(
          RegExp(r'^(#{1,6})\s$'),
          schema.nodes["heading"]!,
          (RegExpMatch match) => {"level": match.group(1)!.length},
        );
        final result = _type(doc(p("#<a>")), [rule], " ");
        expect(result.eq(doc(h1())), isTrue);
      });

      test("turns a paragraph into a level two heading", () {
        final rule = textblockTypeInputRule(
          RegExp(r'^(#{1,6})\s$'),
          schema.nodes["heading"]!,
          (RegExpMatch match) => {"level": match.group(1)!.length},
        );
        final result = _type(doc(p("##<a>")), [rule], " ");
        expect(result.eq(doc(h2())), isTrue);
      });
    });

    group("undoInputRule >", () {
      test("reverts the last input rule to the typed text", () {
        var state = _stateAfterTyping(doc(p("foo-<a>")), [emDash], "-");
        expect(state.doc.eq(doc(p("foo—"))), isTrue);

        final reverted = undoInputRule.execute(
          state,
          (tr) => state = state.apply(tr),
        );
        expect(reverted, isTrue);
        expect(state.doc.eq(doc(p("foo--"))), isTrue);
      });

      test("returns false when no input rule was the last action", () {
        final state = _stateAfterTyping(doc(p("hello<a>")), [emDash], "x");

        var dispatched = false;
        final reverted = undoInputRule.execute(state, (tr) {
          dispatched = true;
        });
        expect(reverted, isFalse);
        expect(dispatched, isFalse);
      });
    });
  });
}

Node _type(Node document, List<InputRule> rules, String text) {
  return _stateAfterTyping(document, rules, text).doc;
}

EditorState _stateAfterTyping(
  Node document,
  List<InputRule> rules,
  String text,
) {
  final plugin = inputRules(rules: rules);
  final caret = document.tag["a"] ?? document.content.size;
  var state = EditorState.create(
    EditorStateConfig(
      doc: document,
      selection: TextSelection.create(document, caret),
      plugins: [plugin],
    ),
  );
  runInputRules(
    state,
    caret,
    caret,
    text,
    rules,
    plugin,
    (tr) => state = state.apply(tr),
  );
  return state;
}
