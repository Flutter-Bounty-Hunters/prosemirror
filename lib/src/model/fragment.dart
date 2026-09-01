import 'package:prosemirror/src/model/diff.dart' as diff;
import 'package:prosemirror/src/model/node.dart';
import 'package:prosemirror/src/model/schema.dart';

/// Callback signature used by [Fragment.nodesBetween] and [Node.nodesBetween].
///
/// Returning `false` prevents descending into the visited node's children.
typedef NodesBetweenCallback = bool? Function(Node node, int start, Node? parent, int index);

/// A fragment represents a node's collection of child nodes.
///
/// Like nodes, fragments are persistent data structures, and you should not
/// mutate them or their content. Rather, you create new instances whenever
/// needed.
class Fragment {
  /// @internal
  Fragment(this.content, [int? size]) : size = size ?? _sumSize(content);

  static int _sumSize(List<Node> content) {
    var total = 0;
    for (var index = 0; index < content.length; index++) {
      total += content[index].nodeSize;
    }
    return total;
  }

  /// The child nodes in this fragment.
  final List<Node> content;

  /// The size of the fragment, which is the total of the size of its content
  /// nodes.
  final int size;

  /// Invoke a callback for all descendant nodes between the given two positions
  /// (relative to start of this fragment). Doesn't descend into a node when the
  /// callback returns `false`.
  void nodesBetween(int from, int to, NodesBetweenCallback callback, [int nodeStart = 0, Node? parent]) {
    var pos = 0;
    for (var index = 0; pos < to; index++) {
      final child = content[index];
      final end = pos + child.nodeSize;
      if (end > from && callback(child, nodeStart + pos, parent, index) != false && child.content.size != 0) {
        final start = pos + 1;
        child.content.nodesBetween(
          (from - start) > 0 ? from - start : 0,
          (to - start) < child.content.size ? to - start : child.content.size,
          callback,
          nodeStart + start,
          child,
        );
      }
      pos = end;
    }
  }

  /// Call the given callback for every descendant node.
  void descendants(NodesBetweenCallback callback) {
    nodesBetween(0, size, callback);
  }

  /// Extract the text between [from] and [to].
  String textBetween(int from, int to, [String? blockSeparator, Object? leafText]) {
    final text = StringBuffer();
    var first = true;
    nodesBetween(from, to, (node, pos, parent, index) {
      String nodeText;
      if (node.isText) {
        final textValue = node.text!;
        final length = textValue.length;
        var begin = (from > pos ? from : pos) - pos;
        var end = to - pos;
        begin = begin < 0 ? 0 : (begin > length ? length : begin);
        end = end < 0 ? 0 : (end > length ? length : end);
        nodeText = end < begin ? "" : textValue.substring(begin, end);
      } else if (!node.isLeaf) {
        nodeText = "";
      } else if (leafText != null) {
        nodeText = leafText is String Function(Node) ? leafText(node) : leafText as String;
      } else if (node.type.spec.leafText != null) {
        nodeText = node.type.spec.leafText!(node);
      } else {
        nodeText = "";
      }
      if (node.isBlock && ((node.isLeaf && nodeText.isNotEmpty) || node.isTextblock) && blockSeparator != null) {
        if (first) {
          first = false;
        } else {
          text.write(blockSeparator);
        }
      }
      text.write(nodeText);
      return null;
    }, 0);
    return text.toString();
  }

  /// Create a new fragment containing the combined content of this fragment
  /// and the other.
  Fragment append(Fragment other) {
    if (other.size == 0) {
      return this;
    }
    if (size == 0) {
      return other;
    }
    final last = lastChild!;
    final first = other.firstChild!;
    final combined = List<Node>.of(content);
    var index = 0;
    if (last.isText && last.sameMarkup(first)) {
      final lastText = last as TextNode;
      combined[combined.length - 1] = lastText.withText(lastText.text + first.text!);
      index = 1;
    }
    for (; index < other.content.length; index++) {
      combined.add(other.content[index]);
    }
    return Fragment(combined, size + other.size);
  }

  /// Cut out the sub-fragment between the two given positions.
  Fragment cut(int from, [int? to]) {
    to ??= size;
    if (from == 0 && to == size) {
      return this;
    }
    final result = <Node>[];
    var newSize = 0;
    if (to > from) {
      var pos = 0;
      for (var index = 0; pos < to; index++) {
        var child = content[index];
        final end = pos + child.nodeSize;
        if (end > from) {
          if (pos < from || end > to) {
            if (child.isText) {
              child = child.cut(
                (from - pos) > 0 ? from - pos : 0,
                (to - pos) < child.text!.length ? to - pos : child.text!.length,
              );
            } else {
              child = child.cut(
                (from - pos - 1) > 0 ? from - pos - 1 : 0,
                (to - pos - 1) < child.content.size ? to - pos - 1 : child.content.size,
              );
            }
          }
          result.add(child);
          newSize += child.nodeSize;
        }
        pos = end;
      }
    }
    return Fragment(result, newSize);
  }

  /// @internal
  Fragment cutByIndex(int from, int to) {
    if (from == to) {
      return empty;
    }
    if (from == 0 && to == content.length) {
      return this;
    }
    return Fragment(content.sublist(from, to));
  }

  /// Create a new fragment in which the node at the given index is replaced by
  /// the given node.
  Fragment replaceChild(int index, Node node) {
    final current = content[index];
    if (identical(current, node)) {
      return this;
    }
    final copy = List<Node>.of(content);
    final newSize = size + node.nodeSize - current.nodeSize;
    copy[index] = node;
    return Fragment(copy, newSize);
  }

  /// Create a new fragment by prepending the given node to this fragment.
  Fragment addToStart(Node node) {
    return Fragment([node, ...content], size + node.nodeSize);
  }

  /// Create a new fragment by appending the given node to this fragment.
  Fragment addToEnd(Node node) {
    return Fragment([...content, node], size + node.nodeSize);
  }

  /// Compare this fragment to another one.
  bool eq(Fragment other) {
    if (content.length != other.content.length) {
      return false;
    }
    for (var index = 0; index < content.length; index++) {
      if (!content[index].eq(other.content[index])) {
        return false;
      }
    }
    return true;
  }

  /// The first child of the fragment, or `null` if it is empty.
  Node? get firstChild => content.isNotEmpty ? content[0] : null;

  /// The last child of the fragment, or `null` if it is empty.
  Node? get lastChild => content.isNotEmpty ? content[content.length - 1] : null;

  /// The number of child nodes in this fragment.
  int get childCount => content.length;

  /// Get the child node at the given index. Raises an error when the index is
  /// out of range.
  Node child(int index) {
    if (index < 0 || index >= content.length) {
      throw RangeError("Index $index out of range for $this");
    }
    return content[index];
  }

  /// Get the child node at the given index, if it exists.
  Node? maybeChild(int index) {
    return (index >= 0 && index < content.length) ? content[index] : null;
  }

  /// Call [callback] for every child node, passing the node, its offset into
  /// this parent node, and its index.
  void forEach(void Function(Node node, int offset, int index) callback) {
    var offset = 0;
    for (var index = 0; index < content.length; index++) {
      final child = content[index];
      callback(child, offset, index);
      offset += child.nodeSize;
    }
  }

  /// Find the first position at which this fragment and another fragment
  /// differ, or `null` if they are the same.
  int? findDiffStart(Fragment other, [int pos = 0]) {
    return diff.findDiffStart(this, other, pos);
  }

  /// Find the first position, searching from the end, at which this fragment
  /// and the given fragment differ, or `null` if they are the same.
  ({int a, int b})? findDiffEnd(Fragment other, [int? pos, int? otherPos]) {
    return diff.findDiffEnd(this, other, pos ?? size, otherPos ?? other.size);
  }

  /// Find the index and inner offset corresponding to a given relative
  /// position in this fragment. @internal
  ({int index, int offset}) findIndex(int pos) {
    if (pos == 0) {
      return (index: 0, offset: pos);
    }
    if (pos == size) {
      return (index: content.length, offset: pos);
    }
    if (pos > size || pos < 0) {
      throw RangeError("Position $pos outside of fragment ($this)");
    }
    var currentPos = 0;
    for (var index = 0; ; index++) {
      final currentChild = child(index);
      final end = currentPos + currentChild.nodeSize;
      if (end >= pos) {
        if (end == pos) {
          return (index: index + 1, offset: end);
        }
        return (index: index, offset: currentPos);
      }
      currentPos = end;
    }
  }

  /// Return a debugging string that describes this fragment.
  @override
  String toString() => "<${toStringInner()}>";

  /// @internal
  String toStringInner() => content.map((node) => node.toString()).join(", ");

  /// Create a JSON-serializeable representation of this fragment.
  Object? toJSON() {
    return content.isNotEmpty ? content.map((node) => node.toJSON()).toList() : null;
  }

  /// Deserialize a fragment from its JSON representation.
  static Fragment fromJSON(Schema schema, Object? value) {
    if (value == null) {
      return empty;
    }
    if (value is! List) {
      throw RangeError("Invalid input for Fragment.fromJSON");
    }
    return fromArray(value.map((json) => schema.nodeFromJSON(json)).toList());
  }

  /// Build a fragment from a list of nodes. Ensures that adjacent text nodes
  /// with the same marks are joined together.
  static Fragment fromArray(List<Node> array) {
    if (array.isEmpty) {
      return empty;
    }
    List<Node>? joined;
    var size = 0;
    for (var index = 0; index < array.length; index++) {
      final node = array[index];
      size += node.nodeSize;
      if (index != 0 && node.isText && array[index - 1].sameMarkup(node)) {
        joined ??= array.sublist(0, index);
        final previous = joined[joined.length - 1] as TextNode;
        joined[joined.length - 1] = (node as TextNode).withText(previous.text + node.text);
      } else if (joined != null) {
        joined.add(node);
      }
    }
    return Fragment(joined ?? array, size);
  }

  /// Create a fragment from something that can be interpreted as a set of
  /// nodes.
  static Fragment from(Object? nodes) {
    if (nodes == null) {
      return empty;
    }
    if (nodes is Fragment) {
      return nodes;
    }
    if (nodes is List<Node>) {
      return fromArray(nodes);
    }
    if (nodes is List) {
      return fromArray(nodes.cast<Node>());
    }
    if (nodes is Node) {
      return Fragment([nodes], nodes.nodeSize);
    }
    throw RangeError("Can not convert $nodes to a Fragment");
  }

  /// An empty fragment.
  static final Fragment empty = Fragment(const [], 0);
}
