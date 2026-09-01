import 'package:markdown/markdown.dart' as markdown;
import 'package:prosemirror/src/markdown/schema.dart';
import 'package:prosemirror/src/model/mark.dart' as prosemirror_model;
import 'package:prosemirror/src/model/node.dart' as prosemirror_model;
import 'package:prosemirror/src/model/schema.dart';

/// A function used to compute attributes for a parsed markdown token.
typedef ParseAttrs = Attrs? Function(MarkdownToken token, List<MarkdownToken> tokenStream, int index);

/// Object type used to specify how Markdown tokens should be parsed.
class ParseSpec {
  /// Creates a parsing spec for a markdown token.
  const ParseSpec({
    this.node,
    this.block,
    this.mark,
    this.attrs,
    this.getAttrs,
    this.noCloseToken = false,
    this.ignore = false,
  });

  /// This token maps to a single node.
  final String? node;

  /// This token wraps block content in a node.
  final String? block;

  /// This token adds a mark to its content.
  final String? mark;

  /// Attributes for the node or mark.
  final Object? attrs;

  /// A function used to compute attributes for the node or mark.
  final ParseAttrs? getAttrs;

  /// Indicates that the token has no open or close variant.
  final bool noCloseToken;

  /// When true, ignore the token wrapper and parse only its content.
  final bool ignore;
}

/// A markdown token with markdown-it-like fields used by [MarkdownParser].
class MarkdownToken {
  /// Creates a markdown token.
  const MarkdownToken(
    this.type, {
    this.content = "",
    this.children,
    this.attrs = const <String, String>{},
    this.tag = "",
    this.info = "",
  });

  /// The token type name.
  final String type;

  /// The token's raw text content.
  final String content;

  /// Child inline tokens.
  final List<MarkdownToken>? children;

  /// Token attributes.
  final Map<String, String> attrs;

  /// The source markdown/html tag name, when available.
  final String tag;

  /// Code fence info string.
  final String info;

  /// Returns the token attribute named [name], or `null`.
  String? attrGet(String name) => attrs[name];
}

/// A tokenizer that produces markdown-it-like token objects.
class MarkdownTokenizer {
  /// Creates a CommonMark tokenizer.
  MarkdownTokenizer.commonMark({bool html = false})
    : _document = markdown.Document(extensionSet: markdown.ExtensionSet.commonMark, encodeHtml: html);

  final markdown.Document _document;

  /// Tokenizes [text] as Markdown.
  List<MarkdownToken> parse(String text, [Object? markdownEnv]) {
    final tokens = <MarkdownToken>[];
    for (final node in _document.parse(text)) {
      _pushNodeTokens(tokens, node, parentTag: null);
    }
    return tokens;
  }
}

/// A configuration of a Markdown parser.
class MarkdownParser {
  /// Creates a parser with the given configuration.
  MarkdownParser(this.schema, this.tokenizer, this.tokens) : _tokenHandlersByType = _tokenHandlers(schema, tokens);

  /// The parser's document schema.
  final Schema schema;

  /// This parser's markdown tokenizer.
  final MarkdownTokenizer tokenizer;

  /// The token parse specs used to construct this parser.
  final Map<String, ParseSpec> tokens;

  final Map<String, _TokenHandler> _tokenHandlersByType;

  /// Parse a string as CommonMark markup.
  prosemirror_model.Node parse(String text, [Object? markdownEnv]) {
    final state = _MarkdownParseState(schema, _tokenHandlersByType);
    state.parseTokens(tokenizer.parse(text, markdownEnv));
    prosemirror_model.Node? document;
    do {
      document = state.closeNode();
    } while (state.stack.isNotEmpty);
    return document ?? schema.topNodeType.createAndFill()!;
  }
}

/// A parser parsing unextended CommonMark, without inline HTML.
final MarkdownParser defaultMarkdownParser = MarkdownParser(
  markdownSchema,
  MarkdownTokenizer.commonMark(html: false),
  defaultMarkdownParseSpecs,
);

/// Parse specs used by [defaultMarkdownParser].
final Map<String, ParseSpec> defaultMarkdownParseSpecs = {
  "blockquote": const ParseSpec(block: "blockquote"),
  "paragraph": const ParseSpec(block: "paragraph"),
  "list_item": const ParseSpec(block: "list_item"),
  "bullet_list": ParseSpec(block: "bullet_list", getAttrs: _bulletListAttrs),
  "ordered_list": ParseSpec(block: "ordered_list", getAttrs: _orderedListAttrs),
  "heading": ParseSpec(block: "heading", getAttrs: _headingAttrs),
  "code_block": const ParseSpec(block: "code_block", noCloseToken: true),
  "fence": ParseSpec(block: "code_block", getAttrs: _fenceAttrs, noCloseToken: true),
  "hr": const ParseSpec(node: "horizontal_rule"),
  "image": ParseSpec(node: "image", getAttrs: _imageAttrs),
  "hardbreak": const ParseSpec(node: "hard_break"),
  "em": const ParseSpec(mark: "em"),
  "strong": const ParseSpec(mark: "strong"),
  "link": ParseSpec(mark: "link", getAttrs: _linkAttrs),
  "code_inline": const ParseSpec(mark: "code", noCloseToken: true),
};

Attrs? _bulletListAttrs(MarkdownToken token, List<MarkdownToken> tokenStream, int index) {
  return {"tight": token.attrs["tight"] == "true"};
}

Attrs? _orderedListAttrs(MarkdownToken token, List<MarkdownToken> tokenStream, int index) {
  return {"order": int.tryParse(token.attrs["start"] ?? "") ?? 1, "tight": token.attrs["tight"] == "true"};
}

Attrs? _headingAttrs(MarkdownToken token, List<MarkdownToken> tokenStream, int index) {
  return {"level": int.tryParse(token.tag.substring(1)) ?? 1};
}

Attrs? _fenceAttrs(MarkdownToken token, List<MarkdownToken> tokenStream, int index) {
  return {"params": token.info};
}

Attrs? _imageAttrs(MarkdownToken token, List<MarkdownToken> tokenStream, int index) {
  return {
    "src": token.attrGet("src"),
    "title": _decodeAttribute(token.attrGet("title")),
    "alt": _decodeAttribute(token.attrGet("alt")),
  };
}

Attrs? _linkAttrs(MarkdownToken token, List<MarkdownToken> tokenStream, int index) {
  return {"href": token.attrGet("href"), "title": _decodeAttribute(token.attrGet("title"))};
}

String? _decodeAttribute(String? value) {
  if (value == null) {
    return null;
  }
  return value
      .replaceAll("&quot;", '"')
      .replaceAll("&#34;", '"')
      .replaceAll("&#x22;", '"')
      .replaceAll("&apos;", "'")
      .replaceAll("&#39;", "'")
      .replaceAll("&#x27;", "'")
      .replaceAll("&lt;", "<")
      .replaceAll("&gt;", ">")
      .replaceAll("&amp;", "&");
}

void _pushNodeTokens(List<MarkdownToken> tokens, markdown.Node node, {required String? parentTag}) {
  if (node is markdown.Text) {
    _pushTextTokens(tokens, node.text);
    return;
  }

  final element = node as markdown.Element;
  final tag = element.tag;
  if (_isHeadingTag(tag)) {
    _pushWrappingElementTokens(tokens, "heading", element, tag);
  } else if (tag == "p") {
    _pushWrappingElementTokens(tokens, "paragraph", element, tag);
  } else if (tag == "blockquote") {
    _pushWrappingElementTokens(tokens, "blockquote", element, tag);
  } else if (tag == "ul") {
    _pushListTokens(tokens, element, ordered: false);
  } else if (tag == "ol") {
    _pushListTokens(tokens, element, ordered: true);
  } else if (tag == "li") {
    _pushListItemTokens(tokens, element);
  } else if (tag == "pre") {
    _pushCodeBlockToken(tokens, element);
  } else if (tag == "hr") {
    tokens.add(const MarkdownToken("hr", tag: "hr"));
  } else if (tag == "img") {
    tokens.add(MarkdownToken("image", tag: tag, attrs: element.attributes));
  } else if (tag == "br") {
    tokens.add(const MarkdownToken("hardbreak", tag: "br"));
  } else if (tag == "em") {
    _pushWrappingElementTokens(tokens, "em", element, tag);
  } else if (tag == "strong") {
    _pushWrappingElementTokens(tokens, "strong", element, tag);
  } else if (tag == "a") {
    _pushWrappingElementTokens(tokens, "link", element, tag);
  } else if (tag == "code" && parentTag != "pre") {
    tokens.add(MarkdownToken("code_inline", tag: "code", content: element.textContent));
  } else {
    for (final child in element.children ?? const <markdown.Node>[]) {
      _pushNodeTokens(tokens, child, parentTag: tag);
    }
  }
}

void _pushWrappingElementTokens(List<MarkdownToken> tokens, String type, markdown.Element element, String tag) {
  tokens.add(MarkdownToken("${type}_open", tag: tag, attrs: element.attributes));
  for (final child in element.children ?? const <markdown.Node>[]) {
    _pushNodeTokens(tokens, child, parentTag: tag);
  }
  tokens.add(MarkdownToken("${type}_close", tag: tag, attrs: element.attributes));
}

void _pushListTokens(List<MarkdownToken> tokens, markdown.Element element, {required bool ordered}) {
  final type = ordered ? "ordered_list" : "bullet_list";
  final attrs = <String, String>{...element.attributes, "tight": _listIsTight(element) ? "true" : "false"};
  tokens.add(MarkdownToken("${type}_open", tag: element.tag, attrs: attrs));
  for (final child in element.children ?? const <markdown.Node>[]) {
    _pushNodeTokens(tokens, child, parentTag: element.tag);
  }
  tokens.add(MarkdownToken("${type}_close", tag: element.tag, attrs: attrs));
}

void _pushListItemTokens(List<MarkdownToken> tokens, markdown.Element element) {
  tokens.add(MarkdownToken("list_item_open", tag: element.tag));
  final children = element.children ?? const <markdown.Node>[];
  var index = 0;
  while (index < children.length) {
    final child = children[index];
    if (_isInlineMarkdownNode(child)) {
      tokens.add(const MarkdownToken("paragraph_open", tag: "p"));
      while (index < children.length && _isInlineMarkdownNode(children[index])) {
        _pushNodeTokens(tokens, children[index], parentTag: element.tag);
        index += 1;
      }
      tokens.add(const MarkdownToken("paragraph_close", tag: "p"));
    } else {
      _pushNodeTokens(tokens, child, parentTag: element.tag);
      index += 1;
    }
  }
  tokens.add(MarkdownToken("list_item_close", tag: element.tag));
}

void _pushCodeBlockToken(List<MarkdownToken> tokens, markdown.Element element) {
  final code = _firstElementChild(element, "code");
  final info = _codeInfo(code);
  tokens.add(
    MarkdownToken(
      "fence",
      tag: "code",
      content: code?.textContent ?? element.textContent,
      attrs: code?.attributes ?? const <String, String>{},
      info: info,
    ),
  );
}

markdown.Element? _firstElementChild(markdown.Element element, String tag) {
  for (final child in element.children ?? const <markdown.Node>[]) {
    if (child is markdown.Element && child.tag == tag) {
      return child;
    }
  }
  return null;
}

String _codeInfo(markdown.Element? code) {
  final className = code?.attributes["class"];
  if (className == null || !className.startsWith("language-")) {
    return "";
  }
  return className.substring("language-".length);
}

void _pushTextTokens(List<MarkdownToken> tokens, String text) {
  final parts = text.split("\n");
  for (var index = 0; index < parts.length; index++) {
    if (index > 0) {
      tokens.add(const MarkdownToken("softbreak"));
    }
    if (parts[index].isNotEmpty) {
      tokens.add(MarkdownToken("text", content: parts[index]));
    }
  }
}

bool _listIsTight(markdown.Element element) {
  for (final item in element.children ?? const <markdown.Node>[]) {
    if (item is! markdown.Element || item.tag != "li") {
      continue;
    }
    final children = item.children ?? const <markdown.Node>[];
    if (children.isEmpty) {
      continue;
    }
    return _isInlineMarkdownNode(children.first);
  }
  return false;
}

bool _isInlineMarkdownNode(markdown.Node node) {
  if (node is markdown.Text) {
    return true;
  }
  if (node is! markdown.Element) {
    return false;
  }
  return const {"em", "strong", "a", "code", "img", "br"}.contains(node.tag);
}

bool _isHeadingTag(String tag) {
  return tag.length == 2 && tag.startsWith("h") && "123456".contains(tag[1]);
}

Map<String, _TokenHandler> _tokenHandlers(Schema schema, Map<String, ParseSpec> tokens) {
  final handlers = <String, _TokenHandler>{};
  for (final entry in tokens.entries) {
    final type = entry.key;
    final spec = entry.value;
    if (spec.block != null) {
      final nodeType = schema.nodeType(spec.block!);
      if (_noCloseToken(spec, type)) {
        handlers[type] = _NoCloseBlockHandler(nodeType, spec);
      } else {
        handlers["${type}_open"] = _OpenBlockHandler(nodeType, spec);
        handlers["${type}_close"] = const _CloseBlockHandler();
      }
    } else if (spec.node != null) {
      final nodeType = schema.nodeType(spec.node!);
      handlers[type] = _NodeHandler(nodeType, spec);
    } else if (spec.mark != null) {
      final markType = schema.marks[spec.mark]!;
      if (_noCloseToken(spec, type)) {
        handlers[type] = _NoCloseMarkHandler(markType, spec);
      } else {
        handlers["${type}_open"] = _OpenMarkHandler(markType, spec);
        handlers["${type}_close"] = _CloseMarkHandler(markType);
      }
    } else if (spec.ignore) {
      if (_noCloseToken(spec, type)) {
        handlers[type] = const _NoOpHandler();
      } else {
        handlers["${type}_open"] = const _NoOpHandler();
        handlers["${type}_close"] = const _NoOpHandler();
      }
    } else {
      throw RangeError("Unrecognized parsing spec $spec");
    }
  }

  handlers["text"] = const _TextHandler();
  handlers["inline"] = const _InlineHandler();
  handlers["softbreak"] ??= const _SoftbreakHandler();

  return handlers;
}

bool _noCloseToken(ParseSpec spec, String type) {
  return spec.noCloseToken || type == "code_inline" || type == "code_block" || type == "fence";
}

Attrs? _attrs(ParseSpec spec, MarkdownToken token, List<MarkdownToken> tokens, int index) {
  final getAttrs = spec.getAttrs;
  if (getAttrs != null) {
    return getAttrs(token, tokens, index);
  }
  final specAttrs = spec.attrs;
  if (specAttrs is ParseAttrs) {
    return specAttrs(token, tokens, index);
  }
  return specAttrs as Attrs?;
}

String _withoutTrailingNewline(String value) {
  return value.endsWith("\n") ? value.substring(0, value.length - 1) : value;
}

prosemirror_model.Node? _maybeMerge(prosemirror_model.Node first, prosemirror_model.Node second) {
  if (first is prosemirror_model.TextNode &&
      second is prosemirror_model.TextNode &&
      prosemirror_model.Mark.sameSet(first.marks, second.marks)) {
    return first.withText(first.text + second.text);
  }
  return null;
}

class _MarkdownParseState {
  _MarkdownParseState(this.schema, this.tokenHandlers) {
    stack = [
      _OpenNode(
        type: schema.topNodeType,
        attrs: null,
        content: <prosemirror_model.Node>[],
        marks: prosemirror_model.Mark.none,
      ),
    ];
  }

  final Schema schema;
  final Map<String, _TokenHandler> tokenHandlers;
  late final List<_OpenNode> stack;

  _OpenNode get top => stack[stack.length - 1];

  void push(prosemirror_model.Node node) {
    if (stack.isNotEmpty) {
      top.content.add(node);
    }
  }

  void addText(String text) {
    if (text.isEmpty) {
      return;
    }
    final nodes = top.content;
    final node = schema.text(text, top.marks);
    final last = nodes.isNotEmpty ? nodes[nodes.length - 1] : null;
    final merged = last != null ? _maybeMerge(last, node) : null;
    if (merged != null) {
      nodes[nodes.length - 1] = merged;
    } else {
      nodes.add(node);
    }
  }

  void openMark(prosemirror_model.Mark mark) {
    top.marks = mark.addToSet(top.marks);
  }

  void closeMark(MarkType markType) {
    top.marks = markType.removeFromSet(top.marks);
  }

  void parseTokens(List<MarkdownToken> tokens) {
    for (var index = 0; index < tokens.length; index++) {
      final token = tokens[index];
      final handler = tokenHandlers[token.type];
      if (handler == null) {
        throw StateError("Token type `${token.type}` not supported by Markdown parser");
      }
      handler.handle(this, token, tokens, index);
    }
  }

  prosemirror_model.Node? addNode(NodeType type, Attrs? attrs, [List<prosemirror_model.Node>? content]) {
    final node = type.createAndFill(attrs, content, stack.isNotEmpty ? top.marks : []);
    if (node == null) {
      return null;
    }
    push(node);
    return node;
  }

  void openNode(NodeType type, Attrs? attrs) {
    stack.add(
      _OpenNode(type: type, attrs: attrs, content: <prosemirror_model.Node>[], marks: prosemirror_model.Mark.none),
    );
  }

  prosemirror_model.Node? closeNode() {
    final info = stack.removeLast();
    return addNode(info.type, info.attrs, info.content);
  }
}

class _OpenNode {
  _OpenNode({required this.type, required this.attrs, required this.content, required this.marks});

  final NodeType type;
  final Attrs? attrs;
  final List<prosemirror_model.Node> content;
  List<prosemirror_model.Mark> marks;
}

abstract interface class _TokenHandler {
  void handle(_MarkdownParseState state, MarkdownToken token, List<MarkdownToken> tokens, int index);
}

class _NoCloseBlockHandler implements _TokenHandler {
  const _NoCloseBlockHandler(this.nodeType, this.spec);

  final NodeType nodeType;
  final ParseSpec spec;

  @override
  void handle(_MarkdownParseState state, MarkdownToken token, List<MarkdownToken> tokens, int index) {
    state.openNode(nodeType, _attrs(spec, token, tokens, index));
    state.addText(_withoutTrailingNewline(token.content));
    state.closeNode();
  }
}

class _OpenBlockHandler implements _TokenHandler {
  const _OpenBlockHandler(this.nodeType, this.spec);

  final NodeType nodeType;
  final ParseSpec spec;

  @override
  void handle(_MarkdownParseState state, MarkdownToken token, List<MarkdownToken> tokens, int index) {
    state.openNode(nodeType, _attrs(spec, token, tokens, index));
  }
}

class _CloseBlockHandler implements _TokenHandler {
  const _CloseBlockHandler();

  @override
  void handle(_MarkdownParseState state, MarkdownToken token, List<MarkdownToken> tokens, int index) {
    state.closeNode();
  }
}

class _NodeHandler implements _TokenHandler {
  const _NodeHandler(this.nodeType, this.spec);

  final NodeType nodeType;
  final ParseSpec spec;

  @override
  void handle(_MarkdownParseState state, MarkdownToken token, List<MarkdownToken> tokens, int index) {
    state.addNode(nodeType, _attrs(spec, token, tokens, index));
  }
}

class _NoCloseMarkHandler implements _TokenHandler {
  const _NoCloseMarkHandler(this.markType, this.spec);

  final MarkType markType;
  final ParseSpec spec;

  @override
  void handle(_MarkdownParseState state, MarkdownToken token, List<MarkdownToken> tokens, int index) {
    state.openMark(markType.create(_attrs(spec, token, tokens, index)));
    state.addText(_withoutTrailingNewline(token.content));
    state.closeMark(markType);
  }
}

class _OpenMarkHandler implements _TokenHandler {
  const _OpenMarkHandler(this.markType, this.spec);

  final MarkType markType;
  final ParseSpec spec;

  @override
  void handle(_MarkdownParseState state, MarkdownToken token, List<MarkdownToken> tokens, int index) {
    state.openMark(markType.create(_attrs(spec, token, tokens, index)));
  }
}

class _CloseMarkHandler implements _TokenHandler {
  const _CloseMarkHandler(this.markType);

  final MarkType markType;

  @override
  void handle(_MarkdownParseState state, MarkdownToken token, List<MarkdownToken> tokens, int index) {
    state.closeMark(markType);
  }
}

class _NoOpHandler implements _TokenHandler {
  const _NoOpHandler();

  @override
  void handle(_MarkdownParseState state, MarkdownToken token, List<MarkdownToken> tokens, int index) {}
}

class _TextHandler implements _TokenHandler {
  const _TextHandler();

  @override
  void handle(_MarkdownParseState state, MarkdownToken token, List<MarkdownToken> tokens, int index) {
    state.addText(token.content);
  }
}

class _InlineHandler implements _TokenHandler {
  const _InlineHandler();

  @override
  void handle(_MarkdownParseState state, MarkdownToken token, List<MarkdownToken> tokens, int index) {
    state.parseTokens(token.children ?? const <MarkdownToken>[]);
  }
}

class _SoftbreakHandler implements _TokenHandler {
  const _SoftbreakHandler();

  @override
  void handle(_MarkdownParseState state, MarkdownToken token, List<MarkdownToken> tokens, int index) {
    state.addText(" ");
  }
}
