import 'package:prosemirror/src/model/mark.dart';
import 'package:prosemirror/src/model/node.dart';

/// You can resolve a position to get more information about it. Objects of this
/// class represent such a resolved position, providing various pieces of
/// context information, and some helper methods.
class ResolvedPos {
  /// @internal
  ResolvedPos(this.pos, this.path, this.parentOffset) {
    depth = path.length ~/ 3 - 1;
  }

  /// The position that was resolved.
  final int pos;

  /// @internal
  final List<Object?> path;

  /// The offset this position has into its parent node.
  final int parentOffset;

  /// The number of levels the parent node is from the root.
  late final int depth;

  /// @internal
  int resolveDepth(int? value) {
    if (value == null) {
      return depth;
    }
    if (value < 0) {
      return depth + value;
    }
    return value;
  }

  /// The parent node that the position points into.
  Node get parent => node(depth);

  /// The root node in which the position was resolved.
  Node get doc => node(0);

  /// The ancestor node at the given level.
  Node node([int? depth]) => path[resolveDepth(depth) * 3] as Node;

  /// The index into the ancestor at the given level.
  int index([int? depth]) => path[resolveDepth(depth) * 3 + 1] as int;

  /// The index pointing after this position into the ancestor at the given
  /// level.
  int indexAfter([int? depth]) {
    final resolved = resolveDepth(depth);
    return index(resolved) + (resolved == this.depth && textOffset == 0 ? 0 : 1);
  }

  /// The (absolute) position at the start of the node at the given level.
  int start([int? depth]) {
    final resolved = resolveDepth(depth);
    return resolved == 0 ? 0 : (path[resolved * 3 - 1] as int) + 1;
  }

  /// The (absolute) position at the end of the node at the given level.
  int end([int? depth]) {
    final resolved = resolveDepth(depth);
    return start(resolved) + node(resolved).content.size;
  }

  /// The (absolute) position directly before the wrapping node at the given
  /// level, or, when [depth] is `this.depth + 1`, the original position.
  int before([int? depth]) {
    final resolved = resolveDepth(depth);
    if (resolved == 0) {
      throw RangeError("There is no position before the top-level node");
    }
    return resolved == this.depth + 1 ? pos : path[resolved * 3 - 1] as int;
  }

  /// The (absolute) position directly after the wrapping node at the given
  /// level, or the original position when [depth] is `this.depth + 1`.
  int after([int? depth]) {
    final resolved = resolveDepth(depth);
    if (resolved == 0) {
      throw RangeError("There is no position after the top-level node");
    }
    return resolved == this.depth + 1 ? pos : (path[resolved * 3 - 1] as int) + (path[resolved * 3] as Node).nodeSize;
  }

  /// When this position points into a text node, the distance between the
  /// position and the start of the text node.
  int get textOffset => pos - (path[path.length - 1] as int);

  /// Get the node directly after the position, if any.
  Node? get nodeAfter {
    final parent = this.parent;
    final index = this.index(depth);
    if (index == parent.childCount) {
      return null;
    }
    final offset = pos - (path[path.length - 1] as int);
    final child = parent.child(index);
    return offset != 0 ? parent.child(index).cut(offset) : child;
  }

  /// Get the node directly before the position, if any.
  Node? get nodeBefore {
    final index = this.index(depth);
    final offset = pos - (path[path.length - 1] as int);
    if (offset != 0) {
      return parent.child(index).cut(0, offset);
    }
    return index == 0 ? null : parent.child(index - 1);
  }

  /// Get the position at the given index in the parent node at the given depth.
  int posAtIndex(int index, [int? depth]) {
    final resolved = resolveDepth(depth);
    final node = path[resolved * 3] as Node;
    var pos = resolved == 0 ? 0 : (path[resolved * 3 - 1] as int) + 1;
    for (var currentIndex = 0; currentIndex < index; currentIndex++) {
      pos += node.child(currentIndex).nodeSize;
    }
    return pos;
  }

  /// Get the marks at this position, factoring in the surrounding marks'
  /// inclusive property.
  List<Mark> marks() {
    final parent = this.parent;
    final index = this.index();

    if (parent.content.size == 0) {
      return Mark.none;
    }

    if (textOffset != 0) {
      return parent.child(index).marks;
    }

    var main = parent.maybeChild(index - 1);
    var other = parent.maybeChild(index);
    if (main == null) {
      final temp = main;
      main = other;
      other = temp;
    }

    var marks = main!.marks;
    for (var markIndex = 0; markIndex < marks.length; markIndex++) {
      if (marks[markIndex].type.spec.inclusive == false && (other == null || !marks[markIndex].isInSet(other.marks))) {
        marks = marks[markIndex].removeFromSet(marks);
        markIndex--;
      }
    }

    return marks;
  }

  /// Get the marks after the current position, if any, except those that are
  /// non-inclusive and not present at position [$end].
  List<Mark>? marksAcross(ResolvedPos $end) {
    final after = parent.maybeChild(index());
    if (after == null || !after.isInline) {
      return null;
    }

    var marks = after.marks;
    final next = $end.parent.maybeChild($end.index());
    for (var markIndex = 0; markIndex < marks.length; markIndex++) {
      if (marks[markIndex].type.spec.inclusive == false && (next == null || !marks[markIndex].isInSet(next.marks))) {
        marks = marks[markIndex].removeFromSet(marks);
        markIndex--;
      }
    }
    return marks;
  }

  /// The depth up to which this position and the given position share the same
  /// parent nodes.
  int sharedDepth(int pos) {
    for (var depth = this.depth; depth > 0; depth--) {
      if (start(depth) <= pos && end(depth) >= pos) {
        return depth;
      }
    }
    return 0;
  }

  /// Returns a range based on the place where this position and the given
  /// position diverge around block content.
  NodeRange? blockRange([ResolvedPos? other, bool Function(Node)? predicate]) {
    other ??= this;
    if (other.pos < pos) {
      return other.blockRange(this);
    }
    for (
      var currentDepth = depth - (parent.inlineContent || pos == other.pos ? 1 : 0);
      currentDepth >= 0;
      currentDepth--
    ) {
      if (other.pos <= end(currentDepth) && (predicate == null || predicate(node(currentDepth)))) {
        return NodeRange(this, other, currentDepth);
      }
    }
    return null;
  }

  /// Query whether the given position shares the same parent node.
  bool sameParent(ResolvedPos other) {
    return pos - parentOffset == other.pos - other.parentOffset;
  }

  /// Return the greater of this and the given position.
  ResolvedPos max(ResolvedPos other) {
    return other.pos > pos ? other : this;
  }

  /// Return the smaller of this and the given position.
  ResolvedPos min(ResolvedPos other) {
    return other.pos < pos ? other : this;
  }

  /// @internal
  @override
  String toString() {
    var result = "";
    for (var level = 1; level <= depth; level++) {
      result += "${result.isNotEmpty ? "/" : ""}${node(level).type.name}_${index(level - 1)}";
    }
    return "$result:$parentOffset";
  }

  /// @internal
  static ResolvedPos resolve(Node doc, int pos) {
    if (!(pos >= 0 && pos <= doc.content.size)) {
      throw RangeError("Position $pos out of range");
    }
    final path = <Object?>[];
    var start = 0;
    var parentOffset = pos;
    for (Node node = doc; ;) {
      final found = node.content.findIndex(parentOffset);
      final remaining = parentOffset - found.offset;
      path.add(node);
      path.add(found.index);
      path.add(start + found.offset);
      if (remaining == 0) {
        break;
      }
      node = node.child(found.index);
      if (node.isText) {
        break;
      }
      parentOffset = remaining - 1;
      start += found.offset + 1;
    }
    return ResolvedPos(pos, path, parentOffset);
  }

  /// @internal
  static ResolvedPos resolveCached(Node doc, int pos) {
    var cache = _resolveCache[doc];
    if (cache != null) {
      for (var index = 0; index < cache.elements.length; index++) {
        final element = cache.elements[index];
        if (element.pos == pos) {
          return element;
        }
      }
    } else {
      cache = _ResolveCache();
      _resolveCache[doc] = cache;
    }
    final result = ResolvedPos.resolve(doc, pos);
    if (cache.elements.length <= cache.index) {
      cache.elements.add(result);
    } else {
      cache.elements[cache.index] = result;
    }
    cache.index = (cache.index + 1) % _resolveCacheSize;
    return result;
  }
}

class _ResolveCache {
  final List<ResolvedPos> elements = [];
  int index = 0;
}

const int _resolveCacheSize = 12;
final Expando<_ResolveCache> _resolveCache = Expando<_ResolveCache>();

/// Represents a flat range of content, i.e. one that starts and ends in the
/// same node.
class NodeRange {
  /// Construct a node range.
  NodeRange(this.$from, this.$to, this.depth);

  /// A resolved position along the start of the content.
  final ResolvedPos $from;

  /// A position along the end of the content.
  final ResolvedPos $to;

  /// The depth of the node that this range points into.
  final int depth;

  /// The position at the start of the range.
  int get start => $from.before(depth + 1);

  /// The position at the end of the range.
  int get end => $to.after(depth + 1);

  /// The parent node that the range points into.
  Node get parent => $from.node(depth);

  /// The start index of the range in the parent node.
  int get startIndex => $from.index(depth);

  /// The end index of the range in the parent node.
  int get endIndex => $to.indexAfter(depth);
}
