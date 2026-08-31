import 'package:prosemirror/prosemirror.dart';
import 'package:test/test.dart';

import 'builders.dart';

void main() {
  group("Markdown > custom parser >", () {
    test("ignores a blockquote", () {
      _parseWith(_ignoreBlockquoteParser, "> hello!", doc(p("hello!")));
    });

    test("converts softbreaks to hard break nodes", () {
      _parseWith(
        _ignoreBlockquoteParser,
        "hello\nworld!",
        doc(p("hello", br(), "world!")),
      );
    });

    test("supports named attribute callbacks from the public barrel", () {
      _parseWith(_headingParser, "# hello", doc(h1("hello")));
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

final MarkdownParser _headingParser = MarkdownParser(
  markdownSchema,
  MarkdownTokenizer.commonMark(html: false),
  {"heading": ParseSpec(block: "heading", getAttrs: _headingAttributes)},
);

void _parseWith(MarkdownParser parser, String markdown, Node expectedDocument) {
  expect(eq(parser.parse(markdown), expectedDocument), isTrue);
}

Attrs? _headingAttributes(
  MarkdownToken token,
  List<MarkdownToken> tokenStream,
  int index,
) {
  return {"level": int.parse(token.tag.substring(1))};
}
