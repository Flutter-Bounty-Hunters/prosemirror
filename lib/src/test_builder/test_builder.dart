import 'package:prosemirror/prosemirror.dart';
import 'package:prosemirror/src/test_builder/build.dart';

export 'package:prosemirror/src/test_builder/build.dart';

final Schema schema = Schema(
  SchemaSpec(nodes: addListNodes(basicSchema.spec.nodes, "paragraph block*", "block"), marks: basicSchema.spec.marks),
);

final Map<String, Map<String, dynamic>> _builderConfig = {
  "p": {"nodeType": "paragraph"},
  "pre": {"nodeType": "code_block"},
  "h1": {"nodeType": "heading", "level": 1},
  "h2": {"nodeType": "heading", "level": 2},
  "h3": {"nodeType": "heading", "level": 3},
  "li": {"nodeType": "list_item"},
  "ul": {"nodeType": "bullet_list"},
  "ol": {"nodeType": "ordered_list"},
  "ol3": {"nodeType": "ordered_list", "order": 3},
  "br": {"nodeType": "hard_break"},
  "img": {"nodeType": "image", "src": "img.png", "alt": "x"},
  "hr": {"nodeType": "horizontal_rule"},
  "a": {"markType": "link", "href": "foo"},
};

final Map<String, dynamic> _b = builders(schema, _builderConfig);

final NodeBuilder document = _b["doc"] as NodeBuilder;
final NodeBuilder p = _b["p"] as NodeBuilder;
final NodeBuilder codeBlock = _b["code_block"] as NodeBuilder;
final NodeBuilder pre = _b["pre"] as NodeBuilder;
final NodeBuilder h1 = _b["h1"] as NodeBuilder;
final NodeBuilder h2 = _b["h2"] as NodeBuilder;
final NodeBuilder h3 = _b["h3"] as NodeBuilder;
final NodeBuilder li = _b["li"] as NodeBuilder;
final NodeBuilder ul = _b["ul"] as NodeBuilder;
final NodeBuilder ol = _b["ol"] as NodeBuilder;
final NodeBuilder ol3 = _b["ol3"] as NodeBuilder;
final NodeBuilder img = _b["img"] as NodeBuilder;
final NodeBuilder hr = _b["hr"] as NodeBuilder;
final NodeBuilder br = _b["br"] as NodeBuilder;
final NodeBuilder blockquote = _b["blockquote"] as NodeBuilder;
final MarkBuilder a = _b["a"] as MarkBuilder;
final MarkBuilder link = _b["link"] as MarkBuilder;
final MarkBuilder em = _b["em"] as MarkBuilder;
final MarkBuilder strong = _b["strong"] as MarkBuilder;
final MarkBuilder code = _b["code"] as MarkBuilder;
