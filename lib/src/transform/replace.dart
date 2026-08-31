import 'dart:math' as math;

import 'package:prosemirror/src/model/content.dart';
import 'package:prosemirror/src/model/fragment.dart';
import 'package:prosemirror/src/model/node.dart';
import 'package:prosemirror/src/model/replace.dart';
import 'package:prosemirror/src/model/resolved_pos.dart';
import 'package:prosemirror/src/model/schema.dart';

import 'package:prosemirror/src/transform/step.dart';
import 'package:prosemirror/src/transform/replace_step.dart';
import 'package:prosemirror/src/transform/structure.dart';
import 'package:prosemirror/src/transform/transform.dart';

/// 'Fit' a slice into a given position in the document, producing a
/// [Step] that inserts it. Will return null if there's no meaningful
/// way to insert the slice here, or inserting it would be a no-op (an
/// empty slice over an empty range).
Step? replaceStep(Node doc, int from, [int? to, Slice? slice]) {
  to ??= from;
  slice ??= Slice.empty;
  if (from == to && slice.size == 0) {
    return null;
  }

  final $from = doc.resolve(from);
  final $to = doc.resolve(to);
  // Optimization -- avoid work if it's obvious that it's not needed.
  if (_fitsTrivially($from, $to, slice)) {
    return ReplaceStep(from, to, slice);
  }
  return _Fitter($from, $to, slice).fit();
}

bool _fitsTrivially(ResolvedPos $from, ResolvedPos $to, Slice slice) {
  return slice.openStart == 0 &&
      slice.openEnd == 0 &&
      $from.start() == $to.start() &&
      $from.parent.canReplace($from.index(), $to.index(), slice.content);
}

class _Fittable {
  _Fittable({
    required this.sliceDepth,
    required this.frontierDepth,
    required this.parent,
    this.inject,
    this.wrap,
  });

  final int sliceDepth;
  final int frontierDepth;
  final Node? parent;
  final Fragment? inject;
  final List<NodeType>? wrap;
}

class _FrontierEntry {
  _FrontierEntry(this.type, this.match);

  NodeType type;
  ContentMatch match;
}

// Algorithm for 'placing' the elements of a slice into a gap.
class _Fitter {
  _Fitter(this.$from, this.$to, this.unplaced) {
    for (var i = 0; i <= $from.depth; i++) {
      final node = $from.node(i);
      frontier.add(
        _FrontierEntry(node.type, node.contentMatchAt($from.indexAfter(i))),
      );
    }

    for (var i = $from.depth; i > 0; i--) {
      placed = Fragment.from($from.node(i).copy(placed));
    }
  }

  final ResolvedPos $from;
  final ResolvedPos $to;
  Slice unplaced;

  final List<_FrontierEntry> frontier = <_FrontierEntry>[];
  Fragment placed = Fragment.empty;

  int get depth => frontier.length - 1;

  Step? fit() {
    // As long as there's unplaced content, try to place some of it.
    // If that fails, either increase the open score of the unplaced
    // slice, or drop nodes from it, and then try again.
    while (unplaced.size != 0) {
      final fit = findFittable();
      if (fit != null) {
        placeNodes(fit);
      } else {
        if (!openMore()) {
          dropNode();
        }
      }
    }
    // When there's inline content directly after the frontier _and_
    // directly after `this.$to`, we must generate a `ReplaceAround`
    // step that pulls that content into the node after the frontier.
    final moveInline = mustMoveInline();
    final $from = this.$from;
    final placedSize = placed.size - depth - $from.depth;
    final $to = close(
      moveInline < 0 ? this.$to : $from.doc.resolve(moveInline),
    );
    if ($to == null) {
      return null;
    }

    // If closing to `$to` succeeded, create a step.
    var content = placed;
    var openStart = $from.depth;
    var openEnd = $to.depth;
    while (openStart != 0 && openEnd != 0 && content.childCount == 1) {
      // Normalize by dropping open parent nodes.
      content = content.firstChild!.content;
      openStart--;
      openEnd--;
    }
    final slice = Slice(content, openStart, openEnd);
    if (moveInline > -1) {
      return ReplaceAroundStep(
        $from.pos,
        moveInline,
        this.$to.pos,
        this.$to.end(),
        slice,
        placedSize,
      );
    }
    if (slice.size != 0 || $from.pos != this.$to.pos) {
      // Don't generate no-op steps.
      return ReplaceStep($from.pos, $to.pos, slice);
    }
    return null;
  }

  // Find a position on the start spine of `this.unplaced` that has
  // content that can be moved somewhere on the frontier.
  _Fittable? findFittable() {
    var startDepth = unplaced.openStart;
    {
      var current = unplaced.content;
      var openEnd = unplaced.openEnd;
      for (var d = 0; d < startDepth; d++) {
        final node = current.firstChild!;
        if (current.childCount > 1) {
          openEnd = 0;
        }
        if (node.type.spec.isolating && openEnd <= d) {
          startDepth = d;
          break;
        }
        current = node.content;
      }
    }

    // Only try wrapping nodes (pass 2) after finding a place without
    // wrapping failed.
    for (var pass = 1; pass <= 2; pass++) {
      for (
        var sliceDepth = pass == 1 ? startDepth : unplaced.openStart;
        sliceDepth >= 0;
        sliceDepth--
      ) {
        Fragment fragment;
        Node? parent;
        if (sliceDepth != 0) {
          parent = _contentAt(unplaced.content, sliceDepth - 1).firstChild;
          fragment = parent!.content;
        } else {
          fragment = unplaced.content;
        }
        final first = fragment.firstChild;
        for (var frontierDepth = depth; frontierDepth >= 0; frontierDepth--) {
          final entry = frontier[frontierDepth];
          final type = entry.type;
          final match = entry.match;
          List<NodeType>? wrap;
          Fragment? inject;
          // In pass 1, if the next node matches, or there is no next
          // node but the parents look compatible, we've found a place.
          if (pass == 1 &&
              (first != null
                  ? match.matchType(first.type) != null ||
                        (inject = match.fillBefore(
                              Fragment.from(first),
                              false,
                            )) !=
                            null
                  : parent != null && type.compatibleContent(parent.type))) {
            return _Fittable(
              sliceDepth: sliceDepth,
              frontierDepth: frontierDepth,
              parent: parent,
              inject: inject,
            );
          } else if (pass == 2 &&
              first != null &&
              (wrap = match.findWrapping(first.type)) != null) {
            return _Fittable(
              sliceDepth: sliceDepth,
              frontierDepth: frontierDepth,
              parent: parent,
              wrap: wrap,
            );
          }
          // Don't continue looking further up if the parent node would
          // fit here.
          if (parent != null && match.matchType(parent.type) != null) {
            break;
          }
        }
      }
    }
    return null;
  }

  bool openMore() {
    final content = unplaced.content;
    final openStart = unplaced.openStart;
    final openEnd = unplaced.openEnd;
    final inner = _contentAt(content, openStart);
    if (inner.childCount == 0 || inner.firstChild!.isLeaf) {
      return false;
    }
    unplaced = Slice(
      content,
      openStart + 1,
      math.max(
        openEnd,
        inner.size + openStart >= content.size - openEnd ? openStart + 1 : 0,
      ),
    );
    return true;
  }

  void dropNode() {
    final content = unplaced.content;
    final openStart = unplaced.openStart;
    final openEnd = unplaced.openEnd;
    final inner = _contentAt(content, openStart);
    if (inner.childCount <= 1 && openStart > 0) {
      final openAtEnd = content.size - openStart <= openStart + inner.size;
      unplaced = Slice(
        _dropFromFragment(content, openStart - 1, 1),
        openStart - 1,
        openAtEnd ? openStart - 1 : openEnd,
      );
    } else {
      unplaced = Slice(
        _dropFromFragment(content, openStart, 1),
        openStart,
        openEnd,
      );
    }
  }

  // Move content from the unplaced slice at `sliceDepth` to the
  // frontier node at `frontierDepth`. Close that frontier node when
  // applicable.
  void placeNodes(_Fittable fittable) {
    final sliceDepth = fittable.sliceDepth;
    final frontierDepth = fittable.frontierDepth;
    final parent = fittable.parent;
    final inject = fittable.inject;
    final wrap = fittable.wrap;

    while (depth > frontierDepth) {
      closeFrontierNode();
    }
    if (wrap != null) {
      for (var i = 0; i < wrap.length; i++) {
        openFrontierNode(wrap[i]);
      }
    }

    final slice = unplaced;
    final fragment = parent != null ? parent.content : slice.content;
    final openStart = slice.openStart - sliceDepth;
    var taken = 0;
    final add = <Node>[];
    var match = frontier[frontierDepth].match;
    final type = frontier[frontierDepth].type;
    if (inject != null) {
      for (var i = 0; i < inject.childCount; i++) {
        add.add(inject.child(i));
      }
      match = match.matchFragment(inject)!;
    }
    // Computes the amount of (end) open nodes at the end of the
    // fragment. When 0, the parent is open, but no more. When negative,
    // nothing is open.
    var openEndCount =
        (fragment.size + sliceDepth) - (slice.content.size - slice.openEnd);
    // Scan over the fragment, fitting as many child nodes as possible.
    while (taken < fragment.childCount) {
      final next = fragment.child(taken);
      final matches = match.matchType(next.type);
      if (matches == null) {
        break;
      }
      taken++;
      if (taken > 1 || openStart == 0 || next.content.size != 0) {
        // Drop empty open nodes.
        match = matches;
        add.add(
          _closeNodeStart(
            next.mark(type.allowedMarks(next.marks)),
            taken == 1 ? openStart : 0,
            taken == fragment.childCount ? openEndCount : -1,
          ),
        );
      }
    }
    final toEnd = taken == fragment.childCount;
    if (!toEnd) {
      openEndCount = -1;
    }

    placed = _addToFragment(placed, frontierDepth, Fragment.from(add));
    frontier[frontierDepth].match = match;

    // If the parent types match, and the entire node was moved, and
    // it's not open, close this frontier node right away.
    if (toEnd &&
        openEndCount < 0 &&
        parent != null &&
        parent.type == frontier[depth].type &&
        frontier.length > 1) {
      closeFrontierNode();
    }

    // Add new frontier nodes for any open nodes at the end.
    {
      var current = fragment;
      for (var i = 0; i < openEndCount; i++) {
        final node = current.lastChild!;
        frontier.add(
          _FrontierEntry(node.type, node.contentMatchAt(node.childCount)),
        );
        current = node.content;
      }
    }

    // Update `this.unplaced`. Drop the entire node from which we placed
    // it if we got to its end, otherwise just drop the placed nodes.
    if (!toEnd) {
      unplaced = Slice(
        _dropFromFragment(slice.content, sliceDepth, taken),
        slice.openStart,
        slice.openEnd,
      );
    } else if (sliceDepth == 0) {
      unplaced = Slice.empty;
    } else {
      unplaced = Slice(
        _dropFromFragment(slice.content, sliceDepth - 1, 1),
        sliceDepth - 1,
        openEndCount < 0 ? slice.openEnd : sliceDepth - 1,
      );
    }
  }

  int mustMoveInline() {
    if (!$to.parent.isTextblock) {
      return -1;
    }
    final top = frontier[depth];
    _CloseLevel? level;
    if (!top.type.isTextblock ||
        contentAfterFits($to, $to.depth, top.type, top.match, false) == null ||
        ($to.depth == depth &&
            (level = findCloseLevel($to)) != null &&
            level!.depth == depth)) {
      return -1;
    }

    var toDepth = $to.depth;
    var after = $to.after(toDepth);
    while (toDepth > 1 && after == $to.end(--toDepth)) {
      ++after;
    }
    return after;
  }

  _CloseLevel? findCloseLevel(ResolvedPos $to) {
    outer:
    for (var i = math.min(depth, $to.depth); i >= 0; i--) {
      final match = frontier[i].match;
      final type = frontier[i].type;
      final dropInner =
          i < $to.depth && $to.end(i + 1) == $to.pos + ($to.depth - (i + 1));
      final fit = contentAfterFits($to, i, type, match, dropInner);
      if (fit == null) {
        continue;
      }
      for (var d = i - 1; d >= 0; d--) {
        final innerMatch = frontier[d].match;
        final innerType = frontier[d].type;
        final matches = contentAfterFits($to, d, innerType, innerMatch, true);
        if (matches == null || matches.childCount != 0) {
          continue outer;
        }
      }
      return _CloseLevel(
        depth: i,
        fit: fit,
        move: dropInner ? $to.doc.resolve($to.after(i + 1)) : $to,
      );
    }
    return null;
  }

  ResolvedPos? close(ResolvedPos $to) {
    final close = findCloseLevel($to);
    if (close == null) {
      return null;
    }

    while (depth > close.depth) {
      closeFrontierNode();
    }
    if (close.fit.childCount != 0) {
      placed = _addToFragment(placed, close.depth, close.fit);
    }
    $to = close.move;
    for (var d = close.depth + 1; d <= $to.depth; d++) {
      final node = $to.node(d);
      final add = node.type.contentMatch.fillBefore(
        node.content,
        true,
        $to.index(d),
      )!;
      openFrontierNode(node.type, node.attrs, add);
    }
    return $to;
  }

  void openFrontierNode(NodeType type, [Attrs? attrs, Fragment? content]) {
    final top = frontier[depth];
    top.match = top.match.matchType(type)!;
    placed = _addToFragment(
      placed,
      depth,
      Fragment.from(type.create(attrs, content)),
    );
    frontier.add(_FrontierEntry(type, type.contentMatch));
  }

  void closeFrontierNode() {
    final open = frontier.removeLast();
    final add = open.match.fillBefore(Fragment.empty, true)!;
    if (add.childCount != 0) {
      placed = _addToFragment(placed, frontier.length, add);
    }
  }
}

class _CloseLevel {
  _CloseLevel({required this.depth, required this.fit, required this.move});

  final int depth;
  final Fragment fit;
  final ResolvedPos move;
}

Fragment _dropFromFragment(Fragment fragment, int depth, int count) {
  if (depth == 0) {
    return fragment.cutByIndex(count, fragment.childCount);
  }
  return fragment.replaceChild(
    0,
    fragment.firstChild!.copy(
      _dropFromFragment(fragment.firstChild!.content, depth - 1, count),
    ),
  );
}

Fragment _addToFragment(Fragment fragment, int depth, Fragment content) {
  if (depth == 0) {
    return fragment.append(content);
  }
  return fragment.replaceChild(
    fragment.childCount - 1,
    fragment.lastChild!.copy(
      _addToFragment(fragment.lastChild!.content, depth - 1, content),
    ),
  );
}

Fragment _contentAt(Fragment fragment, int depth) {
  for (var i = 0; i < depth; i++) {
    fragment = fragment.firstChild!.content;
  }
  return fragment;
}

Node _closeNodeStart(Node node, int openStart, int openEnd) {
  if (openStart <= 0) {
    return node;
  }
  var fragment = node.content;
  if (openStart > 1) {
    fragment = fragment.replaceChild(
      0,
      _closeNodeStart(
        fragment.firstChild!,
        openStart - 1,
        fragment.childCount == 1 ? openEnd - 1 : 0,
      ),
    );
  }
  if (openStart > 0) {
    fragment = node.type.contentMatch.fillBefore(fragment)!.append(fragment);
    if (openEnd <= 0) {
      fragment = fragment.append(
        node.type.contentMatch
            .matchFragment(fragment)!
            .fillBefore(Fragment.empty, true)!,
      );
    }
  }
  return node.copy(fragment);
}

Fragment? contentAfterFits(
  ResolvedPos $to,
  int depth,
  NodeType type,
  ContentMatch match,
  bool open,
) {
  final node = $to.node(depth);
  final index = open ? $to.indexAfter(depth) : $to.index(depth);
  if (index == node.childCount && !type.compatibleContent(node.type)) {
    return null;
  }
  final fit = match.fillBefore(node.content, true, index);
  return fit != null && !_invalidMarks(type, node.content, index) ? fit : null;
}

bool _invalidMarks(NodeType type, Fragment fragment, int start) {
  for (var i = start; i < fragment.childCount; i++) {
    if (!type.allowsMarks(fragment.child(i).marks)) {
      return true;
    }
  }
  return false;
}

bool _definesContent(NodeType type) {
  return type.spec.defining || type.spec.definingForContent;
}

void replaceRange(Transform tr, int from, int to, Slice slice) {
  if (slice.size == 0) {
    tr.deleteRange(from, to);
    return;
  }

  var $from = tr.doc.resolve(from);
  var $to = tr.doc.resolve(to);
  if (_fitsTrivially($from, $to, slice)) {
    tr.step(ReplaceStep(from, to, slice));
    return;
  }

  final targetDepths = _coveredDepths($from, $to);
  // Can't replace the whole document, so remove 0 if it's present.
  if (targetDepths.isNotEmpty && targetDepths[targetDepths.length - 1] == 0) {
    targetDepths.removeLast();
  }
  // Negative numbers represent not expansion over the whole node at
  // that depth, but replacing from $from.before(-D) to $to.pos.
  var preferredTarget = -($from.depth + 1);
  targetDepths.insert(0, preferredTarget);
  // This loop picks a preferred target depth, if one of the covering
  // depths is not outside of a defining node, and adds negative depths
  // for any depth that has $from at its start and does not cross a
  // defining node.
  for (var d = $from.depth, pos = $from.pos - 1; d > 0; d--, pos--) {
    final spec = $from.node(d).type.spec;
    if (spec.defining || spec.definingAsContext || spec.isolating) {
      break;
    }
    if (targetDepths.contains(d)) {
      preferredTarget = d;
    } else if ($from.before(d) == pos) {
      targetDepths.insert(1, -d);
    }
  }
  // Try to fit each possible depth of the slice into each possible
  // target depth, starting with the preferred depths.
  final preferredTargetIndex = targetDepths.indexOf(preferredTarget);

  final leftNodes = <Node?>[];
  var preferredDepth = slice.openStart;
  {
    var content = slice.content;
    for (var i = 0; ; i++) {
      final node = content.firstChild;
      leftNodes.add(node);
      if (i == slice.openStart) {
        break;
      }
      content = node!.content;
    }
  }

  // Back up preferredDepth to cover defining textblocks directly above
  // it, possibly skipping a non-defining textblock.
  for (var d = preferredDepth - 1; d >= 0; d--) {
    final leftNode = leftNodes[d]!;
    final defining = _definesContent(leftNode.type);
    if (defining &&
        !leftNode.sameMarkup($from.node(preferredTarget.abs() - 1))) {
      preferredDepth = d;
    } else if (defining || !leftNode.type.isTextblock) {
      break;
    }
  }

  for (var j = slice.openStart; j >= 0; j--) {
    final openDepth = (j + preferredDepth + 1) % (slice.openStart + 1);
    final insert = openDepth < leftNodes.length ? leftNodes[openDepth] : null;
    if (insert == null) {
      continue;
    }
    for (var i = 0; i < targetDepths.length; i++) {
      // Loop over possible expansion levels, starting with the
      // preferred one.
      var targetDepth =
          targetDepths[(i + preferredTargetIndex) % targetDepths.length];
      var expand = true;
      if (targetDepth < 0) {
        expand = false;
        targetDepth = -targetDepth;
      }
      final parent = $from.node(targetDepth - 1);
      final index = $from.index(targetDepth - 1);
      if (parent.canReplaceWith(index, index, insert.type, insert.marks)) {
        tr.replace(
          $from.before(targetDepth),
          expand ? $to.after(targetDepth) : to,
          Slice(
            _closeFragment(slice.content, 0, slice.openStart, openDepth),
            openDepth,
            slice.openEnd,
          ),
        );
        return;
      }
    }
  }

  final startSteps = tr.steps.length;
  for (var i = targetDepths.length - 1; i >= 0; i--) {
    tr.replace(from, to, slice);
    if (tr.steps.length > startSteps) {
      break;
    }
    final depth = targetDepths[i];
    if (depth < 0) {
      continue;
    }
    from = $from.before(depth);
    to = $to.after(depth);
  }
}

Fragment _closeFragment(
  Fragment fragment,
  int depth,
  int oldOpen,
  int newOpen, [
  Node? parent,
]) {
  if (depth < oldOpen) {
    final first = fragment.firstChild!;
    fragment = fragment.replaceChild(
      0,
      first.copy(
        _closeFragment(first.content, depth + 1, oldOpen, newOpen, first),
      ),
    );
  }
  if (depth > newOpen) {
    final match = parent!.contentMatchAt(0);
    final start = match.fillBefore(fragment)!.append(fragment);
    fragment = start.append(
      match.matchFragment(start)!.fillBefore(Fragment.empty, true)!,
    );
  }
  return fragment;
}

void replaceRangeWith(Transform tr, int from, int to, Node node) {
  if (!node.isInline &&
      from == to &&
      tr.doc.resolve(from).parent.content.size != 0) {
    final point = insertPoint(tr.doc, from, node.type);
    if (point != null) {
      from = to = point;
    }
  }
  tr.replaceRange(from, to, Slice(Fragment.from(node), 0, 0));
}

void deleteRange(Transform tr, int from, int to) {
  var $from = tr.doc.resolve(from);
  var $to = tr.doc.resolve(to);

  // When the deleted range spans from the start of one textblock to the
  // start of another one, move out of the start of both blocks.
  if ($from.parent.isTextblock &&
      $to.parent.isTextblock &&
      $from.start() != $to.start() &&
      $from.parentOffset == 0 &&
      $to.parentOffset == 0) {
    final shared = $from.sharedDepth(to);
    var isolated = false;
    for (var d = $from.depth; d > shared; d--) {
      if ($from.node(d).type.spec.isolating) {
        isolated = true;
      }
    }
    for (var d = $to.depth; d > shared; d--) {
      if ($to.node(d).type.spec.isolating) {
        isolated = true;
      }
    }
    if (!isolated) {
      for (var d = $from.depth; d > 0 && from == $from.start(d); d--) {
        from = $from.before(d);
      }
      for (var d = $to.depth; d > 0 && to == $to.start(d); d--) {
        to = $to.before(d);
      }
      $from = tr.doc.resolve(from);
      $to = tr.doc.resolve(to);
    }
  }

  final covered = _coveredDepths($from, $to);
  for (var i = 0; i < covered.length; i++) {
    final depth = covered[i];
    final last = i == covered.length - 1;
    if ((last && depth == 0) || $from.node(depth).type.contentMatch.validEnd) {
      tr.delete($from.start(depth), $to.end(depth));
      return;
    }
    if (depth > 0 &&
        (last ||
            $from
                .node(depth - 1)
                .canReplace(
                  $from.index(depth - 1),
                  $to.indexAfter(depth - 1),
                ))) {
      tr.delete($from.before(depth), $to.after(depth));
      return;
    }
  }
  for (var d = 1; d <= $from.depth && d <= $to.depth; d++) {
    if (from - $from.start(d) == $from.depth - d &&
        to > $from.end(d) &&
        $to.end(d) - to != $to.depth - d &&
        $from.start(d - 1) == $to.start(d - 1) &&
        $from.node(d - 1).canReplace($from.index(d - 1), $to.index(d - 1))) {
      tr.delete($from.before(d), to);
      return;
    }
  }
  tr.delete(from, to);
}

// Returns an array of all depths for which $from - $to spans the whole
// content of the nodes at that depth.
List<int> _coveredDepths(ResolvedPos $from, ResolvedPos $to) {
  final result = <int>[];
  final minDepth = math.min($from.depth, $to.depth);
  for (var d = minDepth; d >= 0; d--) {
    final start = $from.start(d);
    if (start < $from.pos - ($from.depth - d) ||
        $to.end(d) > $to.pos + ($to.depth - d) ||
        $from.node(d).type.spec.isolating ||
        $to.node(d).type.spec.isolating) {
      break;
    }
    if (start == $to.start(d) ||
        (d == $from.depth &&
            d == $to.depth &&
            $from.parent.inlineContent &&
            $to.parent.inlineContent &&
            d != 0 &&
            $to.start(d - 1) == start - 1)) {
      result.add(d);
    }
  }
  return result;
}
