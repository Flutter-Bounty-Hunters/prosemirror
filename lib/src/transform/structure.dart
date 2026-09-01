import 'package:prosemirror/src/model/content.dart';
import 'package:prosemirror/src/model/fragment.dart';
import 'package:prosemirror/src/model/mark.dart';
import 'package:prosemirror/src/model/node.dart';
import 'package:prosemirror/src/model/replace.dart';
import 'package:prosemirror/src/model/resolved_pos.dart';
import 'package:prosemirror/src/model/schema.dart';

import 'package:prosemirror/src/transform/transform.dart';
import 'package:prosemirror/src/transform/replace_step.dart';
import 'package:prosemirror/src/transform/mark.dart';

/// A wrapper description used by [findWrapping], [wrap], [canSplit] and
/// [split].
typedef NodeTypeWithAttributes = ({NodeType type, Attrs? attrs});

bool _canCut(Node node, int start, int end) {
  return (start == 0 || node.canReplace(start, node.childCount)) && (end == node.childCount || node.canReplace(0, end));
}

/// Try to find a target depth to which the content in the given range
/// can be lifted. Will not go across
/// [isolating](NodeSpec.isolating) parent nodes.
int? liftTarget(NodeRange range) {
  final parent = range.parent;
  final content = parent.content.cutByIndex(range.startIndex, range.endIndex);
  for (var depth = range.depth, contentBefore = 0, contentAfter = 0; ; --depth) {
    final node = range.$from.node(depth);
    final index = range.$from.index(depth) + contentBefore;
    final endIndex = range.$to.indexAfter(depth) - contentAfter;
    if (depth < range.depth && node.canReplace(index, endIndex, content)) {
      return depth;
    }
    if (depth == 0 || node.type.spec.isolating || !_canCut(node, index, endIndex)) {
      break;
    }
    if (index != 0) {
      contentBefore = 1;
    }
    if (endIndex < node.childCount) {
      contentAfter = 1;
    }
  }
  return null;
}

void lift(Transform tr, NodeRange range, int target) {
  final $from = range.$from;
  final $to = range.$to;
  final depth = range.depth;

  final gapStart = $from.before(depth + 1);
  final gapEnd = $to.after(depth + 1);
  var start = gapStart;
  var end = gapEnd;

  var before = Fragment.empty;
  var openStart = 0;
  for (var d = depth, splitting = false; d > target; d--) {
    if (splitting || $from.index(d) > 0) {
      splitting = true;
      before = Fragment.from($from.node(d).copy(before));
      openStart++;
    } else {
      start--;
    }
  }
  var after = Fragment.empty;
  var openEnd = 0;
  for (var d = depth, splitting = false; d > target; d--) {
    if (splitting || $to.after(d + 1) < $to.end(d)) {
      splitting = true;
      after = Fragment.from($to.node(d).copy(after));
      openEnd++;
    } else {
      end++;
    }
  }

  tr.step(
    ReplaceAroundStep(
      start,
      end,
      gapStart,
      gapEnd,
      Slice(before.append(after), openStart, openEnd),
      before.size - openStart,
      true,
    ),
  );
}

/// Try to find a valid way to wrap the content in the given range in a
/// node of the given type. May introduce extra nodes around and inside
/// the wrapper node, if necessary. Returns null if no valid wrapping
/// could be found. When `innerRange` is given, that range's content is
/// used as the content to fit into the wrapping, instead of the
/// content of `range`.
List<NodeTypeWithAttributes>? findWrapping(NodeRange range, NodeType nodeType, [Attrs? attrs, NodeRange? innerRange]) {
  innerRange ??= range;
  final around = _findWrappingOutside(range, nodeType);
  final inner = around != null ? _findWrappingInside(innerRange, nodeType) : null;
  if (inner == null) {
    return null;
  }
  return <NodeTypeWithAttributes>[...around!.map(_withAttrs), (type: nodeType, attrs: attrs), ...inner.map(_withAttrs)];
}

NodeTypeWithAttributes _withAttrs(NodeType type) => (type: type, attrs: null);

List<NodeType>? _findWrappingOutside(NodeRange range, NodeType type) {
  final parent = range.parent;
  final startIndex = range.startIndex;
  final endIndex = range.endIndex;
  final around = parent.contentMatchAt(startIndex).findWrapping(type);
  if (around == null) {
    return null;
  }
  final outer = around.isNotEmpty ? around[0] : type;
  return parent.canReplaceWith(startIndex, endIndex, outer) ? around : null;
}

List<NodeType>? _findWrappingInside(NodeRange range, NodeType type) {
  final parent = range.parent;
  final startIndex = range.startIndex;
  final endIndex = range.endIndex;
  final inner = parent.child(startIndex);
  final inside = type.contentMatch.findWrapping(inner.type);
  if (inside == null) {
    return null;
  }
  final lastType = inside.isNotEmpty ? inside[inside.length - 1] : type;
  ContentMatch? innerMatch = lastType.contentMatch;
  for (var i = startIndex; innerMatch != null && i < endIndex; i++) {
    innerMatch = innerMatch.matchType(parent.child(i).type);
  }
  if (innerMatch == null || !innerMatch.validEnd) {
    return null;
  }
  return inside;
}

void wrap(Transform tr, NodeRange range, List<NodeTypeWithAttributes> wrappers) {
  var content = Fragment.empty;
  for (var i = wrappers.length - 1; i >= 0; i--) {
    if (content.size != 0) {
      final match = wrappers[i].type.contentMatch.matchFragment(content);
      if (match == null || !match.validEnd) {
        throw RangeError("Wrapper type given to Transform.wrap does not form valid content of its parent wrapper");
      }
    }
    content = Fragment.from(wrappers[i].type.create(wrappers[i].attrs, content));
  }

  final start = range.start;
  final end = range.end;
  tr.step(ReplaceAroundStep(start, end, start, end, Slice(content, 0, 0), wrappers.length, true));
}

void setBlockType(Transform tr, int from, int to, NodeType type, Object? attrs) {
  if (!type.isTextblock) {
    throw RangeError("Type given to setBlockType should be a textblock");
  }
  final mapFrom = tr.steps.length;
  tr.doc.nodesBetween(from, to, (node, pos, parent, index) {
    final attrsHere = attrs is Attrs Function(Node) ? attrs(node) : attrs as Attrs?;
    if (node.isTextblock &&
        !node.hasMarkup(type, attrsHere) &&
        _canChangeType(tr.doc, tr.mapping.slice(mapFrom).map(pos), type)) {
      bool? convertNewlines;
      if (type.schema.linebreakReplacement != null) {
        final pre = type.whitespace == "pre";
        final supportLinebreak = type.contentMatch.matchType(type.schema.linebreakReplacement!) != null;
        if (pre && !supportLinebreak) {
          convertNewlines = false;
        } else if (!pre && supportLinebreak) {
          convertNewlines = true;
        }
      }
      // Ensure all markup that isn't allowed in the new node type is
      // cleared.
      if (convertNewlines == false) {
        _replaceLinebreaks(tr, node, pos, mapFrom);
      }
      clearIncompatible(tr, tr.mapping.slice(mapFrom).map(pos, 1), type, null, convertNewlines == null);
      final mapping = tr.mapping.slice(mapFrom);
      final startM = mapping.map(pos, 1);
      final endM = mapping.map(pos + node.nodeSize, 1);
      tr.step(
        ReplaceAroundStep(
          startM,
          endM,
          startM + 1,
          endM - 1,
          Slice(Fragment.from(type.create(attrsHere, null, node.marks)), 0, 0),
          1,
          true,
        ),
      );
      if (convertNewlines == true) {
        _replaceNewlines(tr, node, pos, mapFrom);
      }
      return false;
    }
    return null;
  });
}

void _replaceNewlines(Transform tr, Node node, int pos, int mapFrom) {
  node.forEach((child, offset, index) {
    if (child.isText) {
      final newline = RegExp(r'\r?\n|\r');
      for (final match in newline.allMatches(child.text!)) {
        final start = tr.mapping.slice(mapFrom).map(pos + 1 + offset + match.start);
        tr.replaceWith(start, start + 1, node.type.schema.linebreakReplacement!.create());
      }
    }
  });
}

void _replaceLinebreaks(Transform tr, Node node, int pos, int mapFrom) {
  node.forEach((child, offset, index) {
    if (child.type == child.type.schema.linebreakReplacement) {
      final start = tr.mapping.slice(mapFrom).map(pos + 1 + offset);
      tr.replaceWith(start, start + 1, node.type.schema.text("\n"));
    }
  });
}

bool _canChangeType(Node doc, int pos, NodeType type) {
  final $pos = doc.resolve(pos);
  final index = $pos.index();
  return $pos.parent.canReplaceWith(index, index + 1, type);
}

/// Change the type, attributes, and/or marks of the node at `pos`.
/// When `type` isn't given, the existing node type is preserved.
void setNodeMarkup(Transform tr, int pos, NodeType? type, Attrs? attrs, List<Mark>? marks) {
  final node = tr.doc.nodeAt(pos);
  if (node == null) {
    throw RangeError("No node at given position");
  }
  type ??= node.type;
  final newNode = type.create(attrs, null, marks ?? node.marks);
  if (node.isLeaf) {
    tr.replaceWith(pos, pos + node.nodeSize, newNode);
    return;
  }

  if (!type.validContent(node.content)) {
    throw RangeError("Invalid content for node type ${type.name}");
  }

  tr.step(
    ReplaceAroundStep(
      pos,
      pos + node.nodeSize,
      pos + 1,
      pos + node.nodeSize - 1,
      Slice(Fragment.from(newNode), 0, 0),
      1,
      true,
    ),
  );
}

/// Check whether splitting at the given position is allowed.
bool canSplit(Node doc, int pos, [int depth = 1, List<NodeTypeWithAttributes?>? typesAfter]) {
  final $pos = doc.resolve(pos);
  final base = $pos.depth - depth;
  final innerType = (typesAfter != null && typesAfter.isNotEmpty && typesAfter[typesAfter.length - 1] != null)
      ? typesAfter[typesAfter.length - 1]!.type
      : $pos.parent.type;
  if (base < 0 ||
      $pos.parent.type.spec.isolating ||
      !$pos.parent.canReplace($pos.index(), $pos.parent.childCount) ||
      !innerType.validContent($pos.parent.content.cutByIndex($pos.index(), $pos.parent.childCount))) {
    return false;
  }
  for (var d = $pos.depth - 1, i = depth - 2; d > base; d--, i--) {
    final node = $pos.node(d);
    final index = $pos.index(d);
    if (node.type.spec.isolating) {
      return false;
    }
    var rest = node.content.cutByIndex(index, node.childCount);
    final overrideChild = _typeAt(typesAfter, i + 1);
    if (overrideChild != null) {
      rest = rest.replaceChild(0, overrideChild.type.create(overrideChild.attrs));
    }
    final after = _typeAt(typesAfter, i);
    final afterType = after != null ? after.type : node.type;
    if (!node.canReplace(index + 1, node.childCount) || !afterType.validContent(rest)) {
      return false;
    }
  }
  final index = $pos.indexAfter(base);
  final baseType = _typeAt(typesAfter, 0);
  return $pos.node(base).canReplaceWith(index, index, baseType != null ? baseType.type : $pos.node(base + 1).type);
}

NodeTypeWithAttributes? _typeAt(List<NodeTypeWithAttributes?>? typesAfter, int index) {
  if (typesAfter == null || index < 0 || index >= typesAfter.length) {
    return null;
  }
  return typesAfter[index];
}

void split(Transform tr, int pos, [int depth = 1, List<NodeTypeWithAttributes?>? typesAfter]) {
  final $pos = tr.doc.resolve(pos);
  var before = Fragment.empty;
  var after = Fragment.empty;
  for (var d = $pos.depth, e = $pos.depth - depth, i = depth - 1; d > e; d--, i--) {
    before = Fragment.from($pos.node(d).copy(before));
    final typeAfter = _typeAt(typesAfter, i);
    after = Fragment.from(typeAfter != null ? typeAfter.type.create(typeAfter.attrs, after) : $pos.node(d).copy(after));
  }
  tr.step(ReplaceStep(pos, pos, Slice(before.append(after), depth, depth), true));
}

/// Test whether the blocks before and after a given position can be
/// joined.
bool canJoin(Node doc, int pos) {
  final $pos = doc.resolve(pos);
  final index = $pos.index();
  return _joinable($pos.nodeBefore, $pos.nodeAfter) && $pos.parent.canReplace(index, index + 1);
}

bool _canAppendWithSubstitutedLinebreaks(Node a, Node b) {
  if (b.content.size == 0) {
    a.type.compatibleContent(b.type);
  }
  ContentMatch? match = a.contentMatchAt(a.childCount);
  final linebreakReplacement = a.type.schema.linebreakReplacement;
  for (var i = 0; i < b.childCount; i++) {
    final child = b.child(i);
    final type = child.type == linebreakReplacement ? a.type.schema.nodes["text"]! : child.type;
    match = match!.matchType(type);
    if (match == null) {
      return false;
    }
    if (!a.type.allowsMarks(child.marks)) {
      return false;
    }
  }
  return match!.validEnd;
}

bool _joinable(Node? a, Node? b) {
  return a != null && b != null && !a.isLeaf && _canAppendWithSubstitutedLinebreaks(a, b);
}

/// Find an ancestor of the given position that can be joined to the
/// block before (or after if `dir` is positive). Returns the joinable
/// point, if any.
int? joinPoint(Node doc, int pos, [int dir = -1]) {
  final $pos = doc.resolve(pos);
  for (var d = $pos.depth; ; d--) {
    Node? before;
    Node? after;
    var index = $pos.index(d);
    if (d == $pos.depth) {
      before = $pos.nodeBefore;
      after = $pos.nodeAfter;
    } else if (dir > 0) {
      before = $pos.node(d + 1);
      index++;
      after = $pos.node(d).maybeChild(index);
    } else {
      before = $pos.node(d).maybeChild(index - 1);
      after = $pos.node(d + 1);
    }
    if (before != null &&
        !before.isTextblock &&
        _joinable(before, after) &&
        $pos.node(d).canReplace(index, index + 1)) {
      return pos;
    }
    if (d == 0) {
      break;
    }
    pos = dir < 0 ? $pos.before(d) : $pos.after(d);
  }
  return null;
}

void join(Transform tr, int pos, int depth) {
  bool? convertNewlines;
  final linebreakReplacement = tr.doc.type.schema.linebreakReplacement;
  final $before = tr.doc.resolve(pos - depth);
  final beforeType = $before.node().type;
  if (linebreakReplacement != null && beforeType.inlineContent) {
    final pre = beforeType.whitespace == "pre";
    final supportLinebreak = beforeType.contentMatch.matchType(linebreakReplacement) != null;
    if (pre && !supportLinebreak) {
      convertNewlines = false;
    } else if (!pre && supportLinebreak) {
      convertNewlines = true;
    }
  }
  final mapFrom = tr.steps.length;
  if (convertNewlines == false) {
    final $after = tr.doc.resolve(pos + depth);
    _replaceLinebreaks(tr, $after.node(), $after.before(), mapFrom);
  }
  if (beforeType.inlineContent) {
    clearIncompatible(
      tr,
      pos + depth - 1,
      beforeType,
      $before.node().contentMatchAt($before.index()),
      convertNewlines == null,
    );
  }
  final mapping = tr.mapping.slice(mapFrom);
  final start = mapping.map(pos - depth);
  tr.step(ReplaceStep(start, mapping.map(pos + depth, -1), Slice.empty, true));
  if (convertNewlines == true) {
    final $full = tr.doc.resolve(start);
    _replaceNewlines(tr, $full.node(), $full.before(), tr.steps.length);
  }
}

/// Try to find a point where a node of the given type can be inserted
/// near `pos`, by searching up the node hierarchy when `pos` itself
/// isn't a valid place but is at the start or end of a node. Return
/// null if no position was found.
int? insertPoint(Node doc, int pos, NodeType nodeType) {
  final $pos = doc.resolve(pos);
  if ($pos.parent.canReplaceWith($pos.index(), $pos.index(), nodeType)) {
    return pos;
  }

  if ($pos.parentOffset == 0) {
    for (var d = $pos.depth - 1; d >= 0; d--) {
      final index = $pos.index(d);
      if ($pos.node(d).canReplaceWith(index, index, nodeType)) {
        return $pos.before(d + 1);
      }
      if (index > 0) {
        return null;
      }
    }
  }
  if ($pos.parentOffset == $pos.parent.content.size) {
    for (var d = $pos.depth - 1; d >= 0; d--) {
      final index = $pos.indexAfter(d);
      if ($pos.node(d).canReplaceWith(index, index, nodeType)) {
        return $pos.after(d + 1);
      }
      if (index < $pos.node(d).childCount) {
        return null;
      }
    }
  }
  return null;
}

/// Finds a position at or around the given position where the given
/// slice can be inserted. Will look at parent nodes' nearest boundary
/// and try there, even if the original position wasn't directly at the
/// start or end of that node. Returns null when no position was found.
int? dropPoint(Node doc, int pos, Slice slice) {
  final $pos = doc.resolve(pos);
  if (slice.content.size == 0) {
    return pos;
  }
  var content = slice.content;
  for (var i = 0; i < slice.openStart; i++) {
    content = content.firstChild!.content;
  }
  final passes = slice.openStart == 0 && slice.size != 0 ? 2 : 1;
  for (var pass = 1; pass <= passes; pass++) {
    for (var d = $pos.depth; d >= 0; d--) {
      final bias = d == $pos.depth
          ? 0
          : $pos.pos <= ($pos.start(d + 1) + $pos.end(d + 1)) / 2
          ? -1
          : 1;
      final insertPos = $pos.index(d) + (bias > 0 ? 1 : 0);
      final parent = $pos.node(d);
      bool fits;
      if (pass == 1) {
        fits = parent.canReplace(insertPos, insertPos, content);
      } else {
        final wrapping = parent.contentMatchAt(insertPos).findWrapping(content.firstChild!.type);
        fits = wrapping != null && parent.canReplaceWith(insertPos, insertPos, wrapping[0]);
      }
      if (fits) {
        return bias == 0
            ? $pos.pos
            : bias < 0
            ? $pos.before(d + 1)
            : $pos.after(d + 1);
      }
    }
  }
  return null;
}
