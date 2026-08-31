import 'dart:math' as math;

import 'package:prosemirror/src/changeset/change.dart';
import 'package:prosemirror/src/changeset/diff.dart';
import 'package:prosemirror/src/model/fragment.dart';
import 'package:prosemirror/src/model/node.dart';
import 'package:prosemirror/src/transform/map.dart';

/// The sentinel used in place of the TypeScript `2e8` "very large position".
const int _veryLarge = 200000000;

/// Configuration for a [ChangeSet].
class ChangeSetConfig<Data> {
  ChangeSetConfig({
    required this.doc,
    required this.combine,
    required this.encoder,
  });

  final Node doc;
  final Data? Function(Data dataA, Data dataB) combine;
  final TokenEncoder<Object?> encoder;
}

/// A change set tracks the changes to a document from a given point
/// in the past. It condenses a number of step maps down to a flat
/// sequence of replacements, and simplifies replacments that
/// partially undo themselves by comparing their content.
class ChangeSet<Data> {
  /// @internal
  ChangeSet(this.config, this.changes);

  /// @internal
  final ChangeSetConfig<Data> config;

  /// Replaced regions.
  final List<Change<Data>> changes;

  /// Computes a new changeset by adding the given step maps and
  /// metadata (either as an array, per-map, or as a single value to be
  /// associated with all maps) to the current set. Will not mutate the
  /// old set.
  ///
  /// Note that due to simplification that happens after each add,
  /// incrementally adding steps might create a different final set
  /// than adding all those changes at once, since different document
  /// tokens might be matched during simplification depending on the
  /// boundaries of the current changed ranges.
  ChangeSet<Data> addSteps(Node newDoc, List<StepMap> maps, Object? data) {
    // This works by inspecting the position maps for the changes,
    // which indicate what parts of the document were replaced by new
    // content, and the size of that new content. It uses these to
    // build up Change objects.
    //
    // These change objects are put in sets and merged together using
    // Change.merge, giving us the changes created by the new steps.
    // Those changes can then be merged with the existing set of
    // changes.
    //
    // For each change that was touched by the new steps, we recompute
    // a diff to try to minimize the change by dropping matching
    // pieces of the old and new document from the change.

    final stepChanges = <Change<Data>>[];
    // Add spans for new steps.
    for (var index = 0; index < maps.length; index++) {
      final entryData = data is List ? data[index] as Data : data as Data;
      var offset = 0;
      maps[index].forEach((fromA, toA, fromB, toB) {
        stepChanges.add(
          Change<Data>(
            fromA + offset,
            toA + offset,
            fromB,
            toB,
            fromA == toA
                ? Span.none<Data>()
                : [Span<Data>(toA - fromA, entryData)],
            fromB == toB
                ? Span.none<Data>()
                : [Span<Data>(toB - fromB, entryData)],
          ),
        );
        offset = (toB - fromB) - (toA - fromA);
      });
    }
    if (stepChanges.isEmpty) {
      return this;
    }

    final newChanges = _mergeAll(stepChanges, config.combine);
    final changes = Change.merge(this.changes, newChanges, config.combine);
    var updated = changes;

    // Minimize changes when possible
    for (var index = 0; index < updated.length; index++) {
      final change = updated[index];
      if (change.fromA == change.toA ||
          change.fromB == change.toB ||
          // Only look at changes that touch newly added changed ranges
          !newChanges.any(
            (range) => range.toB > change.fromB && range.fromB < change.toB,
          )) {
        continue;
      }
      final diff = _computeDiff(
        config.doc.content,
        newDoc.content,
        change,
        config.encoder,
      );

      // Fast path: If they are completely different, don't do anything
      if (diff.length == 1 &&
          diff[0].fromB == 0 &&
          diff[0].toB == change.toB - change.fromB) {
        continue;
      }

      if (identical(updated, changes)) {
        updated = List<Change<Data>>.of(changes);
      }
      if (diff.length == 1) {
        updated[index] = diff[0];
      } else {
        updated.replaceRange(index, index + 1, diff);
        index += diff.length - 1;
      }
    }

    return ChangeSet<Data>(config, updated);
  }

  /// The starting document of the change set.
  Node get startDoc => config.doc;

  /// Map the span's data values in the given set through a function
  /// and construct a new set with the resulting data.
  ChangeSet<Data> map(Data Function(Span<Data> range) f) {
    return ChangeSet<Data>(config, [
      for (final change in changes)
        Change<Data>(
          change.fromA,
          change.toA,
          change.fromB,
          change.toB,
          change.deleted.map((span) => _mapSpan(span, f)).toList(),
          change.inserted.map((span) => _mapSpan(span, f)).toList(),
        ),
    ]);
  }

  /// Compare two changesets and return the range in which they are
  /// changed, if any. If the document changed between the maps, pass
  /// the maps for the steps that changed it as second argument, and
  /// make sure the method is called on the old set and passed the new
  /// set. The returned positions will be in new document coordinates.
  ({int from, int to})? changedRange(
    ChangeSet<Object?> other, [
    List<StepMap>? maps,
  ]) {
    if (identical(other, this)) {
      return null;
    }
    final touched = maps != null ? _touchedRange(maps) : null;
    final moved = touched != null
        ? (touched.toB - touched.fromB) - (touched.toA - touched.fromA)
        : 0;

    final accumulator = _ChangedRangeAccumulator(
      from: touched != null ? touched.fromB : _veryLarge,
      to: touched != null ? touched.toB : -_veryLarge,
    );

    final rangesA = changes;
    final rangesB = other.changes;
    var indexA = 0;
    var indexB = 0;
    while (indexA < rangesA.length && indexB < rangesB.length) {
      final rangeA = rangesA[indexA];
      final rangeB = rangesB[indexB];
      if (_sameRanges(rangeA, rangeB, touched, moved)) {
        indexA++;
        indexB++;
      } else if (_mapPosition(rangeA.fromB, touched, moved) >= rangeB.fromB) {
        accumulator.add(rangeB.fromB, rangeB.toB);
        indexB++;
      } else {
        accumulator.add(
          _mapPosition(rangeA.fromB, touched, moved),
          _mapPosition(rangeA.toB, touched, moved),
        );
        indexA++;
      }
    }

    return accumulator.from <= accumulator.to
        ? (from: accumulator.from, to: accumulator.to)
        : null;
  }

  /// Create a changeset with the given base object and configuration.
  ///
  /// The `combine` function is used to compare and combine metadata—it
  /// should return null when metadata isn't compatible, and a combined
  /// version for a merged range when it is.
  ///
  /// When given, a token encoder determines how document tokens are
  /// serialized and compared when diffing the content produced by
  /// changes. The default is to just compare nodes by name and text
  /// by character, ignoring marks and attributes.
  ///
  /// To serialize a change set, you can store its document and
  /// change array as JSON, and then pass the deserialized (via
  /// [Change.fromJSON]) set of changes as fourth argument to `create`
  /// to recreate the set.
  static ChangeSet<Data> create<Data>(
    Node doc, [
    Data? Function(Data dataA, Data dataB)? combine,
    TokenEncoder<Object?>? tokenEncoder,
    List<Change<Data>> changes = const [],
  ]) {
    return ChangeSet<Data>(
      ChangeSetConfig<Data>(
        combine: combine ?? _defaultCombine<Data>,
        doc: doc,
        encoder: tokenEncoder ?? DefaultEncoder,
      ),
      changes,
    );
  }

  /// Exported for testing @internal
  static List<Change<Data>> computeDiff<Data>(
    Fragment fragA,
    Fragment fragB,
    Change<Data> range, [
    TokenEncoder<Object?> encoder = DefaultEncoder,
  ]) {
    return _computeDiff(fragA, fragB, range, encoder);
  }
}

Data? _defaultCombine<Data>(Data a, Data b) {
  return identical(a, b) || a == b ? a : null;
}

// Delegate to the top-level `computeDiff` exported from diff.dart. This
// keeps calls inside the class from resolving to the static member of the
// same name.
List<Change<Data>> _computeDiff<Data>(
  Fragment fragA,
  Fragment fragB,
  Change<Data> range,
  TokenEncoder<Object?> encoder,
) {
  return computeDiff(fragA, fragB, range, encoder);
}

// Divide-and-conquer approach to merging a series of ranges.
List<Change<Data>> _mergeAll<Data>(
  List<Change<Data>> ranges,
  Data? Function(Data dataA, Data dataB) combine, [
  int start = 0,
  int? endArgument,
]) {
  final end = endArgument ?? ranges.length;
  if (end == start + 1) {
    return [ranges[start]];
  }
  final mid = (start + end) >> 1;
  return Change.merge(
    _mergeAll(ranges, combine, start, mid),
    _mergeAll(ranges, combine, mid, end),
    combine,
  );
}

({int from, int to})? _endRange(List<StepMap> maps) {
  var from = _veryLarge;
  var to = -_veryLarge;
  for (var index = 0; index < maps.length; index++) {
    final map = maps[index];
    if (from != _veryLarge) {
      from = map.map(from, -1);
      to = map.map(to, 1);
    }
    map.forEach((oldStart, oldEnd, newStart, newEnd) {
      from = math.min(from, newStart);
      to = math.max(to, newEnd);
    });
  }
  return from == _veryLarge ? null : (from: from, to: to);
}

({int fromA, int toA, int fromB, int toB})? _touchedRange(List<StepMap> maps) {
  final rangeB = _endRange(maps);
  if (rangeB == null) {
    return null;
  }
  final rangeA = _endRange(
    maps.map((map) => map.invert()).toList().reversed.toList(),
  )!;
  return (
    fromA: rangeA.from,
    toA: rangeA.to,
    fromB: rangeB.from,
    toB: rangeB.to,
  );
}

int _mapPosition(
  int position,
  ({int fromA, int toA, int fromB, int toB})? touched,
  int moved,
) {
  return touched == null || position <= touched.fromA
      ? position
      : position + moved;
}

class _ChangedRangeAccumulator {
  _ChangedRangeAccumulator({required this.from, required this.to});

  int from;
  int to;

  void add(int start, [int? end]) {
    final endPosition = end ?? start;
    from = math.min(start, from);
    to = math.max(endPosition, to);
  }
}

Span<Data> _mapSpan<Data>(Span<Data> span, Data Function(Span<Data>) f) {
  final newData = f(span);
  return identical(newData, span.data)
      ? span
      : Span<Data>(span.length, newData);
}

bool _sameRanges<Data>(
  Change<Data> a,
  Change<Object?> b,
  ({int fromA, int toA, int fromB, int toB})? touched,
  int moved,
) {
  return _mapPosition(a.fromB, touched, moved) == b.fromB &&
      _mapPosition(a.toB, touched, moved) == b.toB &&
      _sameSpans(a.deleted, b.deleted) &&
      _sameSpans(a.inserted, b.inserted);
}

bool _sameSpans<Data>(List<Span<Data>> a, List<Span<Object?>> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var index = 0; index < a.length; index++) {
    if (a[index].length != b[index].length ||
        !identical(a[index].data, b[index].data)) {
      return false;
    }
  }
  return true;
}
