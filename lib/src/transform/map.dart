/// There are several things that positions can be mapped through.
/// Such objects conform to this interface.
abstract class Mappable {
  /// Map a position through this object. When given, `assoc` (should
  /// be -1 or 1, defaults to 1) determines with which side the
  /// position is associated, which determines in which direction to
  /// move when a chunk of content is inserted at the mapped position.
  int map(int pos, [int assoc = 1]);

  /// Map a position, and return an object containing additional
  /// information about the mapping. The result's `deleted` field tells
  /// you whether the position was deleted (completely enclosed in a
  /// replaced range) during the mapping. When content on only one side
  /// is deleted, the position itself is only considered deleted when
  /// `assoc` points in the direction of the deleted content.
  MapResult mapResult(int pos, [int assoc = 1]);
}

// Recovery values encode a range index and an offset. They are
// represented as numbers, because tons of them will be created when
// mapping, for example, a large number of decorations. The number's
// lower 16 bits provide the index, the remaining bits the offset.
const int _lower16 = 0xffff;
const int _factor16 = 65536;

int _makeRecover(int index, int offset) => index + offset * _factor16;
int _recoverIndex(int value) => value & _lower16;
int _recoverOffset(int value) => (value - (value & _lower16)) ~/ _factor16;

const int _delBefore = 1;
const int _delAfter = 2;
const int _delAcross = 4;
const int _delSide = 8;

/// An object representing a mapped position with extra information.
class MapResult {
  /// @internal
  MapResult(this.pos, this.delInfo, this.recover);

  /// The mapped version of the position.
  final int pos;

  /// @internal
  final int delInfo;

  /// @internal
  final int? recover;

  /// Tells you whether the position was deleted, that is, whether the
  /// step removed the token on the side queried (via the `assoc`)
  /// argument from the document.
  bool get deleted => (delInfo & _delSide) > 0;

  /// Tells you whether the token before the mapped position was deleted.
  bool get deletedBefore => (delInfo & (_delBefore | _delAcross)) > 0;

  /// True when the token after the mapped position was deleted.
  bool get deletedAfter => (delInfo & (_delAfter | _delAcross)) > 0;

  /// Tells whether any of the steps mapped through deletes across the
  /// position (including both the token before and after the position).
  bool get deletedAcross => (delInfo & _delAcross) > 0;
}

/// A map describing the deletions and insertions made by a step, which
/// can be used to find the correspondence between positions in the
/// pre-step version of a document and the same position in the
/// post-step version.
class StepMap implements Mappable {
  /// Create a position map. The modifications to the document are
  /// represented as an array of numbers, in which each group of three
  /// represents a modified chunk as `[start, oldSize, newSize]`.
  StepMap(this.ranges, [this.inverted = false]);

  /// @internal
  final List<int> ranges;

  /// @internal
  final bool inverted;

  /// @internal
  int recover(int value) {
    var diff = 0;
    final index = _recoverIndex(value);
    if (!inverted) {
      for (var i = 0; i < index; i++) {
        diff += ranges[i * 3 + 2] - ranges[i * 3 + 1];
      }
    }
    return ranges[index * 3] + diff + _recoverOffset(value);
  }

  @override
  MapResult mapResult(int pos, [int assoc = 1]) {
    return _map(pos, assoc, false) as MapResult;
  }

  @override
  int map(int pos, [int assoc = 1]) {
    return _map(pos, assoc, true) as int;
  }

  /// @internal
  Object _map(int pos, int assoc, bool simple) {
    var diff = 0;
    final oldIndex = inverted ? 2 : 1;
    final newIndex = inverted ? 1 : 2;
    for (var i = 0; i < ranges.length; i += 3) {
      final start = ranges[i] - (inverted ? diff : 0);
      if (start > pos) {
        break;
      }
      final oldSize = ranges[i + oldIndex];
      final newSize = ranges[i + newIndex];
      final end = start + oldSize;
      if (pos <= end) {
        final side = oldSize == 0
            ? assoc
            : pos == start
            ? -1
            : pos == end
            ? 1
            : assoc;
        final result = start + diff + (side < 0 ? 0 : newSize);
        if (simple) {
          return result;
        }
        final int? recover = pos == (assoc < 0 ? start : end)
            ? null
            : _makeRecover(i ~/ 3, pos - start);
        var del = pos == start
            ? _delAfter
            : pos == end
            ? _delBefore
            : _delAcross;
        if (assoc < 0 ? pos != start : pos != end) {
          del |= _delSide;
        }
        return MapResult(result, del, recover);
      }
      diff += newSize - oldSize;
    }
    return simple ? pos + diff : MapResult(pos + diff, 0, null);
  }

  /// @internal
  bool touches(int pos, int recover) {
    var diff = 0;
    final index = _recoverIndex(recover);
    final oldIndex = inverted ? 2 : 1;
    final newIndex = inverted ? 1 : 2;
    for (var i = 0; i < ranges.length; i += 3) {
      final start = ranges[i] - (inverted ? diff : 0);
      if (start > pos) {
        break;
      }
      final oldSize = ranges[i + oldIndex];
      final end = start + oldSize;
      if (pos <= end && i == index * 3) {
        return true;
      }
      diff += ranges[i + newIndex] - oldSize;
    }
    return false;
  }

  /// Calls the given function on each of the changed ranges included in
  /// this map.
  void forEach(
    void Function(int oldStart, int oldEnd, int newStart, int newEnd) callback,
  ) {
    final oldIndex = inverted ? 2 : 1;
    final newIndex = inverted ? 1 : 2;
    for (var i = 0, diff = 0; i < ranges.length; i += 3) {
      final start = ranges[i];
      final oldStart = start - (inverted ? diff : 0);
      final newStart = start + (inverted ? 0 : diff);
      final oldSize = ranges[i + oldIndex];
      final newSize = ranges[i + newIndex];
      callback(oldStart, oldStart + oldSize, newStart, newStart + newSize);
      diff += newSize - oldSize;
    }
  }

  /// Create an inverted version of this map. The result can be used to
  /// map positions in the post-step document to the pre-step document.
  StepMap invert() {
    return StepMap(ranges, !inverted);
  }

  @override
  String toString() {
    return (inverted ? "-" : "") + ranges.toString();
  }

  /// Create a map that moves all positions by offset `distance` (which
  /// may be negative). This can be useful when applying steps meant for
  /// a sub-document to a larger document, or vice-versa.
  static StepMap offset(int distance) {
    return distance == 0
        ? StepMap.empty
        : StepMap(distance < 0 ? [0, -distance, 0] : [0, 0, distance]);
  }

  /// A StepMap that contains no changed ranges.
  static final StepMap empty = StepMap(const <int>[]);
}

/// A mapping represents a pipeline of zero or more [StepMap]s. It has
/// special provisions for losslessly handling mapping positions
/// through a series of steps in which some steps are inverted versions
/// of earlier steps.
class Mapping implements Mappable {
  /// Create a new mapping with the given position maps.
  Mapping([List<StepMap>? maps, this.mirror, this.from = 0, int? to]) {
    _maps = maps ?? <StepMap>[];
    this.to = to ?? (maps != null ? maps.length : 0);
    _ownData = !(maps != null || mirror != null);
  }

  /// @internal
  List<int>? mirror;

  /// The starting position in the `maps` array, used when [map] or
  /// [mapResult] is called.
  int from;

  /// The end position in the `maps` array.
  late int to;

  late List<StepMap> _maps;

  // False if maps/mirror are shared arrays that we shouldn't mutate.
  late bool _ownData;

  /// The step maps in this mapping.
  List<StepMap> get maps => _maps;

  /// Create a mapping that maps only through a part of this one.
  Mapping slice([int from = 0, int? to]) {
    return Mapping(_maps, mirror, from, to ?? maps.length);
  }

  /// Add a step map to the end of this mapping. If `mirrors` is given,
  /// it should be the index of the step map that is the mirror image
  /// of this one.
  void appendMap(StepMap map, [int? mirrors]) {
    if (!_ownData) {
      _maps = List<StepMap>.of(_maps);
      mirror = mirror != null ? List<int>.of(mirror!) : null;
      _ownData = true;
    }
    _maps.add(map);
    to = _maps.length;
    if (mirrors != null) {
      setMirror(_maps.length - 1, mirrors);
    }
  }

  /// Add all the step maps in a given mapping to this one (preserving
  /// mirroring information).
  void appendMapping(Mapping mapping) {
    for (var i = 0, startSize = _maps.length; i < mapping._maps.length; i++) {
      final mirrorIndex = mapping.getMirror(i);
      appendMap(
        mapping._maps[i],
        mirrorIndex != null && mirrorIndex < i ? startSize + mirrorIndex : null,
      );
    }
  }

  /// Finds the offset of the step map that mirrors the map at the given
  /// offset, in this mapping (as per the second argument to
  /// [appendMap]).
  int? getMirror(int index) {
    if (mirror != null) {
      for (var i = 0; i < mirror!.length; i++) {
        if (mirror![i] == index) {
          return mirror![i + (i % 2 != 0 ? -1 : 1)];
        }
      }
    }
    return null;
  }

  /// @internal
  void setMirror(int index, int mirrorIndex) {
    mirror ??= <int>[];
    mirror!.add(index);
    mirror!.add(mirrorIndex);
  }

  /// Append the inverse of the given mapping to this one.
  void appendMappingInverted(Mapping mapping) {
    for (
      var i = mapping.maps.length - 1,
          totalSize = _maps.length + mapping._maps.length;
      i >= 0;
      i--
    ) {
      final mirrorIndex = mapping.getMirror(i);
      appendMap(
        mapping._maps[i].invert(),
        mirrorIndex != null && mirrorIndex > i
            ? totalSize - mirrorIndex - 1
            : null,
      );
    }
  }

  /// Create an inverted version of this mapping.
  Mapping invert() {
    final inverse = Mapping();
    inverse.appendMappingInverted(this);
    return inverse;
  }

  /// Map a position through this mapping.
  @override
  int map(int pos, [int assoc = 1]) {
    if (mirror != null) {
      return _map(pos, assoc, true) as int;
    }
    for (var i = from; i < to; i++) {
      pos = _maps[i].map(pos, assoc);
    }
    return pos;
  }

  /// Map a position through this mapping, returning a mapping result.
  @override
  MapResult mapResult(int pos, [int assoc = 1]) {
    return _map(pos, assoc, false) as MapResult;
  }

  /// @internal
  Object _map(int pos, int assoc, bool simple) {
    var delInfo = 0;

    for (var i = from; i < to; i++) {
      final map = _maps[i];
      final result = map.mapResult(pos, assoc);
      if (result.recover != null) {
        final mirrorIndex = getMirror(i);
        if (mirrorIndex != null && mirrorIndex > i && mirrorIndex < to) {
          i = mirrorIndex;
          pos = _maps[mirrorIndex].recover(result.recover!);
          continue;
        }
      }

      delInfo |= result.delInfo;
      pos = result.pos;
    }

    return simple ? pos : MapResult(pos, delInfo, null);
  }
}
