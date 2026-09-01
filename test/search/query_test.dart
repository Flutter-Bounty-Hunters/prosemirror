import 'package:prosemirror/prosemirror.dart';
import 'package:test/test.dart';

import 'package:prosemirror/test_builder.dart';

void main() {
  group("Search query >", () {
    test("can match plain strings", () {
      _testQuery(SearchQuery(search: "abc"), p("<s1>abc<e1> flakdj a<s2>abc<e2> aabbcc"));
    });

    test("skips overlapping matches", () {
      _testQuery(SearchQuery(search: "aba"), p("<s1>aba<e1>b<s2>aba<e2>."));
    });

    test("goes through multiple textblocks", () {
      _testQuery(SearchQuery(search: "12"), document(p("a<s1>12<e1>b"), p("..."), p("and <s2>12<e2>")));
    });

    test("matches across mark boundaries", () {
      _testQuery(SearchQuery(search: "two"), p("ab<s1>t", em("w"), "o<e1>oo"));
    });

    test("can match case-insensitive strings", () {
      _testQuery(SearchQuery(search: "abC", caseSensitive: false), p("<s1>aBc<e1> flakdj a<s2>ABC<e2>"));
    });

    test("can match literally", () {
      _testQuery(SearchQuery(search: r"a\nb", literal: true), p("a\nb <s1>a\\nb<e1>"));
    });

    test("can match by word", () {
      _testQuery(
        SearchQuery(search: "hello", wholeWord: true),
        p("<s1>hello<e1> hellothere <s2>hello<e2>\nello ahello ohellop"),
      );
    });

    test("doesn't match non-words by word", () {
      _testQuery(SearchQuery(search: "^_^", wholeWord: true), p("x<s1>^_^<e1>y <s2>^_^<e2>"));
    });

    test("can match regular expressions", () {
      _testQuery(SearchQuery(search: "a..b", regexp: true), p("<s1>appb<e1> apb"));
    });

    test("can match case-insensitive regular expressions", () {
      _testQuery(SearchQuery(search: "a..b", regexp: true, caseSensitive: false), p("<s1>Appb<e1> Apb"));
    });

    test("can match regular expressions through multiple textblocks", () {
      _testQuery(SearchQuery(search: "12", regexp: true), document(p("a<s1>12<e1>b"), p("..."), p("and <s2>12<e2>")));
    });

    test("can match regular expressions by word", () {
      _testQuery(SearchQuery(search: "a..", regexp: true, wholeWord: true), p("<s1>aap<e1> baap aapje <s2>a--<e2>w"));
    });
  });
}

void _testQuery(SearchQuery query, Node document) {
  final matches = <({int from, int to})>[];
  for (var index = 1; ; index++) {
    final start = document.tag["s$index"];
    final end = document.tag["e$index"];
    if (start == null || end == null) {
      break;
    }
    matches.add((from: start, to: end));
  }

  final state = EditorState.create(EditorStateConfig(doc: document));
  final forward = <({int from, int to})>[];
  for (var position = 0; ;) {
    final next = query.findNext(state, position);
    if (next == null) {
      break;
    }
    forward.add((from: next.from, to: next.to));
    position = next.to;
  }
  expect(forward, matches);

  final backward = <({int from, int to})>[];
  for (var position = document.content.size; ;) {
    final next = query.findPrev(state, position);
    if (next == null) {
      break;
    }
    backward.add((from: next.from, to: next.to));
    position = next.from;
  }
  expect(backward, matches.reversed.toList());
}
