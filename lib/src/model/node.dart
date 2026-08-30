import 'package:prosemirror/src/model/compare_deep.dart';
import 'package:prosemirror/src/model/content.dart';
import 'package:prosemirror/src/model/fragment.dart';
import 'package:prosemirror/src/model/mark.dart';
import 'package:prosemirror/src/model/replace.dart';
import 'package:prosemirror/src/model/resolved_pos.dart';
import 'package:prosemirror/src/model/schema.dart';

const Attrs _emptyAttrs = <String, Object?>{};

/// This class represents a node in the tree that makes up a ProseMirror
/// document. A document is an instance of [Node], with children that are also
/// instances of [Node].
///
/// Nodes are persistent data structures. Instead of changing them, you create
/// new ones with the content you want.
class Node {
  /// @internal
  Node(this.type, this.attrs, [Fragment? content, this.marks = Mark.none])
    : content = content ?? Fragment.empty;

  /// The type of node that this is.
  final NodeType type;

  /// An object mapping attribute names to values.
  final Attrs attrs;

  /// A container holding the node's children.
  final Fragment content;

  /// The marks applied to this node.
  final List<Mark> marks;

  /// The list of this node's child nodes.
  List<Node> get children => content.content;

  /// For text nodes, this contains the node's text content.
  String? get text => null;

  /// The size of this node, as defined by the integer-based indexing scheme.
  int get nodeSize => isLeaf ? 1 : 2 + content.size;

  /// The number of children that the node has.
  int get childCount => content.childCount;

  /// Get the child node at the given index.
  Node child(int index) => content.child(index);

  /// Get the child node at the given index, if it exists.
  Node? maybeChild(int index) => content.maybeChild(index);

  /// Call [callback] for every child node.
  void forEach(void Function(Node node, int offset, int index) callback) =>
      content.forEach(callback);

  /// Invoke a callback for all descendant nodes recursively overlapping the
  /// given two positions that are relative to start of this node's content.
  void nodesBetween(
    int from,
    int to,
    NodesBetweenCallback callback, [
    int startPos = 0,
  ]) {
    content.nodesBetween(from, to, callback, startPos, this);
  }

  /// Call the given callback for every descendant node.
  void descendants(NodesBetweenCallback callback) {
    nodesBetween(0, content.size, callback);
  }

  /// Concatenates all the text nodes found in this fragment and its children.
  String get textContent {
    return (isLeaf && type.spec.leafText != null)
        ? type.spec.leafText!(this)
        : textBetween(0, content.size, "");
  }

  /// Get all text between positions [from] and [to].
  String textBetween(
    int from,
    int to, [
    String? blockSeparator,
    Object? leafText,
  ]) {
    return content.textBetween(from, to, blockSeparator, leafText);
  }

  /// Returns this node's first child, or `null` if there are no children.
  Node? get firstChild => content.firstChild;

  /// Returns this node's last child, or `null` if there are no children.
  Node? get lastChild => content.lastChild;

  /// Test whether two nodes represent the same piece of document.
  bool eq(Node other) {
    return identical(this, other) ||
        (sameMarkup(other) && content.eq(other.content));
  }

  /// Compare the markup (type, attributes, and marks) of this node to those of
  /// another.
  bool sameMarkup(Node other) {
    return hasMarkup(other.type, other.attrs, other.marks);
  }

  /// Check whether this node's markup correspond to the given type, attributes,
  /// and marks.
  bool hasMarkup(NodeType type, [Attrs? attrs, List<Mark>? marks]) {
    return identical(this.type, type) &&
        compareDeep(this.attrs, attrs ?? type.defaultAttrs ?? _emptyAttrs) &&
        Mark.sameSet(this.marks, marks ?? Mark.none);
  }

  /// Create a new node with the same markup as this node, containing the given
  /// content (or empty, if no content is given).
  Node copy([Object? content]) {
    final fragment = content as Fragment?;
    if (identical(fragment, this.content)) {
      return this;
    }
    return Node(type, attrs, fragment, marks);
  }

  /// Create a copy of this node, with the given set of marks instead of the
  /// node's own marks.
  Node mark(List<Mark> marks) {
    return identical(marks, this.marks)
        ? this
        : Node(type, attrs, content, marks);
  }

  /// Create a copy of this node with only the content between the given
  /// positions.
  Node cut(int from, [int? to]) {
    to ??= content.size;
    if (from == 0 && to == content.size) {
      return this;
    }
    return copy(content.cut(from, to));
  }

  /// Cut out the part of the document between the given positions, and return
  /// it as a [Slice] object.
  Slice slice(int from, [int? to, bool includeParents = false]) {
    final toPos = to ?? content.size;
    if (from == toPos) {
      return Slice.empty;
    }

    final resolvedFrom = resolve(from);
    final resolvedTo = resolve(toPos);
    final depth = includeParents ? 0 : resolvedFrom.sharedDepth(toPos);
    final start = resolvedFrom.start(depth);
    final node = resolvedFrom.node(depth);
    final sliceContent = node.content.cut(
      resolvedFrom.pos - start,
      resolvedTo.pos - start,
    );
    return Slice(
      sliceContent,
      resolvedFrom.depth - depth,
      resolvedTo.depth - depth,
    );
  }

  /// Replace the part of the document between the given positions with the
  /// given slice.
  Node replace(int from, int to, Slice slice) {
    return replaceImpl(resolve(from), resolve(to), slice);
  }

  /// Find the node directly after the given position.
  Node? nodeAt(int pos) {
    Node? node = this;
    for (;;) {
      final found = node!.content.findIndex(pos);
      node = node.maybeChild(found.index);
      if (node == null) {
        return null;
      }
      if (found.offset == pos || node.isText) {
        return node;
      }
      pos -= found.offset + 1;
    }
  }

  /// Find the (direct) child node after the given offset, if any.
  ({Node? node, int index, int offset}) childAfter(int pos) {
    final found = content.findIndex(pos);
    return (
      node: content.maybeChild(found.index),
      index: found.index,
      offset: found.offset,
    );
  }

  /// Find the (direct) child node before the given offset, if any.
  ({Node? node, int index, int offset}) childBefore(int pos) {
    if (pos == 0) {
      return (node: null, index: 0, offset: 0);
    }
    final found = content.findIndex(pos);
    if (found.offset < pos) {
      return (
        node: content.child(found.index),
        index: found.index,
        offset: found.offset,
      );
    }
    final node = content.child(found.index - 1);
    return (
      node: node,
      index: found.index - 1,
      offset: found.offset - node.nodeSize,
    );
  }

  /// Resolve the given position in the document.
  ResolvedPos resolve(int pos) => ResolvedPos.resolveCached(this, pos);

  /// @internal
  ResolvedPos resolveNoCache(int pos) => ResolvedPos.resolve(this, pos);

  /// Test whether a given mark or mark type occurs in this document between the
  /// two given positions.
  bool rangeHasMark(int from, int to, Object type) {
    var found = false;
    if (to > from) {
      nodesBetween(from, to, (node, pos, parent, index) {
        if (_isInSet(type, node.marks)) {
          found = true;
        }
        return !found;
      });
    }
    return found;
  }

  /// True when this is a block (non-inline node).
  bool get isBlock => type.isBlock;

  /// True when this is a textblock node, a block node with inline content.
  bool get isTextblock => type.isTextblock;

  /// True when this node allows inline content.
  bool get inlineContent => type.inlineContent;

  /// True when this is an inline node.
  bool get isInline => type.isInline;

  /// True when this is a text node.
  bool get isText => type.isText;

  /// True when this is a leaf node.
  bool get isLeaf => type.isLeaf;

  /// True when this is an atom.
  bool get isAtom => type.isAtom;

  /// Return a string representation of this node for debugging purposes.
  @override
  String toString() {
    if (type.spec.toDebugString != null) {
      return type.spec.toDebugString!(this);
    }
    var name = type.name;
    if (content.size != 0) {
      name += "(${content.toStringInner()})";
    }
    return _wrapMarks(marks, name);
  }

  /// Get the content match in this node at the given index.
  ContentMatch contentMatchAt(int index) {
    final match = type.contentMatch.matchFragment(content, 0, index);
    if (match == null) {
      throw StateError("Called contentMatchAt on a node with invalid content");
    }
    return match;
  }

  /// Test whether replacing the range between [from] and [to] (by child index)
  /// with the given replacement fragment would leave the node's content valid.
  bool canReplace(
    int from,
    int to, [
    Fragment? replacement,
    int start = 0,
    int? end,
  ]) {
    replacement ??= Fragment.empty;
    end ??= replacement.childCount;
    final one = contentMatchAt(from).matchFragment(replacement, start, end);
    final two = one?.matchFragment(content, to);
    if (two == null || !two.validEnd) {
      return false;
    }
    for (var index = start; index < end; index++) {
      if (!type.allowsMarks(replacement.child(index).marks)) {
        return false;
      }
    }
    return true;
  }

  /// Test whether replacing the range [from] to [to] (by index) with a node of
  /// the given type would leave the node's content valid.
  bool canReplaceWith(int from, int to, NodeType type, [List<Mark>? marks]) {
    if (marks != null && !this.type.allowsMarks(marks)) {
      return false;
    }
    final start = contentMatchAt(from).matchType(type);
    final end = start?.matchFragment(content, to);
    return end != null ? end.validEnd : false;
  }

  /// Test whether the given node's content could be appended to this node.
  bool canAppend(Node other) {
    if (other.content.size != 0) {
      return canReplace(childCount, childCount, other.content);
    } else {
      return type.compatibleContent(other.type);
    }
  }

  /// Check whether this node and its descendants conform to the schema, and
  /// raise an exception when they do not.
  void check() {
    type.checkContent(content);
    type.checkAttrs(attrs);
    var copy = Mark.none;
    for (var index = 0; index < marks.length; index++) {
      final mark = marks[index];
      mark.type.checkAttrs(mark.attrs);
      copy = mark.addToSet(copy);
    }
    if (!Mark.sameSet(copy, marks)) {
      throw RangeError(
        "Invalid collection of marks for node ${type.name}: ${marks.map((mark) => mark.type.name).toList()}",
      );
    }
    content.forEach((node, offset, index) => node.check());
  }

  /// Return a JSON-serializeable representation of this node.
  Object? toJSON() {
    final result = <String, Object?>{"type": type.name};
    if (attrs.isNotEmpty) {
      result["attrs"] = attrs;
    }
    if (content.size != 0) {
      result["content"] = content.toJSON();
    }
    if (marks.isNotEmpty) {
      result["marks"] = marks.map((mark) => mark.toJSON()).toList();
    }
    return result;
  }

  /// Deserialize a node from its JSON representation.
  static Node fromJSON(Schema schema, Object? json) {
    if (json == null) {
      throw RangeError("Invalid input for Node.fromJSON");
    }
    final map = json as Map<String, Object?>;
    List<Mark>? marks;
    if (map["marks"] != null) {
      final rawMarks = map["marks"];
      if (rawMarks is! List) {
        throw RangeError("Invalid mark data for Node.fromJSON");
      }
      marks = rawMarks.map((mark) => schema.markFromJSON(mark)).toList();
    }
    if (map["type"] == "text") {
      final textValue = map["text"];
      if (textValue is! String) {
        throw RangeError("Invalid text node in JSON");
      }
      return schema.text(textValue, marks);
    }
    final content = Fragment.fromJSON(schema, map["content"]);
    final node = schema
        .nodeType(map["type"] as String)
        .create(map["attrs"] as Attrs?, content, marks);
    node.type.checkAttrs(node.attrs);
    return node;
  }
}

bool _isInSet(Object type, List<Mark> marks) {
  if (type is Mark) {
    return type.isInSet(marks);
  }
  return (type as MarkType).isInSet(marks) != null;
}

/// A text node in the document.
class TextNode extends Node {
  /// @internal
  TextNode(
    NodeType type,
    Attrs attrs,
    String content, [
    List<Mark> marks = Mark.none,
  ]) : _text = content,
       super(type, attrs, null, marks) {
    if (content.isEmpty) {
      throw RangeError("Empty text nodes are not allowed");
    }
  }

  final String _text;

  @override
  String get text => _text;

  @override
  String toString() {
    if (type.spec.toDebugString != null) {
      return type.spec.toDebugString!(this);
    }
    return _wrapMarks(marks, _jsonQuote(_text));
  }

  @override
  String get textContent => _text;

  @override
  String textBetween(
    int from,
    int to, [
    String? blockSeparator,
    Object? leafText,
  ]) {
    return _text.substring(from, to);
  }

  @override
  int get nodeSize => _text.length;

  @override
  Node mark(List<Mark> marks) {
    return identical(marks, this.marks)
        ? this
        : TextNode(type, attrs, _text, marks);
  }

  /// Return a copy of this text node with different text.
  TextNode withText(String text) {
    if (text == _text) {
      return this;
    }
    return TextNode(type, attrs, text, marks);
  }

  @override
  Node cut([int from = 0, int? to]) {
    to ??= _text.length;
    if (from == 0 && to == _text.length) {
      return this;
    }
    return withText(_text.substring(from, to));
  }

  @override
  bool eq(Node other) {
    return sameMarkup(other) && _text == other.text;
  }

  @override
  Object? toJSON() {
    final base = super.toJSON() as Map<String, Object?>;
    base["text"] = _text;
    return base;
  }
}

String _wrapMarks(List<Mark> marks, String wrapped) {
  for (var index = marks.length - 1; index >= 0; index--) {
    wrapped = "${marks[index].type.name}($wrapped)";
  }
  return wrapped;
}

String _jsonQuote(String text) {
  final buffer = StringBuffer('"');
  for (final code in text.codeUnits) {
    switch (code) {
      case 0x22:
        buffer.write(r'\"');
        break;
      case 0x5C:
        buffer.write(r'\\');
        break;
      case 0x08:
        buffer.write(r'\b');
        break;
      case 0x0C:
        buffer.write(r'\f');
        break;
      case 0x0A:
        buffer.write(r'\n');
        break;
      case 0x0D:
        buffer.write(r'\r');
        break;
      case 0x09:
        buffer.write(r'\t');
        break;
      default:
        if (code < 0x20) {
          buffer.write('\\u${code.toRadix16Padded()}');
        } else {
          buffer.writeCharCode(code);
        }
    }
  }
  buffer.write('"');
  return buffer.toString();
}

extension _Radix on int {
  String toRadix16Padded() => toRadixString(16).padLeft(4, '0');
}
