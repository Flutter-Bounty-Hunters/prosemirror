import 'dart:math' as math;

/// The sentinel used in place of the TypeScript `2e8` "very large position".
const int _veryLarge = 200000000;

/// Stores metadata for a part of a change.
class Span<Data> {
  /// @internal
  Span(this.length, this.data);

  /// The length of this span.
  final int length;

  /// The data associated with this span.
  final Data data;

  /// @internal
  Span<Data> cut(int length) {
    return length == this.length ? this : Span<Data>(length, data);
  }

  /// @internal
  static List<Span<Data>> slice<Data>(
    List<Span<Data>> spans,
    int from,
    int to,
  ) {
    if (from == to) {
      return Span.none<Data>();
    }
    if (from == 0 && to == Span.len(spans)) {
      return spans;
    }
    final result = <Span<Data>>[];
    var offset = 0;
    for (var index = 0; offset < to; index++) {
      final span = spans[index];
      final end = offset + span.length;
      final overlap = math.min<int>(to, end) - math.max<int>(from, offset);
      if (overlap > 0) {
        result.add(span.cut(overlap));
      }
      offset = end;
    }
    return result;
  }

  /// @internal
  static List<Span<Data>> join<Data>(
    List<Span<Data>> a,
    List<Span<Data>> b,
    Data? Function(Data dataA, Data dataB) combine,
  ) {
    if (a.isEmpty) {
      return b;
    }
    if (b.isEmpty) {
      return a;
    }
    final combined = combine(a[a.length - 1].data, b[0].data);
    if (combined == null) {
      return [...a, ...b];
    }
    final result = a.sublist(0, a.length - 1);
    result.add(Span<Data>(a[a.length - 1].length + b[0].length, combined));
    for (var index = 1; index < b.length; index++) {
      result.add(b[index]);
    }
    return result;
  }

  /// @internal
  static int len<Data>(List<Span<Data>> spans) {
    var length = 0;
    for (var index = 0; index < spans.length; index++) {
      length += spans[index].length;
    }
    return length;
  }

  /// @internal
  static List<Span<Data>> none<Data>() => <Span<Data>>[];
}

/// A replaced range with metadata associated with it.
class Change<Data> {
  /// @internal
  Change(
    this.fromA,
    this.toA,
    this.fromB,
    this.toB,
    this.deleted,
    this.inserted,
  );

  /// The start of the range deleted/replaced in the old document.
  final int fromA;

  /// The end of the range in the old document.
  final int toA;

  /// The start of the range inserted in the new document.
  final int fromB;

  /// The end of the range in the new document.
  final int toB;

  /// Data associated with the deleted content. The length of these
  /// spans adds up to `this.toA - this.fromA`.
  final List<Span<Data>> deleted;

  /// Data associated with the inserted content. Length adds up to
  /// `this.toB - this.fromB`.
  final List<Span<Data>> inserted;

  /// @internal
  int get lenA => toA - fromA;

  /// @internal
  int get lenB => toB - fromB;

  /// @internal
  Change<Data> slice(int startA, int endA, int startB, int endB) {
    if (startA == 0 &&
        startB == 0 &&
        endA == toA - fromA &&
        endB == toB - fromB) {
      return this;
    }
    return Change<Data>(
      fromA + startA,
      fromA + endA,
      fromB + startB,
      fromB + endB,
      Span.slice(deleted, startA, endA),
      Span.slice(inserted, startB, endB),
    );
  }

  /// This merges two changesets (the end document of x should be the
  /// start document of y) into a single one spanning the start of x to
  /// the end of y.
  static List<Change<Data>> merge<Data>(
    List<Change<Data>> x,
    List<Change<Data>> y,
    Data? Function(Data dataA, Data dataB) combine,
  ) {
    if (x.isEmpty) {
      return y;
    }
    if (y.isEmpty) {
      return x;
    }

    final result = <Change<Data>>[];
    // Iterate over both sets in parallel, using the middle coordinate
    // system (B in x, A in y) to synchronize.
    var indexX = 0;
    var indexY = 0;
    Change<Data>? currentX = x[0];
    Change<Data>? currentY = y[0];
    for (;;) {
      if (currentX == null && currentY == null) {
        return result;
      } else if (currentX != null &&
          (currentY == null || currentX.toB < currentY.fromA)) {
        // currentX entirely in front of currentY
        final offset = indexY != 0 ? y[indexY - 1].toB - y[indexY - 1].toA : 0;
        result.add(
          offset == 0
              ? currentX
              : Change<Data>(
                  currentX.fromA,
                  currentX.toA,
                  currentX.fromB + offset,
                  currentX.toB + offset,
                  currentX.deleted,
                  currentX.inserted,
                ),
        );
        currentX = indexX++ == x.length ? null : _elementAt(x, indexX);
      } else if (currentY != null &&
          (currentX == null || currentY.toA < currentX.fromB)) {
        // currentY entirely in front of currentX
        final offset = indexX != 0 ? x[indexX - 1].toB - x[indexX - 1].toA : 0;
        result.add(
          offset == 0
              ? currentY
              : Change<Data>(
                  currentY.fromA - offset,
                  currentY.toA - offset,
                  currentY.fromB,
                  currentY.toB,
                  currentY.deleted,
                  currentY.inserted,
                ),
        );
        currentY = indexY++ == y.length ? null : _elementAt(y, indexY);
      } else {
        // Touch, need to merge
        // The rules for merging ranges are that deletions from the
        // old set and insertions from the new are kept. Areas of the
        // middle document covered by a but not by b are insertions
        // from a that need to be added, and areas covered by b but
        // not a are deletions from b that need to be added.
        final nonNullX = currentX!;
        final nonNullY = currentY!;
        var fromA = math.min(
          nonNullX.fromA,
          nonNullY.fromA -
              (indexX != 0 ? x[indexX - 1].toB - x[indexX - 1].toA : 0),
        );
        var toA = fromA;
        var fromB = math.min(
          nonNullY.fromB,
          nonNullX.fromB +
              (indexY != 0 ? y[indexY - 1].toB - y[indexY - 1].toA : 0),
        );
        var toB = fromB;
        var pos = math.min(nonNullX.fromB, nonNullY.fromA);
        var deleted = Span.none<Data>();
        var inserted = Span.none<Data>();

        // Used to prevent appending ins/del range for the same Change twice
        var enteredX = false;
        var enteredY = false;

        // Need to have an inner loop since any number of further
        // ranges might be touching this group
        for (;;) {
          final nextX = currentX == null
              ? _veryLarge
              : pos >= currentX.fromB
              ? currentX.toB
              : currentX.fromB;
          final nextY = currentY == null
              ? _veryLarge
              : pos >= currentY.fromA
              ? currentY.toA
              : currentY.fromA;
          final next = math.min(nextX, nextY);
          final inX = currentX != null && pos >= currentX.fromB;
          final inY = currentY != null && pos >= currentY.fromA;
          if (!inX && !inY) {
            break;
          }
          if (inX && pos == currentX.fromB && !enteredX) {
            deleted = Span.join(deleted, currentX.deleted, combine);
            toA += currentX.lenA;
            enteredX = true;
          }
          if (inX && !inY) {
            inserted = Span.join(
              inserted,
              Span.slice(
                currentX.inserted,
                pos - currentX.fromB,
                next - currentX.fromB,
              ),
              combine,
            );
            toB += next - pos;
          }
          if (inY && pos == currentY.fromA && !enteredY) {
            inserted = Span.join(inserted, currentY.inserted, combine);
            toB += currentY.lenB;
            enteredY = true;
          }
          if (inY && !inX) {
            deleted = Span.join(
              deleted,
              Span.slice(
                currentY.deleted,
                pos - currentY.fromA,
                next - currentY.fromA,
              ),
              combine,
            );
            toA += next - pos;
          }

          if (inX && next == currentX.toB) {
            currentX = indexX++ == x.length ? null : _elementAt(x, indexX);
            enteredX = false;
          }
          if (inY && next == currentY.toA) {
            currentY = indexY++ == y.length ? null : _elementAt(y, indexY);
            enteredY = false;
          }
          pos = next;
        }
        if (fromA < toA || fromB < toB) {
          result.add(Change<Data>(fromA, toA, fromB, toB, deleted, inserted));
        }
      }
    }
  }

  /// Deserialize a change from JSON format.
  static Change<Data> fromJSON<Data>(Map<String, Object?> json) {
    final deleted = (json["deleted"] as List)
        .map((entry) => _spanFromJSON<Data>(entry as Map<String, Object?>))
        .toList();
    final inserted = (json["inserted"] as List)
        .map((entry) => _spanFromJSON<Data>(entry as Map<String, Object?>))
        .toList();
    return Change<Data>(
      json["fromA"] as int,
      json["toA"] as int,
      json["fromB"] as int,
      json["toB"] as int,
      deleted,
      inserted,
    );
  }

  /// Returns a JSON-serializeable object to represent this change.
  Map<String, Object?> toJSON() {
    return <String, Object?>{
      "fromA": fromA,
      "toA": toA,
      "fromB": fromB,
      "toB": toB,
      "deleted": [
        for (final span in deleted)
          <String, Object?>{"length": span.length, "data": span.data},
      ],
      "inserted": [
        for (final span in inserted)
          <String, Object?>{"length": span.length, "data": span.data},
      ],
    };
  }
}

// Mirrors JavaScript's out-of-bounds array access, which yields `undefined`
// (treated as null here) rather than throwing.
Change<Data>? _elementAt<Data>(List<Change<Data>> list, int index) {
  return index >= 0 && index < list.length ? list[index] : null;
}

Span<Data> _spanFromJSON<Data>(Map<String, Object?> json) {
  return Span<Data>(json["length"] as int, json["data"] as Data);
}

/// JSON-serialized form of a change.
typedef ChangeJSON<Data> = Map<String, Object?>;
