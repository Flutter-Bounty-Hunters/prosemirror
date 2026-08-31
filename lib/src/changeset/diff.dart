import 'dart:math' as math;
import 'dart:typed_data';

import 'package:prosemirror/src/changeset/change.dart';
import 'package:prosemirror/src/model/fragment.dart';
import 'package:prosemirror/src/model/mark.dart';
import 'package:prosemirror/src/model/node.dart';
import 'package:prosemirror/src/model/schema.dart';

/// A token encoder can be passed when creating a `ChangeSet` in order
/// to influence the way the library runs its diffing algorithm. The
/// encoder determines how document tokens (such as nodes and
/// characters) are encoded and compared.
///
/// Note that both the encoding and the comparison may run a lot, and
/// doing non-trivial work in these functions could impact
/// performance.
abstract interface class TokenEncoder<T> {
  /// Encode a given character, with the given marks applied.
  T encodeCharacter(int char, List<Mark> marks);

  /// Encode the start of a node or, if this is a leaf node, the
  /// entire node.
  T encodeNodeStart(Node node);

  /// Encode the end token for the given node. It is valid to encode
  /// every end token in the same way.
  T encodeNodeEnd(Node node);

  /// Compare the given tokens. Should return true when they count as
  /// equal.
  bool compareTokens(T a, T b);
}

// Caches the per-node-type integer id used by the default encoder. This
// mirrors the TypeScript `type.schema.cached.changeSetIDs` cache without
// adding a slot to `Schema` (option (b): non-invasive Expando).
final Expando<Map<String, int>> _typeIdCache = Expando<Map<String, int>>();

int _typeId(NodeType type) {
  final schema = type.schema;
  final cache = _typeIdCache[schema] ??= <String, int>{};
  return cache[type.name] ??= schema.nodes.keys.toList().indexOf(type.name) + 1;
}

/// The default token encoder, which encodes node open tokens as strings
/// holding the node name, characters as their character code, and node
/// close tokens as negative numbers.
class _DefaultEncoder implements TokenEncoder<Object> {
  const _DefaultEncoder();

  @override
  Object encodeCharacter(int char, List<Mark> marks) => char;

  @override
  Object encodeNodeStart(Node node) => node.type.name;

  @override
  Object encodeNodeEnd(Node node) => -_typeId(node.type);

  @override
  bool compareTokens(Object a, Object b) => a == b;
}

/// The default token encoder instance.
// ignore: constant_identifier_names
const TokenEncoder<Object> DefaultEncoder = _DefaultEncoder();

// Convert the given range of a fragment to tokens.
List<T> _tokens<T>(
  Fragment fragment,
  TokenEncoder<T> encoder,
  int start,
  int end,
  List<T> target,
) {
  var offset = 0;
  for (var index = 0; index < fragment.childCount; index++) {
    final child = fragment.child(index);
    final endOffset = offset + child.nodeSize;
    final from = math.max(offset, start);
    final to = math.min(endOffset, end);
    if (from < to) {
      if (child.isText) {
        for (var position = from; position < to; position++) {
          target.add(
            encoder.encodeCharacter(
              child.text!.codeUnitAt(position - offset),
              child.marks,
            ),
          );
        }
      } else if (child.isLeaf) {
        target.add(encoder.encodeNodeStart(child));
      } else {
        if (from == offset) {
          target.add(encoder.encodeNodeStart(child));
        }
        _tokens(
          child.content,
          encoder,
          math.max(offset + 1, from) - offset - 1,
          math.min(endOffset - 1, to) - offset - 1,
          target,
        );
        if (to == endOffset) {
          target.add(encoder.encodeNodeEnd(child));
        }
      }
    }
    offset = endOffset;
  }
  return target;
}

// The code below will refuse to compute a diff with more than 5000
// insertions or deletions, which takes about 300ms to reach on my
// machine. This is a safeguard against runaway computations.
const int _maxDiffSize = 2500;

// This obscure mess of constants computes the minimum length of an
// unchanged range (not at the start/end of the compared content). The
// idea is to make it higher in bigger replacements, so that you don't
// get a diff soup of coincidentally identical letters when replacing
// a paragraph.
int _minUnchanged(int sizeA, int sizeB) {
  return math.min(15, math.max(2, (math.max(sizeA, sizeB) / 10).floor()));
}

// Mirrors JavaScript's out-of-bounds typed-array read, which yields
// `undefined`. The only out-of-range index reachable here is -1, and every
// comparison of the read value keeps the "not less than" outcome that JS
// produces for `undefined`, which a value of -1 reproduces for the x
// coordinates involved.
int _readFrontier(Int16List frontier, int index) {
  return index >= 0 && index < frontier.length ? frontier[index] : -1;
}

List<Change<Data>> computeDiff<Data>(
  Fragment fragA,
  Fragment fragB,
  Change<Data> range, [
  TokenEncoder<Object?> encoder = DefaultEncoder,
]) {
  // When one side is longer than our max scan distance, the algorithm
  // will never find a diff.
  if (math.max(range.toA - range.fromA, math.max(range.toB, range.fromB)) >
      _maxDiffSize) {
    return [range];
  }
  final tokensA = _tokens<Object?>(
    fragA,
    encoder,
    range.fromA,
    range.toA,
    <Object?>[],
  );
  final tokensB = _tokens<Object?>(
    fragB,
    encoder,
    range.fromB,
    range.toB,
    <Object?>[],
  );
  return _diff(tokensA, tokensB, range, encoder.compareTokens);
}

List<Change<Data>> _diff<Data, T>(
  List<T> tokensA,
  List<T> tokensB,
  Change<Data> range,
  bool Function(T a, T b) compare,
) {
  // Scan from both sides to cheaply eliminate work
  var start = 0;
  var endA = tokensA.length;
  var endB = tokensB.length;
  while (start < tokensA.length &&
      start < tokensB.length &&
      compare(tokensA[start], tokensB[start])) {
    start++;
  }
  if (start == tokensA.length && start == tokensB.length) {
    return [];
  }
  while (endA > start &&
      endB > start &&
      compare(tokensA[endA - 1], tokensB[endB - 1])) {
    endA--;
    endB--;
  }
  // If the result is simple _or_ too big to cheaply compute, return
  // the remaining region as the diff
  if (endA == start || endB == start || (endA == endB && endA == start + 1)) {
    return [range.slice(start, endA, start, endB)];
  }

  // This is an implementation of Myers' diff algorithm
  // See https://neil.fraser.name/writing/diff/myers.pdf and
  // https://blog.jcoglan.com/2017/02/12/the-myers-diff-algorithm-part-1/

  final lenA = endA - start;
  final lenB = endB - start;
  final max = math.min(_maxDiffSize, lenA + lenB);
  final history = <Int16List>[];
  var frontier = Int16List((max + 1) * 2)..fillRange(0, (max + 1) * 2, -1);

  for (var size = 0; size <= max; size++) {
    for (var diag = -size; diag <= size; diag += 2) {
      final next = _readFrontier(frontier, diag + 1 + max);
      final prev = _readFrontier(frontier, diag - 1 + max);
      var x = next < prev ? prev : next + 1;
      var y = x + diag;
      while (x < lenA &&
          y < lenB &&
          compare(tokensA[start + x], tokensB[start + y])) {
        x++;
        y++;
      }
      frontier[diag + max] = x;
      // Found a match
      if (x >= lenA && y >= lenB) {
        // Trace back through the history to build up a set of changed
        // ranges.
        final diff = <Change<Data>>[];
        final minSpan = _minUnchanged(endA - start, endB - start);
        // Used to add steps to a diff one at a time, back to front,
        // merging ones that are less than minSpan tokens apart
        final adder = _DiffAdder<Data>(range, minSpan);

        for (var index = size - 1; index >= 0; index--) {
          final traceNext = _readFrontier(frontier, diag + 1 + max);
          final tracePrev = _readFrontier(frontier, diag - 1 + max);
          if (traceNext < tracePrev) {
            // Deletion
            diag--;
            x = tracePrev + start;
            y = x + diag;
            adder.add(x, x, y, y + 1, diff);
          } else {
            // Insertion
            diag++;
            x = traceNext + start;
            y = x + diag;
            adder.add(x, x + 1, y, y, diff);
          }
          frontier = history[index >> 1];
        }
        if (adder.fromA > -1) {
          diff.add(range.slice(adder.fromA, adder.toA, adder.fromB, adder.toB));
        }
        return diff.reversed.toList();
      }
    }
    // Since only either odd or even diagonals are read from each
    // frontier, we only copy them every other iteration.
    if (size % 2 == 0) {
      history.add(Int16List.fromList(frontier));
    }
  }
  // The loop exited, meaning the maximum amount of work was done.
  // Just return a change spanning the entire range.
  return [range];
}

// Accumulates diff steps back-to-front, merging ones that are less than
// `minSpan` tokens apart. Hoisted from the nested `add` closure in the
// TypeScript source so it is not a method-within-a-method.
class _DiffAdder<Data> {
  _DiffAdder(this.range, this.minSpan);

  final Change<Data> range;
  final int minSpan;

  int fromA = -1;
  int toA = -1;
  int fromB = -1;
  int toB = -1;

  void add(
    int newFromA,
    int newToA,
    int newFromB,
    int newToB,
    List<Change<Data>> diff,
  ) {
    if (fromA > -1 && fromA < newToA + minSpan) {
      fromA = newFromA;
      fromB = newFromB;
    } else {
      if (fromA > -1) {
        diff.add(range.slice(fromA, toA, fromB, toB));
      }
      fromA = newFromA;
      toA = newToA;
      fromB = newFromB;
      toB = newToB;
    }
  }
}
