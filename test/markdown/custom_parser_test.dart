import 'package:prosemirror/prosemirror.dart';
import 'package:test/test.dart';

import 'package:prosemirror/test_builder.dart';

final Map<String, dynamic> _b = builders(markdownSchema, {
  "p": {"nodeType": "paragraph"},
  "h1": {"nodeType": "heading", "level": 1},
  "h2": {"nodeType": "heading", "level": 2},
  "hr": {"nodeType": "horizontal_rule"},
  "li": {"nodeType": "list_item"},
  "ol": {"nodeType": "ordered_list"},
  "ol3": {"nodeType": "ordered_list", "order": 3},
  "ul": {"nodeType": "bullet_list"},
  "pre": {"nodeType": "code_block"},
  "a": {"markType": "link", "href": "foo"},
  "br": {"nodeType": "hard_break"},
  "img": {"nodeType": "image", "src": "img.png", "alt": "x"},
});

final NodeBuilder document = _b["doc"] as NodeBuilder;
final NodeBuilder p = _b["p"] as NodeBuilder;
final NodeBuilder h1 = _b["h1"] as NodeBuilder;
final NodeBuilder h2 = _b["h2"] as NodeBuilder;
final NodeBuilder hr = _b["hr"] as NodeBuilder;
final NodeBuilder li = _b["li"] as NodeBuilder;
final NodeBuilder ol = _b["ol"] as NodeBuilder;
final NodeBuilder ol3 = _b["ol3"] as NodeBuilder;
final NodeBuilder ul = _b["ul"] as NodeBuilder;
final NodeBuilder pre = _b["pre"] as NodeBuilder;
final NodeBuilder blockquote = _b["blockquote"] as NodeBuilder;
final NodeBuilder br = _b["br"] as NodeBuilder;
final NodeBuilder img = _b["img"] as NodeBuilder;
final MarkBuilder a = _b["a"] as MarkBuilder;
final MarkBuilder link = _b["link"] as MarkBuilder;
final MarkBuilder em = _b["em"] as MarkBuilder;
final MarkBuilder strong = _b["strong"] as MarkBuilder;
final MarkBuilder code = _b["code"] as MarkBuilder;

void main() {
  group("Markdown > custom parser >", () {
    test("ignores a blockquote", () {
      _parseWith(_ignoreBlockquoteParser, "> hello!", document(p("hello!")));
    });

    test("converts softbreaks to hard break nodes", () {
      _parseWith(_ignoreBlockquoteParser, "hello\nworld!", document(p("hello", br(), "world!")));
    });

    test("supports named attribute callbacks from the public barrel", () {
      _parseWith(_headingParser, "# hello", document(h1("hello")));
    });
  });
}

final MarkdownParser _ignoreBlockquoteParser = MarkdownParser(
  markdownSchema,
  MarkdownTokenizer.commonMark(html: false),
  {
    "blockquote": ParseSpec(ignore: true),
    "paragraph": ParseSpec(block: "paragraph"),
    "softbreak": ParseSpec(node: "hard_break"),
  },
);

final MarkdownParser _headingParser = MarkdownParser(markdownSchema, MarkdownTokenizer.commonMark(html: false), {
  "heading": ParseSpec(block: "heading", getAttrs: _headingAttributes),
});

void _parseWith(MarkdownParser parser, String markdown, Node expectedDocument) {
  expect(eq(parser.parse(markdown), expectedDocument), isTrue);
}

Attrs? _headingAttributes(MarkdownToken token, List<MarkdownToken> tokenStream, int index) {
  return {"level": int.parse(token.tag.substring(1))};
}
