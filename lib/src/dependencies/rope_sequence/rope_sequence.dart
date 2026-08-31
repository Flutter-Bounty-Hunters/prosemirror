import 'dart:math' as math;

/// A persistent (immutable) sequence, represented as a mostly-balanced tree of
/// leaf and append nodes.
///
/// This is a Dart port of the JavaScript `rope-sequence` package. Every
/// operation returns a new [RopeSequence] (or, when it is a no-op, the receiver
/// or the shared [empty] instance) and leaves the original untouched.
abstract class RopeSequence<T> {
  const RopeSequence();

  /// The shared empty rope. Every no-op operation returns this same instance so
  /// that identity checks remain meaningful.
  static final RopeSequence empty = _Leaf<Never>(<Never>[]);

  /// Builds a rope from [value].
  ///
  /// The list is wrapped in a leaf carrying [value]'s element type, so
  /// `RopeSequence.from([1, 2, 3])` produces a `RopeSequence<int>`. An empty
  /// list produces an empty (length zero) leaf of the inferred type; the shared
  /// [empty] singleton is reserved for no-op results such as `slice(0, 0)`.
  static RopeSequence<T> from<T>(List<T> value) {
    return _Leaf<T>(value);
  }

  /// Coerces [value] (a [List] or an existing [RopeSequence]) into a rope.
  ///
  /// - If [value] is already a [RopeSequence], it is returned unchanged.
  /// - If [value] is a non-empty [List], it is wrapped in a leaf.
  /// - Otherwise the shared [empty] rope is returned.
  static RopeSequence<T> _fromObject<T>(Object value) {
    if (value is RopeSequence<T>) {
      return value;
    }
    if (value is List<T> && value.isNotEmpty) {
      return _Leaf<T>(value);
    }
    return empty as RopeSequence<T>;
  }

  /// The number of elements in this rope.
  int get length;

  /// Returns a rope with [other] (a [List] or [RopeSequence]) appended.
  RopeSequence<T> append(Object other) {
    final otherRope = _fromObject<T>(other);
    if (otherRope.length == 0) {
      return this;
    }
    if (length == 0) {
      return otherRope;
    }
    if (otherRope.length < _goodLeafSize) {
      final combined = _leafAppend(otherRope);
      if (combined != null) {
        return combined;
      }
    }
    if (length < _goodLeafSize) {
      final combined = otherRope._leafPrepend(this);
      if (combined != null) {
        return combined;
      }
    }
    return _appendInner(otherRope);
  }

  /// Returns a rope with [other] (a [List] or [RopeSequence]) prepended.
  RopeSequence<T> prepend(Object other) {
    final otherRope = _fromObject<T>(other);
    if (otherRope.length == 0) {
      return this;
    }
    return otherRope.append(this);
  }

  /// Returns the sub-range of this rope between [from] (inclusive) and [to]
  /// (exclusive). When [to] is omitted it defaults to [length]. An empty range
  /// returns the shared [empty] rope.
  RopeSequence<T> slice([int from = 0, int? to]) {
    final resolvedTo = to ?? length;
    if (from >= resolvedTo) {
      return empty as RopeSequence<T>;
    }
    return _sliceInner(math.max(0, from), math.min(length, resolvedTo));
  }

  /// Returns the element at [index], or `null` when [index] is out of range.
  T? get(int index) {
    if (index < 0 || index >= length) {
      return null;
    }
    return _getInner(index);
  }

  /// Calls [callback] for each element between [from] and [to].
  ///
  /// When [to] is omitted it defaults to [length]. If [from] is greater than
  /// [to] the elements are visited in reverse. Returning `false` from [callback]
  /// stops the iteration immediately.
  void forEach(
    Object? Function(T element, int index) callback, [
    int from = 0,
    int? to,
  ]) {
    final resolvedTo = to ?? length;
    if (from <= resolvedTo) {
      _forEachInner(callback, from, resolvedTo, 0);
    } else {
      _forEachInvertedInner(callback, from, resolvedTo, 0);
    }
  }

  /// Maps every element between [from] and [to] through [callback], collecting
  /// the results into a new list.
  List<U> map<U>(
    U Function(T element, int index) callback, [
    int from = 0,
    int? to,
  ]) {
    final result = <U>[];
    forEach(
      (element, index) {
        result.add(callback(element, index));
        return null;
      },
      from,
      to,
    );
    return result;
  }

  /// The height of this node within the tree.
  int get _depth;

  /// The default append: wrap the two nodes in a new append node.
  RopeSequence<T> _appendInner(RopeSequence<T> other) {
    return _Append<T>(this, other);
  }

  /// Returns a flat list of every element in this node.
  List<T> _flatten();

  /// Returns the element at [index], assuming [index] is in range.
  T _getInner(int index);

  /// Returns the sub-range of this node, assuming [from] and [to] are clamped.
  RopeSequence<T> _sliceInner(int from, int to);

  /// Walks elements forward. Returns `false` when [callback] aborted.
  bool _forEachInner(
    Object? Function(T element, int index) callback,
    int from,
    int to,
    int start,
  );

  /// Walks elements in reverse. Returns `false` when [callback] aborted.
  bool _forEachInvertedInner(
    Object? Function(T element, int index) callback,
    int from,
    int to,
    int start,
  );

  /// Attempts to merge [other] onto the end of this node into a single leaf,
  /// returning `null` when the combined size would exceed [_goodLeafSize].
  RopeSequence<T>? _leafAppend(RopeSequence<T> other);

  /// Attempts to merge [other] onto the front of this node into a single leaf,
  /// returning `null` when the combined size would exceed [_goodLeafSize].
  RopeSequence<T>? _leafPrepend(RopeSequence<T> other);
}

const _goodLeafSize = 200;

/// A leaf node that stores its elements directly in a list.
class _Leaf<T> extends RopeSequence<T> {
  _Leaf(this.values);

  final List<T> values;

  @override
  int get length => values.length;

  @override
  int get _depth => 0;

  @override
  List<T> _flatten() {
    return values;
  }

  @override
  T _getInner(int index) {
    return values[index];
  }

  @override
  RopeSequence<T> _sliceInner(int from, int to) {
    if (from == 0 && to == length) {
      return this;
    }
    return _Leaf<T>(values.sublist(from, to));
  }

  @override
  bool _forEachInner(
    Object? Function(T element, int index) callback,
    int from,
    int to,
    int start,
  ) {
    for (var index = from; index < to; index++) {
      if (callback(values[index], start + index) == false) {
        return false;
      }
    }
    return true;
  }

  @override
  bool _forEachInvertedInner(
    Object? Function(T element, int index) callback,
    int from,
    int to,
    int start,
  ) {
    for (var index = from - 1; index >= to; index--) {
      if (callback(values[index], start + index) == false) {
        return false;
      }
    }
    return true;
  }

  @override
  RopeSequence<T>? _leafAppend(RopeSequence<T> other) {
    if (length + other.length <= _goodLeafSize) {
      return _Leaf<T>([...values, ...other._flatten()]);
    }
    return null;
  }

  @override
  RopeSequence<T>? _leafPrepend(RopeSequence<T> other) {
    if (length + other.length <= _goodLeafSize) {
      return _Leaf<T>([...other._flatten(), ...values]);
    }
    return null;
  }
}

/// An internal node that concatenates a [left] and [right] child.
class _Append<T> extends RopeSequence<T> {
  _Append(this.left, this.right)
    : length = left.length + right.length,
      _depth = math.max(left._depth, right._depth) + 1;

  final RopeSequence<T> left;
  final RopeSequence<T> right;

  @override
  final int length;

  @override
  final int _depth;

  @override
  List<T> _flatten() {
    return [...left._flatten(), ...right._flatten()];
  }

  @override
  T _getInner(int index) {
    return index < left.length
        ? left.get(index) as T
        : right.get(index - left.length) as T;
  }

  @override
  RopeSequence<T> _sliceInner(int from, int to) {
    if (from == 0 && to == length) {
      return this;
    }
    final leftLength = left.length;
    if (to <= leftLength) {
      return left.slice(from, to);
    }
    if (from >= leftLength) {
      return right.slice(from - leftLength, to - leftLength);
    }
    return left.slice(from, leftLength).append(right.slice(0, to - leftLength));
  }

  @override
  bool _forEachInner(
    Object? Function(T element, int index) callback,
    int from,
    int to,
    int start,
  ) {
    final leftLength = left.length;
    if (from < leftLength &&
        left._forEachInner(callback, from, math.min(to, leftLength), start) ==
            false) {
      return false;
    }
    if (to > leftLength &&
        right._forEachInner(
              callback,
              math.max(from - leftLength, 0),
              math.min(length, to) - leftLength,
              start + leftLength,
            ) ==
            false) {
      return false;
    }
    return true;
  }

  @override
  bool _forEachInvertedInner(
    Object? Function(T element, int index) callback,
    int from,
    int to,
    int start,
  ) {
    final leftLength = left.length;
    if (from > leftLength &&
        right._forEachInvertedInner(
              callback,
              from - leftLength,
              math.max(to, leftLength) - leftLength,
              start + leftLength,
            ) ==
            false) {
      return false;
    }
    if (to < leftLength &&
        left._forEachInvertedInner(
              callback,
              math.min(from, leftLength),
              to,
              start,
            ) ==
            false) {
      return false;
    }
    return true;
  }

  @override
  RopeSequence<T>? _leafAppend(RopeSequence<T> other) {
    final inner = right._leafAppend(other);
    if (inner != null) {
      return _Append<T>(left, inner);
    }
    return null;
  }

  @override
  RopeSequence<T>? _leafPrepend(RopeSequence<T> other) {
    final inner = left._leafPrepend(other);
    if (inner != null) {
      return _Append<T>(inner, right);
    }
    return null;
  }

  @override
  RopeSequence<T> _appendInner(RopeSequence<T> other) {
    if (left._depth >= math.max(right._depth, other._depth) + 1) {
      return _Append<T>(left, _Append<T>(right, other));
    }
    return _Append<T>(this, other);
  }
}
