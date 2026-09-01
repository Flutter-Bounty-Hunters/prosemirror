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
  group("Markdown > default parser and serializer >", () {
    test("parses a paragraph", () {
      _same("hello!", document(p("hello!")));
    });

    test("parses headings", () {
      _same("# one\n\n## two\n\nthree", document(h1("one"), h2("two"), p("three")));
    });

    test("parses a blockquote", () {
      _same("> once\n\n> > twice", document(blockquote(p("once")), blockquote(blockquote(p("twice")))));
    });

    test("parses a bullet list", () {
      _same(
        "* foo\n\n  * bar\n\n  * baz\n\n* quux",
        document(ul(li(p("foo"), ul(li(p("bar")), li(p("baz")))), li(p("quux")))),
      );
    });

    test("parses an ordered list", () {
      _same(
        "1. Hello\n\n2. Goodbye\n\n3. Nest\n\n   1. Hey\n\n   2. Aye",
        document(ol(li(p("Hello")), li(p("Goodbye")), li(p("Nest"), ol(li(p("Hey")), li(p("Aye")))))),
      );
    });

    test("preserves ordered list start number", () {
      _same("3. Foo\n\n4. Bar", document(ol3(li(p("Foo")), li(p("Bar")))));
    });

    test("can parse a heading in a list", () {
      _same("* # Foo", document(ul(li(h1("Foo")))));
    });

    test("parses a code block", () {
      _same(
        "Some code:\n\n```\nHere it is\n```\n\nPara",
        document(
          p("Some code:"),
          markdownSchema.node("code_block", {"params": ""}, [markdownSchema.text("Here it is")]),
          p("Para"),
        ),
      );
    });

    test("parses an indented code block", () {
      _parse("Some code:\n\n    Here it is\n\nPara", document(p("Some code:"), pre("Here it is"), p("Para")));
    });

    test("parses a fenced code block with info string", () {
      _same(
        "foo\n\n```javascript\n1\n```",
        document(p("foo"), markdownSchema.node("code_block", {"params": "javascript"}, [markdownSchema.text("1")])),
      );
    });

    test("parses inline marks", () {
      _same(
        "Hello. Some *em* text, some **strong** text, and some `code`",
        document(p("Hello. Some ", em("em"), " text, some ", strong("strong"), " text, and some ", code("code"))),
      );
    });

    test("parses overlapping inline marks", () {
      _same(
        "This is **strong *emphasized text with `code` in* it**",
        document(p("This is ", strong("strong ", em("emphasized text with ", code("code"), " in"), " it"))),
      );
    });

    test("parses links inside strong text", () {
      _same("**[link](foo) is bold**", document(p(strong(a("link"), " is bold"))));
    });

    test("parses emphasis inside links", () {
      _same("[link *foo **bar** `#`*](foo)", document(p(a("link ", em("foo ", strong("bar"), " ", code("#"))))));
    });

    test("parses code mark inside strong text", () {
      _same("**`code` is bold**", document(p(strong(code("code"), " is bold"))));
    });

    test("parses code mark containing backticks", () {
      _same("``` one backtick: ` two backticks: `` ```", document(p(code("one backtick: ` two backticks: ``"))));
    });

    test("parses code mark containing only whitespace", () {
      _serialize(document(p("Three spaces: ", code("   "))), "Three spaces: `   `");
    });

    test("parses hard breaks", () {
      _same("foo\\\nbar", document(p("foo", br(), "bar")));
      _same("*foo\\\nbar*", document(p(em("foo", br(), "bar"))));
    });

    test("parses links", () {
      _same("My [link](foo) goes to foo", document(p("My ", a("link"), " goes to foo")));
    });

    test("parses urls", () {
      _same(
        "Link to <https://prosemirror.net>",
        document(p("Link to ", link({"href": "https://prosemirror.net"}, "https://prosemirror.net"))),
      );
    });

    test("correctly serializes relative urls", () {
      _same("[foo.html](foo.html)", document(p(link({"href": "foo.html"}, "foo.html"))));
    });

    test("can handle link titles", () {
      _same('[a](x.html "title \\"quoted\\"")', document(p(link({"href": "x.html", "title": 'title "quoted"'}, "a"))));
    });

    test("does not escape underscores in link", () {
      _same("[link](http://foo.com/a_b_c)", document(p(link({"href": "http://foo.com/a_b_c"}, "link"))));
    });

    test("parses emphasized urls", () {
      _same(
        "Link to *<https://prosemirror.net>*",
        document(p("Link to ", em(link({"href": "https://prosemirror.net"}, "https://prosemirror.net")))),
      );
    });

    test("parses an image", () {
      _same("Here's an image: ![x](img.png)", document(p("Here's an image: ", img())));
    });

    test("parses a line break", () {
      _same("line one\\\nline two", document(p("line one", br(), "line two")));
    });

    test("parses a horizontal rule", () {
      _same("one two\n\n---\n\nthree", document(p("one two"), hr(), p("three")));
    });

    test("ignores HTML tags", () {
      _same("Foo < img> bar", document(p("Foo < img> bar")));
    });

    test("does not accidentally generate list markup", () {
      _same("1\\. foo", document(p("1. foo")));
    });

    test("does not fail with line break inside inline mark", () {
      _serialize(document(p(strong("text1\ntext2"))), "**text1\ntext2**");
    });

    test("drops trailing hard breaks", () {
      _serialize(document(p("a", br(), br())), "a");
    });

    test("expels enclosing whitespace from inside emphasis", () {
      _serialize(
        document(p("Some emphasized text with", strong(em("  whitespace   ")), "surrounding the emphasis.")),
        "Some emphasized text with  ***whitespace***   surrounding the emphasis.",
      );
    });

    test("expels whitespace from emphasis with a nested mark", () {
      _serialize(document(p("One", em(" two ", a("three"), " four "), "five")), "One *two [three](foo) four* five");
    });

    test("properly expels whitespace before a hard break", () {
      _serialize(document(p(strong("foo ", br()), "bar")), "**foo** \\\nbar");
    });

    test("does not crash when a block ends in a hard break", () {
      _serialize(document(p(strong("foo", br()))), "**foo**");
    });

    test("drops nodes when all whitespace is expelled from them", () {
      _serialize(document(p("Text with", em(" "), "an emphasized space")), "Text with an emphasized space");
    });

    test("preserves list tightness", () {
      _same("* foo\n* bar", document(ul({"tight": true}, li(p("foo")), li(p("bar")))));
      _same("1. foo\n2. bar", document(ol({"tight": true}, li(p("foo")), li(p("bar")))));
    });

    test("does not put a code block after a list item inside the list item", () {
      _same("* list item\n\n```\ncode\n```", document(ul({"tight": true}, li(p("list item"))), pre("code")));
    });

    test("does not escape characters in code", () {
      _same("foo`*`", document(p("foo", code("*"))));
    });

    test("does not escape underscores between word characters", () {
      _same("abc_def", document(p("abc_def")));
    });

    test("does not escape strips of underscores between word characters", () {
      _same("abc___def", document(p("abc___def")));
    });

    test("escapes underscores at word boundaries", () {
      _same("\\_abc\\_", document(p("_abc_")));
    });

    test("escapes underscores surrounded by non-word characters", () {
      _same("/\\_abc\\_)", document(p("/_abc_)")));
    });

    test("ensure no escapes in url", () {
      _parse(
        "[text](https://example.com/_file/#~anchor)",
        document(p(a({"href": "https://example.com/_file/#~anchor"}, "text"))),
      );
    });

    test("ensure no escapes in autolinks", () {
      _same(
        "<https://example.com/_file/#~anchor>",
        document(p(a({"href": "https://example.com/_file/#~anchor"}, "https://example.com/_file/#~anchor"))),
      );
    });

    test("escapes exclamation marks in front of links", () {
      _serialize(document(p("!", a("text"))), "\\![text](foo)");
    });

    test("escapes URL characters in links and images", () {
      _serialize(document(p(a({"href": "foo):"}, "link"))), "[link](foo\\):)");
      _serialize(document(p(a({"href": "(foo"}, "link"))), "[link](\\(foo)");
      _serialize(document(p(img({"src": "foo):"}))), "![x](foo\\):)");
      _serialize(document(p(img({"src": "(foo"}))), "![x](\\(foo)");
      _serialize(document(p(a({"title": "bar", "href": 'foo%20"'}, "link"))), '[link](foo%20\\" "bar")');
    });

    test("escapes extra characters from options", () {
      final markdownSerializer = MarkdownSerializer(
        defaultMarkdownSerializer.nodes,
        defaultMarkdownSerializer.marks,
        MarkdownSerializerOptions(escapeExtraCharacters: RegExp(r"[|!]")),
      );
      expect(markdownSerializer.serialize(document(p("foo|bar!"))), "foo\\|bar\\!");
    });

    test("supports named node serializers from the public barrel", () {
      final markdownSerializer = MarkdownSerializer({
        ...defaultMarkdownSerializer.nodes,
        "paragraph": _serializeCustomParagraph,
      }, defaultMarkdownSerializer.marks);

      expect(markdownSerializer.serialize(document(p("hello"))), "custom: hello");
    });

    test("escapes list markers inside lists", () {
      _same("* 1\\. hi\n\n* x", document(ul(li(p("1. hi")), li(p("x")))));
    });

    test("does not escape list markers in the middle of paragraphs", () {
      _same("123 [0. com](foo)\n\n123 [2. 2](foo)", document(p("123 ", a("0. com")), p("123 ", a("2. 2"))));
    });

    test("does not escape list markers without space after them", () {
      _same("1.2kg", document(p("1.2kg")));
    });

    test("escapes ATX heading markers with space after them", () {
      _same("\\### text", document(p("### text")));
    });

    test("escapes ATX heading markers followed by the end of line", () {
      _same("\\###", document(p("###")));
    });

    test("does not escape ATX heading markers without space after them", () {
      _same("#hashtag", document(p("#hashtag")));
    });

    test("does not escape ATX heading markers consisting of more than six in a sequence", () {
      _same("#######", document(p("#######")));
    });

    test("keeps Unicode space after ATX heading markers when escaping", () {
      _same("\\#　こんにちは", document(p("#　こんにちは")));
    });

    test("does not escape block-start characters in header", () {
      _same("# 1. foo", document(h1("1. foo")));
    });

    test("does not escape plus markers", () {
      _same("+++", document(p("+++")));
    });

    test("code block fence adjusts to content", () {
      _same("````\n```\ncode\n```\n````", document(pre("```\ncode\n```")));
    });

    test("parses a code block that ends with an empty line", () {
      const originalText = "1\n";
      final markdownText = defaultMarkdownSerializer.serialize(
        document(markdownSchema.node("code_block", {"params": ""}, [markdownSchema.text(originalText)])),
      );
      _same(
        markdownText,
        document(markdownSchema.node("code_block", {"params": ""}, [markdownSchema.text(originalText)])),
      );
    });

    test("can expel leading whitespace from overlapping emphasis", () {
      _serialize(document(p(strong("f"), em(strong("oo"), " bar"))), "**f*oo*** *bar*");
    });

    test("can expel trailing whitespace from overlapping emphasis", () {
      _serialize(document(p(strong("f"), em(strong("oo "), "bar"))), "**f*oo*** *bar*");
    });
  });
}

void _parse(String markdown, Node expectedDocument) {
  expect(eq(defaultMarkdownParser.parse(markdown), expectedDocument), isTrue);
}

void _serialize(Node document, String expectedMarkdown) {
  expect(defaultMarkdownSerializer.serialize(document), expectedMarkdown);
}

void _same(String markdown, Node expectedDocument) {
  _parse(markdown, expectedDocument);
  _serialize(expectedDocument, markdown);
}

void _serializeCustomParagraph(MarkdownSerializerState state, Node node, Node parent, int index) {
  state.write("custom: ");
  state.renderInline(node, false);
  state.closeBlock(node);
}
