import 'fragment.dart';
import 'node.dart';
import 'resolved_pos.dart';
import 'schema.dart';

/// Error type raised by [Node.replace] when given an invalid replacement.
class ReplaceError implements Exception {
  ReplaceError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A slice represents a piece cut out of a larger document. It stores not only
/// a fragment, but also the depth up to which nodes on both sides are 'open'
/// (cut through).
class Slice {
  /// Create a slice.
  Slice(this.content, this.openStart, this.openEnd);

  /// The slice's content.
  final Fragment content;

  /// The open depth at the start of the fragment.
  final int openStart;

  /// The open depth at the end.
  final int openEnd;

  /// The size this slice would add when inserted into a document.
  int get size => content.size - openStart - openEnd;

  /// @internal
  Slice? insertAt(int pos, Fragment fragment) {
    final content = _insertInto(this.content, pos + openStart, fragment, null);
    return content != null ? Slice(content, openStart, openEnd) : null;
  }

  /// @internal
  Slice removeBetween(int from, int to) {
    return Slice(
      _removeRange(content, from + openStart, to + openStart),
      openStart,
      openEnd,
    );
  }

  /// Tests whether this slice is equal to another slice.
  bool eq(Slice other) {
    return content.eq(other.content) &&
        openStart == other.openStart &&
        openEnd == other.openEnd;
  }

  /// @internal
  @override
  String toString() => "$content($openStart,$openEnd)";

  /// Convert a slice to a JSON-serializable representation.
  Object? toJSON() {
    if (content.size == 0) {
      return null;
    }
    final json = <String, Object?>{"content": content.toJSON()};
    if (openStart > 0) {
      json["openStart"] = openStart;
    }
    if (openEnd > 0) {
      json["openEnd"] = openEnd;
    }
    return json;
  }

  /// Deserialize a slice from its JSON representation.
  static Slice fromJSON(Schema schema, Object? json) {
    if (json == null) {
      return empty;
    }
    final map = json as Map<String, Object?>;
    final openStart = (map["openStart"] as int?) ?? 0;
    final openEnd = (map["openEnd"] as int?) ?? 0;
    return Slice(Fragment.fromJSON(schema, map["content"]), openStart, openEnd);
  }

  /// Create a slice from a fragment by taking the maximum possible open value
  /// on both sides of the fragment.
  static Slice maxOpen(Fragment fragment, [bool openIsolating = true]) {
    var openStart = 0;
    var openEnd = 0;
    for (
      Node? node = fragment.firstChild;
      node != null &&
          !node.isLeaf &&
          (openIsolating || !node.type.spec.isolating);
      node = node.firstChild
    ) {
      openStart++;
    }
    for (
      Node? node = fragment.lastChild;
      node != null &&
          !node.isLeaf &&
          (openIsolating || !node.type.spec.isolating);
      node = node.lastChild
    ) {
      openEnd++;
    }
    return Slice(fragment, openStart, openEnd);
  }

  /// The empty slice.
  static final Slice empty = Slice(Fragment.empty, 0, 0);
}

Fragment _removeRange(Fragment content, int from, int to) {
  final found = content.findIndex(from);
  final child = content.maybeChild(found.index);
  final foundTo = content.findIndex(to);
  if (found.offset == from || child!.isText) {
    if (foundTo.offset != to && !content.child(foundTo.index).isText) {
      throw RangeError("Removing non-flat range");
    }
    return content.cut(0, from).append(content.cut(to));
  }
  if (found.index != foundTo.index) {
    throw RangeError("Removing non-flat range");
  }
  return content.replaceChild(
    found.index,
    child.copy(
      _removeRange(
        child.content,
        from - found.offset - 1,
        to - found.offset - 1,
      ),
    ),
  );
}

Fragment? _insertInto(
  Fragment content,
  int dist,
  Fragment insert,
  Node? parent,
) {
  final found = content.findIndex(dist);
  final child = content.maybeChild(found.index);
  if (found.offset == dist || child!.isText) {
    if (parent != null &&
        !parent.canReplace(found.index, found.index, insert)) {
      return null;
    }
    return content.cut(0, dist).append(insert).append(content.cut(dist));
  }
  final inner = _insertInto(
    child.content,
    dist - found.offset - 1,
    insert,
    child,
  );
  return inner != null
      ? content.replaceChild(found.index, child.copy(inner))
      : null;
}

/// Replace the range between [$from] and [$to] with [slice].
Node replaceImpl(ResolvedPos $from, ResolvedPos $to, Slice slice) {
  if (slice.openStart > $from.depth) {
    throw ReplaceError("Inserted content deeper than insertion position");
  }
  if ($from.depth - slice.openStart != $to.depth - slice.openEnd) {
    throw ReplaceError("Inconsistent open depths");
  }
  return _replaceOuter($from, $to, slice, 0);
}

Node _replaceOuter(ResolvedPos $from, ResolvedPos $to, Slice slice, int depth) {
  final index = $from.index(depth);
  final node = $from.node(depth);
  if (index == $to.index(depth) && depth < $from.depth - slice.openStart) {
    final inner = _replaceOuter($from, $to, slice, depth + 1);
    return node.copy(node.content.replaceChild(index, inner));
  } else if (slice.content.size == 0) {
    return _close(node, _replaceTwoWay($from, $to, depth));
  } else if (slice.openStart == 0 &&
      slice.openEnd == 0 &&
      $from.depth == depth &&
      $to.depth == depth) {
    final parent = $from.parent;
    final content = parent.content;
    return _close(
      parent,
      content
          .cut(0, $from.parentOffset)
          .append(slice.content)
          .append(content.cut($to.parentOffset)),
    );
  } else {
    final prepared = _prepareSliceForReplace(slice, $from);
    return _close(
      node,
      _replaceThreeWay($from, prepared.start, prepared.end, $to, depth),
    );
  }
}

void _checkJoin(Node main, Node sub) {
  if (!sub.type.compatibleContent(main.type)) {
    throw ReplaceError("Cannot join ${sub.type.name} onto ${main.type.name}");
  }
}

Node _joinable(ResolvedPos $before, ResolvedPos $after, int depth) {
  final node = $before.node(depth);
  _checkJoin(node, $after.node(depth));
  return node;
}

void _addNode(Node child, List<Node> target) {
  final last = target.length - 1;
  if (last >= 0 && child.isText && child.sameMarkup(target[last])) {
    target[last] = (child as TextNode).withText(
      target[last].text! + child.text,
    );
  } else {
    target.add(child);
  }
}

void _addRange(
  ResolvedPos? $start,
  ResolvedPos? $end,
  int depth,
  List<Node> target,
) {
  final node = ($end ?? $start)!.node(depth);
  var startIndex = 0;
  final endIndex = $end != null ? $end.index(depth) : node.childCount;
  if ($start != null) {
    startIndex = $start.index(depth);
    if ($start.depth > depth) {
      startIndex++;
    } else if ($start.textOffset != 0) {
      _addNode($start.nodeAfter!, target);
      startIndex++;
    }
  }
  for (var index = startIndex; index < endIndex; index++) {
    _addNode(node.child(index), target);
  }
  if ($end != null && $end.depth == depth && $end.textOffset != 0) {
    _addNode($end.nodeBefore!, target);
  }
}

Node _close(Node node, Fragment content) {
  node.type.checkContent(content);
  return node.copy(content);
}

Fragment _replaceThreeWay(
  ResolvedPos $from,
  ResolvedPos $start,
  ResolvedPos $end,
  ResolvedPos $to,
  int depth,
) {
  final Node? openStart = $from.depth > depth
      ? _joinable($from, $start, depth + 1)
      : null;
  final Node? openEnd = $to.depth > depth
      ? _joinable($end, $to, depth + 1)
      : null;

  final content = <Node>[];
  _addRange(null, $from, depth, content);
  if (openStart != null &&
      openEnd != null &&
      $start.index(depth) == $end.index(depth)) {
    _checkJoin(openStart, openEnd);
    _addNode(
      _close(openStart, _replaceThreeWay($from, $start, $end, $to, depth + 1)),
      content,
    );
  } else {
    if (openStart != null) {
      _addNode(
        _close(openStart, _replaceTwoWay($from, $start, depth + 1)),
        content,
      );
    }
    _addRange($start, $end, depth, content);
    if (openEnd != null) {
      _addNode(_close(openEnd, _replaceTwoWay($end, $to, depth + 1)), content);
    }
  }
  _addRange($to, null, depth, content);
  return Fragment(content);
}

Fragment _replaceTwoWay(ResolvedPos $from, ResolvedPos $to, int depth) {
  final content = <Node>[];
  _addRange(null, $from, depth, content);
  if ($from.depth > depth) {
    final type = _joinable($from, $to, depth + 1);
    _addNode(_close(type, _replaceTwoWay($from, $to, depth + 1)), content);
  }
  _addRange($to, null, depth, content);
  return Fragment(content);
}

({ResolvedPos start, ResolvedPos end}) _prepareSliceForReplace(
  Slice slice,
  ResolvedPos $along,
) {
  final extra = $along.depth - slice.openStart;
  final parent = $along.node(extra);
  var node = parent.copy(slice.content);
  for (var index = extra - 1; index >= 0; index--) {
    node = $along.node(index).copy(Fragment.from(node));
  }
  return (
    start: node.resolveNoCache(slice.openStart + extra),
    end: node.resolveNoCache(node.content.size - slice.openEnd - extra),
  );
}
