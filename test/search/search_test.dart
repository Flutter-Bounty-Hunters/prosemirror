import 'package:prosemirror/prosemirror.dart';
import 'package:test/test.dart';

import 'builders.dart';

void main() {
  group("Search >", () {
    group("Find next >", () {
      test("can find the next match", () {
        _testSelectionCommand(
          const _Query(search: "two"),
          p("one <c>two<d> two"),
          findNext,
        );
      });

      test("can find the next match from selection", () {
        _testSelectionCommand(
          const _Query(search: "two"),
          p("one <a>two<b> <c>two<d>"),
          findNext,
        );
      });

      test("wraps around at end of document", () {
        _testSelectionCommand(
          const _Query(search: "two"),
          p("one <c>two<d> <a>two<b>"),
          findNext,
        );
      });

      test("doesn't wrap around in no-wrap mode", () {
        _testSelectionCommand(
          const _Query(search: "two"),
          p("one two <a>two<b>"),
          findNextNoWrap,
        );
      });

      test("can search a limited range", () {
        _testSelectionCommand(
          const _Query(search: "two", range: SearchRange(from: 7, to: 11)),
          p("one two <a>two<b>"),
          findNext,
        );
      });

      test("wraps within the given range", () {
        _testSelectionCommand(
          const _Query(search: "two", range: SearchRange(from: 3, to: 11)),
          p("two <c>two<d> <a>two<b>"),
          findNext,
        );
      });

      test("can match in nested structure", () {
        _testSelectionCommand(
          const _Query(search: "one"),
          doc(
            blockquote(p("para <a>one<b>"), p("para two")),
            p("and <c>one<d>"),
          ),
          findNext,
        );
      });
    });

    group("Find previous >", () {
      test("can find the previous match", () {
        _testSelectionCommand(
          const _Query(search: "two"),
          p("one <c>two<d> <a>two<b>"),
          findPrev,
        );
      });

      test("wraps around at start of document", () {
        _testSelectionCommand(
          const _Query(search: "two"),
          p("one <a>two<b> <c>two<d>"),
          findPrev,
        );
      });

      test("doesn't wrap around in no-wrap mode", () {
        _testSelectionCommand(
          const _Query(search: "two"),
          p("one <a>two<b> two"),
          findPrevNoWrap,
        );
      });

      test("can search a limited range", () {
        _testSelectionCommand(
          const _Query(search: "two", range: SearchRange(from: 7, to: 11)),
          p("one two <a>two<b>"),
          findPrev,
        );
      });

      test("wraps within the given range", () {
        _testSelectionCommand(
          const _Query(search: "two", range: SearchRange(from: 3, to: 11)),
          p("two <a>two<b> <c>two<d>"),
          findPrev,
        );
      });

      test("can match in nested structure", () {
        _testSelectionCommand(
          const _Query(search: "one"),
          doc(
            blockquote(p("para <c>one<d>"), p("para two")),
            p("and <a>one<b>"),
          ),
          findPrev,
        );
      });
    });

    group("Replace next >", () {
      test("moves to a match when not already on one", () {
        _testCommand(
          const _Query(search: "one", replace: "two"),
          p("one one"),
          p("<a>one<b> one"),
          replaceNext,
        );
      });

      test("can replace the current match", () {
        _testCommand(
          const _Query(search: "one", replace: "two"),
          p("<a>one<b> two"),
          p("<a>two<b> two"),
          replaceNext,
        );
      });

      test("moves selection to the next match", () {
        _testCommand(
          const _Query(search: "one", replace: "two"),
          p("<a>one<b> one"),
          p("two <a>one<b>"),
          replaceNext,
        );
      });

      test("wraps around the end of the document", () {
        _testCommand(
          const _Query(search: "one", replace: "two"),
          p("one <a>one<b>"),
          p("<a>one<b> two"),
          replaceNext,
        );
      });

      test("doesn't wrap with wrapping disabled", () {
        _testCommand(
          const _Query(search: "one", replace: "two"),
          p("one <a>one<b>"),
          p("one <a>two<b>"),
          replaceNextNoWrap,
        );
      });

      test("can replace within a limited range", () {
        _testCommand(
          const _Query(
            search: "one",
            replace: "two",
            range: SearchRange(from: 0, to: 7),
          ),
          p("one <a>one<b> one"),
          p("<a>one<b> two one"),
          replaceNext,
        );
      });

      test("can reuse parts of the match", () {
        _testCommand(
          const _Query(search: r"\((.*?)\)", regexp: true, replace: r"[$1]"),
          p("<a>(hi)<b> (x)"),
          p("[hi] <a>(x)<b>"),
          replaceNext,
        );
      });

      test("can reuse matched leaf nodes", () {
        _testCommand(
          const _Query(search: r"\((.*?)\)", regexp: true, replace: r"[$1]"),
          p("<a>(", img(), ")<b> (x)"),
          p("[", img(), "] <a>(x)<b>"),
          replaceNext,
        );
      });

      test("can replace in nested structure", () {
        _testCommand(
          const _Query(search: "one", replace: "two"),
          doc(blockquote(p("para <a>one<b>"), p("para two")), p("and one")),
          doc(blockquote(p("para two"), p("para two")), p("and <a>one<b>")),
          replaceNext,
        );
      });

      test("doesn't replace reused content", () {
        var state = _makeState(
          const _Query(search: ".(eu).", regexp: true, replace: r"p$1t"),
          p("<a>deux<b> trois"),
        );
        Transaction? transaction;

        replaceNext.execute(state, (tr) => transaction = tr);

        expect(transaction, isNotNull);
        expect(eq(transaction!.doc, p("peut trois")), isTrue);
        expect(transaction!.mapping.map(2), 2);
      });

      test("can handle multiple references to groups", () {
        _testCommand(
          const _Query(search: "(ab)-(cd)", regexp: true, replace: r"$2$1$2"),
          p("<a>ab-cd<b>"),
          p("<a>cdabcd<b>"),
          replaceNext,
        );
      });

      test("replaces non-matched groups with nothing", () {
        _testCommand(
          const _Query(search: "(ab)|(cd)", regexp: true, replace: r"x$2"),
          p("<a>ab<b>"),
          p("<a>x<b>"),
          replaceNext,
        );
      });

      test("supports matches in string replacements", () {
        _testCommand(
          const _Query(search: "one", replace: r"$&$&"),
          p("<a>one<b>"),
          p("<a>oneone<b>"),
          replaceNext,
        );
      });

      test("ignores invalid replacement group markers", () {
        _testCommand(
          const _Query(search: "one", replace: r"$+"),
          p("<a>one<b> two"),
          p("<a><b> two"),
          replaceNext,
        );
      });
    });

    group("Replace current >", () {
      test("does nothing when not at a match", () {
        _testCommand(
          const _Query(search: "one", replace: "two"),
          p("one"),
          null,
          replaceCurrent,
        );
      });

      test("selects the replacement", () {
        _testCommand(
          const _Query(search: "one", replace: "two"),
          p("<a>one<b>"),
          p("<a>two<b>"),
          replaceCurrent,
        );
      });

      test("replaces delimiters with regexp", () {
        _testCommand(
          const _Query(search: "“([^”]+)”", regexp: true, replace: r"$1"),
          p("This is the <a>“footnote”<b> text"),
          p("This is the <a>footnote<b> text"),
          replaceCurrent,
        );
      });

      test("replaces inside non-leaf atoms", () {
        final footnote = _footnoteBuilders();
        _testCommand(
          const _Query(search: "footnote", replace: "NOTE"),
          footnote.p(
            "text",
            footnote.footnote("This is the <a>footnote<b> text"),
          ),
          footnote.p("text", footnote.footnote("This is the <a>NOTE<b> text")),
          replaceCurrent,
        );
      });

      test("replaces delimiters with regexp inside non-leaf atoms", () {
        final footnote = _footnoteBuilders();
        _testCommand(
          const _Query(search: "“([^”]+)”", regexp: true, replace: r"$1"),
          footnote.p(
            "text",
            footnote.footnote("This is the <a>“footnote”<b> text"),
          ),
          footnote.p(
            "text",
            footnote.footnote("This is the <a>footnote<b> text"),
          ),
          replaceCurrent,
        );
      });
    });

    group("Replace all >", () {
      test("replaces all instances", () {
        _testCommand(
          const _Query(search: "one", replace: "two"),
          doc(p("this one"), p("that one"), blockquote(p("another one"))),
          doc(p("this two"), p("that two"), blockquote(p("another two"))),
          replaceAll,
        );
      });

      test("supports using parts of the match", () {
        _testCommand(
          const _Query(search: r"(\d+)-(\d+)", regexp: true, replace: r"$1:$2"),
          p("50-20 vs 40-15"),
          p("50:20 vs 40:15"),
          replaceAll,
        );
      });

      test("works within a limited range", () {
        _testCommand(
          const _Query(
            search: "one",
            replace: "two",
            range: SearchRange(from: 2, to: 17),
          ),
          p("one one one one one"),
          p("one two two two one"),
          replaceAll,
        );
      });

      test("works on zero-length matches", () {
        _testCommand(
          const _Query(search: ".*", regexp: true, replace: "/"),
          doc(p("hello world")),
          doc(p("/")),
          replaceAll,
        );
      });
    });

    group("Filter >", () {
      test("lets you replace only emphasized texts", () {
        _testCommand(
          _Query(search: "one", replace: "two", filter: _emphasizedOnly),
          doc(
            p("this one"),
            p("that ", em("one")),
            blockquote(p("another ", em("one"))),
          ),
          doc(
            p("this one"),
            p("that ", em("two")),
            blockquote(p("another ", em("two"))),
          ),
          replaceAll,
        );
      });
    });
  });
}

EditorState _makeState(_Query query, Node document) {
  final anchor = document.tag["a"];
  final head = document.tag["b"];
  return EditorState.create(
    EditorStateConfig(
      doc: document,
      selection: anchor == null
          ? null
          : TextSelection.create(document, anchor, head),
      plugins: [
        search(initialQuery: query.toSearchQuery(), initialRange: query.range),
      ],
    ),
  );
}

void _testSelectionCommand(_Query query, Node document, Command command) {
  var state = _makeState(query, document);
  final result = command.execute(state, (tr) => state = state.apply(tr));
  final anchor = document.tag["c"];
  final head = document.tag["d"];

  expect(result, anchor != null);
  if (anchor != null) {
    expect(
      state.selection.eq(TextSelection.create(document, anchor, head)),
      isTrue,
    );
  }
}

void _testCommand(
  _Query query,
  Node start,
  Node? expectedDocument,
  Command command,
) {
  var state = _makeState(query, start);
  final result = command.execute(state, (tr) => state = state.apply(tr));

  expect(result, expectedDocument != null);
  if (expectedDocument != null) {
    final expectedState = _makeState(query, expectedDocument);
    expect(eq(state.doc, expectedState.doc), isTrue);
    expect(state.selection.eq(expectedState.selection), isTrue);
  }
}

bool _emphasizedOnly(EditorState state, SearchResult result) {
  return state.doc.rangeHasMark(
    result.from,
    result.to,
    state.schema.marks["em"]!.create(),
  );
}

_FootnoteBuilders _footnoteBuilders() {
  final footnoteSchema = Schema(
    SchemaSpec(
      nodes: schema.spec.nodes.addBefore(
        "image",
        "footnote",
        NodeSpec(group: "inline", content: "text*", inline: true, atom: true),
      ),
      marks: schema.spec.marks,
    ),
  );
  final builders = SearchBuilders(footnoteSchema, {
    "p": {"nodeType": "paragraph"},
    "pre": {"nodeType": "code_block"},
    "h1": {"nodeType": "heading", "level": 1},
    "h2": {"nodeType": "heading", "level": 2},
    "h3": {"nodeType": "heading", "level": 3},
    "li": {"nodeType": "list_item"},
    "ul": {"nodeType": "bullet_list"},
    "ol": {"nodeType": "ordered_list"},
    "br": {"nodeType": "hard_break"},
    "footnote": {"nodeType": "footnote"},
    "img": {"nodeType": "image", "src": "img.png"},
    "hr": {"nodeType": "horizontal_rule"},
    "a": {"markType": "link", "href": "foo"},
  });
  return _FootnoteBuilders(
    p: builders.node("p"),
    footnote: builders.node("footnote"),
  );
}

class _Query {
  const _Query({
    required this.search,
    this.regexp = false,
    this.replace = "",
    this.range,
    this.filter,
  });

  final String search;
  final bool regexp;
  final String replace;
  final SearchRange? range;
  final SearchResultFilter? filter;

  SearchQuery toSearchQuery() {
    return SearchQuery(
      search: search,
      regexp: regexp,
      replace: replace,
      filter: filter,
    );
  }
}

class _FootnoteBuilders {
  _FootnoteBuilders({required this.p, required this.footnote});

  final SearchNodeBuilder p;
  final SearchNodeBuilder footnote;
}
