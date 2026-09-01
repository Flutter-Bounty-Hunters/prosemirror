import 'package:prosemirror/src/model/mark.dart';
import 'package:prosemirror/src/model/node.dart';

/// Serializes a ProseMirror node as markdown.
typedef NodeSerializer = void Function(MarkdownSerializerState state, Node node, Node parent, int index);

/// Computes a markdown string for an opening or closing mark.
typedef MarkString = String Function(MarkdownSerializerState state, Mark mark, Node parent, int index);

/// Computes the first-line delimiter for a list item.
typedef ListDelimiter = String Function(int index);

/// A specification for serializing a ProseMirror mark as Markdown.
class MarkSerializerSpec {
  /// Creates a markdown mark serializer spec.
  const MarkSerializerSpec({
    required this.open,
    required this.close,
    this.mixable = false,
    this.expelEnclosingWhitespace = false,
    this.escape = true,
  });

  /// The string or [MarkString] that opens this mark.
  final Object open;

  /// The string or [MarkString] that closes this mark.
  final Object close;

  /// Whether this mark can be reordered with other mixable marks.
  final bool mixable;

  /// Whether enclosing whitespace should be moved outside this mark.
  final bool expelEnclosingWhitespace;

  /// Whether content inside this mark should be escaped.
  final bool escape;
}

/// Options used by [MarkdownSerializer].
class MarkdownSerializerOptions {
  /// Creates markdown serializer options.
  const MarkdownSerializerOptions({
    this.escapeExtraCharacters,
    this.hardBreakNodeName = "hard_break",
    this.strict = true,
    this.tightLists = false,
  });

  /// Extra characters to escape.
  final RegExp? escapeExtraCharacters;

  /// The node name used for hard breaks.
  final String hardBreakNodeName;

  /// Whether unknown nodes and marks should throw.
  final bool strict;

  /// Whether lists should serialize tightly by default.
  final bool tightLists;

  /// Returns a copy with fields from [other] replacing this instance.
  MarkdownSerializerOptions merge(MarkdownSerializerOptions? other) {
    if (other == null) {
      return this;
    }
    return MarkdownSerializerOptions(
      escapeExtraCharacters: other.escapeExtraCharacters ?? escapeExtraCharacters,
      hardBreakNodeName: other.hardBreakNodeName,
      strict: other.strict,
      tightLists: other.tightLists,
    );
  }
}

/// A specification for serializing a ProseMirror document as Markdown text.
class MarkdownSerializer {
  /// Constructs a serializer with the given node and mark serializers.
  const MarkdownSerializer(this.nodes, this.marks, [this.options = _noOptions]);

  /// The node serializer functions for this serializer.
  final Map<String, NodeSerializer> nodes;

  /// The mark serializer info.
  final Map<String, MarkSerializerSpec> marks;

  /// The default options for this serializer.
  final MarkdownSerializerOptions options;

  /// Serialize the given node as CommonMark markdown.
  String serialize(Node content, [MarkdownSerializerOptions? options]) {
    final state = MarkdownSerializerState(nodes, marks, this.options.merge(options));
    state.renderContent(content);
    return state.out;
  }
}

/// A serializer for the markdown schema.
const MarkdownSerializer defaultMarkdownSerializer = MarkdownSerializer(
  {
    "blockquote": _serializeBlockquote,
    "code_block": _serializeCodeBlock,
    "heading": _serializeHeading,
    "horizontal_rule": _serializeHorizontalRule,
    "bullet_list": _serializeBulletList,
    "ordered_list": _serializeOrderedList,
    "list_item": _serializeListItem,
    "paragraph": _serializeParagraph,
    "image": _serializeImage,
    "hard_break": _serializeHardBreak,
    "text": _serializeText,
  },
  {
    "em": MarkSerializerSpec(open: "*", close: "*", mixable: true, expelEnclosingWhitespace: true),
    "strong": MarkSerializerSpec(open: "**", close: "**", mixable: true, expelEnclosingWhitespace: true),
    "link": MarkSerializerSpec(open: _openLink, close: _closeLink, mixable: true),
    "code": MarkSerializerSpec(open: _openCode, close: _closeCode, escape: false),
  },
);

const MarkdownSerializerOptions _noOptions = MarkdownSerializerOptions();

const MarkSerializerSpec _blankMark = MarkSerializerSpec(open: "", close: "", mixable: true);

void _serializeBlockquote(MarkdownSerializerState state, Node node, Node parent, int index) {
  state.wrapBlock("> ", null, node, _RenderContent(state, node).call);
}

void _serializeCodeBlock(MarkdownSerializerState state, Node node, Node parent, int index) {
  final fence = _codeFenceFor(node.textContent);
  state.write("$fence${node.attrs["params"] ?? ""}\n");
  state.text(node.textContent, false);
  state.write("\n");
  state.write(fence);
  state.closeBlock(node);
}

void _serializeHeading(MarkdownSerializerState state, Node node, Node parent, int index) {
  state.write("${state.repeat("#", node.attrs["level"] as int)} ");
  state.renderInline(node, false);
  state.closeBlock(node);
}

void _serializeHorizontalRule(MarkdownSerializerState state, Node node, Node parent, int index) {
  state.write((node.attrs["markup"] as String?) ?? "---");
  state.closeBlock(node);
}

void _serializeBulletList(MarkdownSerializerState state, Node node, Node parent, int index) {
  state.renderList(node, "  ", _BulletListDelimiter(node).call);
}

void _serializeOrderedList(MarkdownSerializerState state, Node node, Node parent, int index) {
  final start = node.attrs["order"] as int? ?? 1;
  final maxWidth = (start + node.childCount - 1).toString().length;
  final space = state.repeat(" ", maxWidth + 2);
  state.renderList(node, space, _OrderedListDelimiter(start, maxWidth, state).call);
}

void _serializeListItem(MarkdownSerializerState state, Node node, Node parent, int index) {
  state.renderContent(node);
}

void _serializeParagraph(MarkdownSerializerState state, Node node, Node parent, int index) {
  state.renderInline(node);
  state.closeBlock(node);
}

void _serializeImage(MarkdownSerializerState state, Node node, Node parent, int index) {
  final alt = state.esc((node.attrs["alt"] as String?) ?? "");
  final src = _escapeImageUrl(node.attrs["src"] as String);
  final title = node.attrs["title"] as String?;
  final titleText = title != null ? ' "${_escapeTitle(title)}"' : "";
  state.write("![$alt]($src$titleText)");
}

void _serializeHardBreak(MarkdownSerializerState state, Node node, Node parent, int index) {
  for (var nextIndex = index + 1; nextIndex < parent.childCount; nextIndex++) {
    if (!identical(parent.child(nextIndex).type, node.type)) {
      state.write("\\\n");
      return;
    }
  }
}

void _serializeText(MarkdownSerializerState state, Node node, Node parent, int index) {
  state.text(node.text!, state.inAutolink != true);
}

String _openLink(MarkdownSerializerState state, Mark mark, Node parent, int index) {
  state.inAutolink = _isPlainUrl(mark, parent, index);
  return state.inAutolink == true ? "<" : "[";
}

String _closeLink(MarkdownSerializerState state, Mark mark, Node parent, int index) {
  final inAutolink = state.inAutolink == true;
  state.inAutolink = null;
  if (inAutolink) {
    return ">";
  }
  final href = _escapeLinkUrl(mark.attrs["href"] as String);
  final title = mark.attrs["title"] as String?;
  final titleText = title != null ? ' "${_escapeTitle(title)}"' : "";
  return "]($href$titleText)";
}

String _openCode(MarkdownSerializerState state, Mark mark, Node parent, int index) {
  return _backticksFor(parent.child(index), -1);
}

String _closeCode(MarkdownSerializerState state, Mark mark, Node parent, int index) {
  return _backticksFor(parent.child(index - 1), 1);
}

String _codeFenceFor(String text) {
  var longest = 0;
  for (final match in RegExp(r'`{3,}').allMatches(text)) {
    longest = longest > match.group(0)!.length ? longest : match.group(0)!.length;
  }
  return longest == 0 ? "```" : "`" * (longest + 1);
}

String _escapeImageUrl(String value) {
  return value.replaceAllMapped(RegExp(r'[\(\)]'), _escapeMatch);
}

String _escapeLinkUrl(String value) {
  return value.replaceAllMapped(RegExp(r'[\(\)"]'), _escapeMatch);
}

String _escapeTitle(String value) {
  return value.replaceAll('"', r'\"');
}

String _escapeMatch(Match match) {
  return "\\${match.group(0)!}";
}

String _backticksFor(Node node, int side) {
  var length = 0;
  if (node.isText) {
    for (final match in RegExp(r'`+').allMatches(node.text!)) {
      if (match.group(0)!.length > length) {
        length = match.group(0)!.length;
      }
    }
  }

  var result = length > 0 && side > 0 ? " `" : "`";
  for (var index = 0; index < length; index++) {
    result += "`";
  }
  if (length > 0 && side < 0) {
    result += " ";
  }
  return result;
}

bool _isPlainUrl(Mark link, Node parent, int index) {
  final href = link.attrs["href"];
  if (link.attrs["title"] != null || href is! String || !RegExp(r'^\w+:').hasMatch(href)) {
    return false;
  }
  final content = parent.child(index);
  if (!content.isText ||
      content.text != href ||
      content.marks.isEmpty ||
      !content.marks[content.marks.length - 1].eq(link)) {
    return false;
  }
  return index == parent.childCount - 1 || !link.isInSet(parent.child(index + 1).marks);
}

class _RenderContent {
  const _RenderContent(this.state, this.node);

  final MarkdownSerializerState state;
  final Node node;

  void call() {
    state.renderContent(node);
  }
}

class _BulletListDelimiter {
  const _BulletListDelimiter(this.node);

  final Node node;

  String call(int index) {
    return "${node.attrs["bullet"] ?? "*"} ";
  }
}

class _OrderedListDelimiter {
  const _OrderedListDelimiter(this.start, this.maxWidth, this.state);

  final int start;
  final int maxWidth;
  final MarkdownSerializerState state;

  String call(int index) {
    final number = (start + index).toString();
    return "${state.repeat(" ", maxWidth - number.length)}$number. ";
  }
}

/// Tracks state during markdown serialization.
class MarkdownSerializerState {
  /// Creates serializer state.
  MarkdownSerializerState(this.nodes, this.marks, this.options);

  /// The node serializer functions.
  final Map<String, NodeSerializer> nodes;

  /// The mark serializer info.
  final Map<String, MarkSerializerSpec> marks;

  /// The active serializer options.
  final MarkdownSerializerOptions options;

  /// The current line delimiter.
  String delim = "";

  /// The accumulated markdown output.
  String out = "";

  /// The block that was just closed but not yet flushed.
  Node? closed;

  /// Whether currently rendering an autolink.
  bool? inAutolink;

  /// Whether the output position is at the start of a block.
  bool atBlockStart = false;

  /// Whether currently rendering inside a tight list.
  bool inTightList = false;

  /// Flushes a pending closed block.
  void flushClose([int size = 2]) {
    if (closed == null) {
      return;
    }
    if (!atBlank()) {
      out += "\n";
    }
    if (size > 1) {
      var delimiterMin = delim;
      delimiterMin = delimiterMin.replaceFirst(RegExp(r'\s+$'), "");
      for (var index = 1; index < size; index++) {
        out += "$delimiterMin\n";
      }
    }
    closed = null;
  }

  /// Gets markdown serialization info for a mark type.
  MarkSerializerSpec getMark(String name) {
    final info = marks[name];
    if (info != null) {
      return info;
    }
    if (options.strict) {
      throw StateError("Mark type `$name` not supported by Markdown renderer");
    }
    return _blankMark;
  }

  /// Render a block, prefixing each line with [delim].
  void wrapBlock(String delim, String? firstDelim, Node node, void Function() render) {
    final old = this.delim;
    write(firstDelim ?? delim);
    this.delim += delim;
    render();
    this.delim = old;
    closeBlock(node);
  }

  /// Whether the current output ends at a blank position.
  bool atBlank() {
    return out.isEmpty || out.endsWith("\n");
  }

  /// Ensure the current content ends with a newline.
  void ensureNewLine() {
    if (!atBlank()) {
      out += "\n";
    }
  }

  /// Prepare the state for writing output and optionally write [content].
  void write([String? content]) {
    flushClose();
    if (delim.isNotEmpty && atBlank()) {
      out += delim;
    }
    if (content != null && content.isNotEmpty) {
      out += content;
    }
  }

  /// Close the given block.
  void closeBlock(Node node) {
    closed = node;
  }

  /// Add text to the document.
  void text(String text, [bool escape = true]) {
    final lines = text.split("\n");
    for (var index = 0; index < lines.length; index++) {
      write();
      if (!escape && lines[index].startsWith("[") && RegExp(r'(^|[^\\])!$').hasMatch(out)) {
        out = "${out.substring(0, out.length - 1)}\\!";
      }
      out += escape ? esc(lines[index], atBlockStart) : lines[index];
      if (index != lines.length - 1) {
        out += "\n";
      }
    }
  }

  /// Render [node] as a block or inline node.
  void render(Node node, Node parent, int index) {
    final serializer = nodes[node.type.name];
    if (serializer != null) {
      serializer(this, node, parent, index);
      return;
    }
    if (options.strict) {
      throw StateError("Token type `${node.type.name}` not supported by Markdown renderer");
    }
    if (!node.type.isLeaf) {
      if (node.type.inlineContent) {
        renderInline(node);
      } else {
        renderContent(node);
      }
      if (node.isBlock) {
        closeBlock(node);
      }
    }
  }

  /// Render block children of [parent].
  void renderContent(Node parent) {
    parent.forEach((node, offset, index) {
      render(node, parent, index);
    });
  }

  /// Render inline children of [parent].
  void renderInline(Node parent, [bool fromBlockStart = true]) {
    atBlockStart = fromBlockStart;
    final active = <Mark>[];
    var trailing = "";
    parent.forEach((node, offset, index) {
      trailing = _renderInlineNode(parent, node, index, active, trailing);
    });
    _renderInlineNode(parent, null, parent.childCount, active, trailing);
    atBlockStart = false;
  }

  String _renderInlineNode(Node parent, Node? node, int index, List<Mark> active, String trailing) {
    var marks = node != null ? List<Mark>.of(node.marks) : <Mark>[];
    marks = _withoutExpiredHardBreakMarks(parent, node, index, marks);

    final inner = marks.isNotEmpty ? marks[marks.length - 1] : null;
    final noEscape = inner != null && !getMark(inner.type.name).escape;
    final length = marks.length - (noEscape ? 1 : 0);
    marks = _reorderMixableMarks(marks, active, length);

    var keep = 0;
    while (keep < active.length && keep < length && marks[keep].eq(active[keep])) {
      keep += 1;
    }

    var leading = trailing;
    var nextTrailing = "";
    final expelled = _expelEnclosingWhitespace(parent, node, index, marks, active, keep);
    node = expelled.node;
    marks = expelled.marks;
    leading += expelled.leading;
    nextTrailing = expelled.trailing;

    if (node != null || index == parent.childCount) {
      while (keep < active.length) {
        text(markString(active.removeLast(), false, parent, index), false);
      }
    }

    if (leading.isNotEmpty) {
      text(leading);
    }

    if (node != null) {
      while (active.length < length) {
        final mark = marks[active.length];
        active.add(mark);
        text(markString(mark, true, parent, index), false);
        atBlockStart = false;
      }

      if (noEscape && node.isText) {
        text(markString(inner, true, parent, index) + node.text! + markString(inner, false, parent, index + 1), false);
      } else {
        render(node, parent, index);
      }
      atBlockStart = false;

      if (node.isText && node.nodeSize > 0) {
        atBlockStart = false;
      }
    }

    return nextTrailing;
  }

  List<Mark> _withoutExpiredHardBreakMarks(Node parent, Node? node, int index, List<Mark> marks) {
    if (node == null || node.type.name != options.hardBreakNodeName) {
      return marks;
    }
    final kept = <Mark>[];
    for (final mark in marks) {
      if (index + 1 == parent.childCount) {
        continue;
      }
      final next = parent.child(index + 1);
      if (mark.isInSet(next.marks) && (!next.isText || RegExp(r'\S').hasMatch(next.text!))) {
        kept.add(mark);
      }
    }
    return kept;
  }

  List<Mark> _reorderMixableMarks(List<Mark> marks, List<Mark> active, int length) {
    var reordered = List<Mark>.of(marks);
    outer:
    for (var markIndex = 0; markIndex < length; markIndex++) {
      final mark = reordered[markIndex];
      if (!getMark(mark.type.name).mixable) {
        break;
      }
      for (var activeIndex = 0; activeIndex < active.length; activeIndex++) {
        final other = active[activeIndex];
        if (!getMark(other.type.name).mixable) {
          break;
        }
        if (mark.eq(other)) {
          if (markIndex > activeIndex) {
            reordered = [
              ...reordered.sublist(0, activeIndex),
              mark,
              ...reordered.sublist(activeIndex, markIndex),
              ...reordered.sublist(markIndex + 1, length),
            ];
          } else if (activeIndex > markIndex) {
            reordered = [
              ...reordered.sublist(0, markIndex),
              ...reordered.sublist(markIndex + 1, activeIndex),
              mark,
              ...reordered.sublist(activeIndex, length),
            ];
          }
          continue outer;
        }
      }
    }
    return reordered;
  }

  _ExpelledWhitespace _expelEnclosingWhitespace(
    Node parent,
    Node? node,
    int index,
    List<Mark> marks,
    List<Mark> active,
    int keep,
  ) {
    var leading = "";
    var trailing = "";
    if (node != null && node.isText && _shouldExpelLeadingWhitespace(marks, active, keep)) {
      final split = _splitLeadingWhitespace(node.text!);
      if (split.whitespace.isNotEmpty) {
        leading = split.whitespace;
        node = split.rest.isNotEmpty ? (node as TextNode).withText(split.rest) : null;
        if (node == null) {
          marks = active;
        }
      }
    }
    if (node != null && node.isText && _shouldExpelTrailingWhitespace(parent, node, index, marks)) {
      final split = _splitTrailingWhitespace(node.text!);
      if (split.whitespace.isNotEmpty) {
        trailing = split.whitespace;
        node = split.rest.isNotEmpty ? (node as TextNode).withText(split.rest) : null;
        if (node == null) {
          marks = active;
        }
      }
    }
    return _ExpelledWhitespace(node: node, marks: marks, leading: leading, trailing: trailing);
  }

  bool _shouldExpelLeadingWhitespace(List<Mark> marks, List<Mark> active, int keep) {
    for (final mark in marks) {
      final info = getMark(mark.type.name);
      if (info.expelEnclosingWhitespace && !_hasActivePrefixMark(mark, active, keep)) {
        return true;
      }
    }
    return false;
  }

  bool _hasActivePrefixMark(Mark mark, List<Mark> active, int keep) {
    for (var index = 0; index < keep; index++) {
      if (index < active.length && active[index].eq(mark)) {
        return true;
      }
    }
    return false;
  }

  bool _shouldExpelTrailingWhitespace(Node parent, Node node, int index, List<Mark> marks) {
    for (var markIndex = 0; markIndex < marks.length; markIndex++) {
      final mark = marks[markIndex];
      final info = getMark(mark.type.name);
      if (info.expelEnclosingWhitespace && !isMarkAhead(parent, index + 1, marks.sublist(0, markIndex + 1))) {
        return true;
      }
    }
    return false;
  }

  /// Render a node's content as a list.
  void renderList(Node node, String delim, ListDelimiter firstDelim) {
    if (closed != null && identical(closed!.type, node.type)) {
      flushClose(3);
    } else if (inTightList) {
      flushClose(1);
    }

    final isTight = node.attrs.containsKey("tight") ? node.attrs["tight"] == true : options.tightLists;
    final previousTight = inTightList;
    inTightList = isTight;
    node.forEach((child, offset, index) {
      if (index > 0 && isTight) {
        flushClose(1);
      }
      wrapBlock(delim, firstDelim(index), node, _RenderNode(this, child, node, index).call);
    });
    inTightList = previousTight;
  }

  /// Escape the given string so that it can safely appear in Markdown content.
  String esc(String value, [bool startOfLine = false]) {
    var result = value.replaceAllMapped(RegExp(r'[`*\\~\[\]_]'), (match) {
      final matched = match.group(0)!;
      final index = match.start;
      if (matched == "_" &&
          index > 0 &&
          index + 1 < value.length &&
          _isWord(value.codeUnitAt(index - 1)) &&
          _isWord(value.codeUnitAt(index + 1))) {
        return matched;
      }
      return "\\$matched";
    });
    if (startOfLine) {
      result = result
          .replaceFirstMapped(RegExp(r'^(\+[ ]|[\-*>])'), _escapeWholeMatch)
          .replaceFirstMapped(RegExp(r'^(\s*)(#{1,6})(\s|$)'), _escapeHeadingStart)
          .replaceFirstMapped(RegExp(r'^(\s*\d+)\.\s'), _escapeOrderedMarker);
    }
    final extra = options.escapeExtraCharacters;
    if (extra != null) {
      result = result.replaceAllMapped(extra, _escapeMatch);
    }
    return result;
  }

  /// Quote [value] using a suitable pair of delimiters.
  String quote(String value) {
    final wrap = !value.contains('"')
        ? '""'
        : !value.contains("'")
        ? "''"
        : "()";
    return "${wrap[0]}$value${wrap[1]}";
  }

  /// Repeat [value] [count] times.
  String repeat(String value, int count) {
    final buffer = StringBuffer();
    for (var index = 0; index < count; index++) {
      buffer.write(value);
    }
    return buffer.toString();
  }

  /// Get the markdown string for a given opening or closing mark.
  String markString(Mark mark, bool open, Node parent, int index) {
    final info = getMark(mark.type.name);
    final value = open ? info.open : info.close;
    if (value is String) {
      return value;
    }
    return (value as MarkString)(this, mark, parent, index);
  }

  /// Get leading and trailing whitespace from [text].
  ({String? leading, String? trailing}) getEnclosingWhitespace(String text) {
    return (
      leading: _splitLeadingWhitespace(text).whitespace.nullIfEmpty,
      trailing: _splitTrailingWhitespace(text).whitespace.nullIfEmpty,
    );
  }

  /// Returns true if [marks] are active after [index].
  bool isMarkAhead(Node parent, int index, List<Mark> marks) {
    var nextIndex = index;
    for (;;) {
      if (nextIndex >= parent.childCount) {
        return false;
      }
      final next = parent.child(nextIndex);
      if (next.type.name != options.hardBreakNodeName) {
        return next.marks.length >= marks.length && Mark.sameSet(next.marks.sublist(0, marks.length), marks);
      }
      nextIndex += 2;
    }
  }
}

class _RenderNode {
  const _RenderNode(this.state, this.node, this.parent, this.index);

  final MarkdownSerializerState state;
  final Node node;
  final Node parent;
  final int index;

  void call() {
    state.render(node, parent, index);
  }
}

class _ExpelledWhitespace {
  const _ExpelledWhitespace({required this.node, required this.marks, required this.leading, required this.trailing});

  final Node? node;
  final List<Mark> marks;
  final String leading;
  final String trailing;
}

({String whitespace, String rest}) _splitLeadingWhitespace(String value) {
  var index = 0;
  while (index < value.length && _isWhitespace(value.codeUnitAt(index))) {
    index += 1;
  }
  return (whitespace: value.substring(0, index), rest: value.substring(index));
}

({String rest, String whitespace}) _splitTrailingWhitespace(String value) {
  var index = value.length;
  while (index > 0 && _isWhitespace(value.codeUnitAt(index - 1))) {
    index -= 1;
  }
  return (rest: value.substring(0, index), whitespace: value.substring(index));
}

String _escapeWholeMatch(Match match) {
  return "\\${match.group(0)!}";
}

String _escapeHeadingStart(Match match) {
  return "${match.group(1)!}\\${match.group(2)!}${match.group(3)!}";
}

String _escapeOrderedMarker(Match match) {
  return "${match.group(1)!}\\. ";
}

bool _isWord(int codeUnit) {
  return (codeUnit >= 0x30 && codeUnit <= 0x39) ||
      (codeUnit >= 0x41 && codeUnit <= 0x5A) ||
      (codeUnit >= 0x61 && codeUnit <= 0x7A) ||
      codeUnit == 0x5F;
}

bool _isWhitespace(int codeUnit) {
  return codeUnit == 0x20 ||
      codeUnit == 0x09 ||
      codeUnit == 0x0A ||
      codeUnit == 0x0D ||
      codeUnit == 0x0B ||
      codeUnit == 0x0C;
}

extension _StringNullIfEmpty on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}
