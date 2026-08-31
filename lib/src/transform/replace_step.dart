import 'dart:math' as math;

import 'package:prosemirror/src/model/node.dart';
import 'package:prosemirror/src/model/replace.dart';
import 'package:prosemirror/src/model/schema.dart';

import 'package:prosemirror/src/transform/step.dart';
import 'package:prosemirror/src/transform/map.dart';

/// Replace a part of the document with a slice of new content.
class ReplaceStep extends Step {
  /// The given `slice` should fit the 'gap' between `from` and
  /// `to`—the depths must line up, and the surrounding nodes must be
  /// able to be joined with the open sides of the slice. When
  /// `structure` is true, the step will fail if the content between
  /// from and to is not just a sequence of closing and then opening
  /// tokens (this is to guard against rebased replace steps
  /// overwriting something they weren't supposed to).
  ReplaceStep(this.from, this.to, this.slice, [this.structure = false]);

  /// The start position of the replaced range.
  final int from;

  /// The end position of the replaced range.
  final int to;

  /// The slice to insert.
  final Slice slice;

  /// @internal
  final bool structure;

  @override
  StepResult apply(Node doc) {
    if (structure && _contentBetween(doc, from, to)) {
      return StepResult.fail("Structure replace would overwrite content");
    }
    return StepResult.fromReplace(doc, from, to, slice);
  }

  @override
  StepMap getMap() {
    return StepMap([from, to - from, slice.size]);
  }

  @override
  Step invert(Node doc) {
    return ReplaceStep(from, from + slice.size, doc.slice(from, to));
  }

  @override
  Step? map(Mappable mapping) {
    final to = mapping.mapResult(this.to, -1);
    final from = this.from == this.to && ReplaceStep.mapBias < 0
        ? to
        : mapping.mapResult(this.from, 1);
    if (from.deletedAcross && to.deletedAcross) {
      return null;
    }
    return ReplaceStep(from.pos, math.max(from.pos, to.pos), slice, structure);
  }

  @override
  Step? merge(Step other) {
    if (other is! ReplaceStep || other.structure || structure) {
      return null;
    }

    if (from + slice.size == other.from &&
        slice.openEnd == 0 &&
        other.slice.openStart == 0) {
      final slice = this.slice.size + other.slice.size == 0
          ? Slice.empty
          : Slice(
              this.slice.content.append(other.slice.content),
              this.slice.openStart,
              other.slice.openEnd,
            );
      return ReplaceStep(from, to + (other.to - other.from), slice, structure);
    } else if (other.to == from &&
        slice.openStart == 0 &&
        other.slice.openEnd == 0) {
      final slice = this.slice.size + other.slice.size == 0
          ? Slice.empty
          : Slice(
              other.slice.content.append(this.slice.content),
              other.slice.openStart,
              this.slice.openEnd,
            );
      return ReplaceStep(other.from, to, slice, structure);
    } else {
      return null;
    }
  }

  @override
  Object? toJSON() {
    final json = <String, Object?>{
      "stepType": "replace",
      "from": from,
      "to": to,
    };
    if (slice.size != 0) {
      json["slice"] = slice.toJSON();
    }
    if (structure) {
      json["structure"] = true;
    }
    return json;
  }

  /// @internal
  static Step fromJSON(Schema schema, Object? json) {
    final map = json as Map;
    if (map["from"] is! int || map["to"] is! int) {
      throw RangeError("Invalid input for ReplaceStep.fromJSON");
    }
    return ReplaceStep(
      map["from"] as int,
      map["to"] as int,
      Slice.fromJSON(schema, map["slice"]),
      map["structure"] == true,
    );
  }

  /// By default, for backwards compatibility, an inserting step mapped
  /// over an insertion at that same position will move after the
  /// inserted content. Set this to -1 to make such mapping keep the
  /// step before the insertion instead.
  static int mapBias = 1;
}

/// Replace a part of the document with a slice of content, but
/// preserve a range of the replaced content by moving it into the
/// slice.
class ReplaceAroundStep extends Step {
  /// Create a replace-around step with the given range and gap.
  /// `insert` should be the point in the slice into which the content
  /// of the gap should be moved. `structure` has the same meaning as
  /// it has in the [ReplaceStep] class.
  ReplaceAroundStep(
    this.from,
    this.to,
    this.gapFrom,
    this.gapTo,
    this.slice,
    this.insert, [
    this.structure = false,
  ]);

  /// The start position of the replaced range.
  final int from;

  /// The end position of the replaced range.
  final int to;

  /// The start of preserved range.
  final int gapFrom;

  /// The end of preserved range.
  final int gapTo;

  /// The slice to insert.
  final Slice slice;

  /// The position in the slice where the preserved range should be
  /// inserted.
  final int insert;

  /// @internal
  final bool structure;

  @override
  StepResult apply(Node doc) {
    if (structure &&
        (_contentBetween(doc, from, gapFrom) ||
            _contentBetween(doc, gapTo, to))) {
      return StepResult.fail("Structure gap-replace would overwrite content");
    }

    final gap = doc.slice(gapFrom, gapTo);
    if (gap.openStart != 0 || gap.openEnd != 0) {
      return StepResult.fail("Gap is not a flat range");
    }
    final inserted = slice.insertAt(insert, gap.content);
    if (inserted == null) {
      return StepResult.fail("Content does not fit in gap");
    }
    return StepResult.fromReplace(doc, from, to, inserted);
  }

  @override
  StepMap getMap() {
    return StepMap([
      from,
      gapFrom - from,
      insert,
      gapTo,
      to - gapTo,
      slice.size - insert,
    ]);
  }

  @override
  Step invert(Node doc) {
    final gap = gapTo - gapFrom;
    return ReplaceAroundStep(
      from,
      from + slice.size + gap,
      from + insert,
      from + insert + gap,
      doc.slice(from, to).removeBetween(gapFrom - from, gapTo - from),
      gapFrom - from,
      structure,
    );
  }

  @override
  Step? map(Mappable mapping) {
    final from = mapping.mapResult(this.from, 1);
    final to = mapping.mapResult(this.to, -1);
    final gapFrom = this.from == this.gapFrom
        ? from.pos
        : mapping.map(this.gapFrom, -1);
    final gapTo = this.to == this.gapTo ? to.pos : mapping.map(this.gapTo, 1);
    if ((from.deletedAcross && to.deletedAcross) ||
        gapFrom < from.pos ||
        gapTo > to.pos) {
      return null;
    }
    return ReplaceAroundStep(
      from.pos,
      to.pos,
      gapFrom,
      gapTo,
      slice,
      insert,
      structure,
    );
  }

  @override
  Object? toJSON() {
    final json = <String, Object?>{
      "stepType": "replaceAround",
      "from": from,
      "to": to,
      "gapFrom": gapFrom,
      "gapTo": gapTo,
      "insert": insert,
    };
    if (slice.size != 0) {
      json["slice"] = slice.toJSON();
    }
    if (structure) {
      json["structure"] = true;
    }
    return json;
  }

  /// @internal
  static Step fromJSON(Schema schema, Object? json) {
    final map = json as Map;
    if (map["from"] is! int ||
        map["to"] is! int ||
        map["gapFrom"] is! int ||
        map["gapTo"] is! int ||
        map["insert"] is! int) {
      throw RangeError("Invalid input for ReplaceAroundStep.fromJSON");
    }
    return ReplaceAroundStep(
      map["from"] as int,
      map["to"] as int,
      map["gapFrom"] as int,
      map["gapTo"] as int,
      Slice.fromJSON(schema, map["slice"]),
      map["insert"] as int,
      map["structure"] == true,
    );
  }
}

bool _contentBetween(Node doc, int from, int to) {
  final $from = doc.resolve(from);
  var distance = to - from;
  var depth = $from.depth;
  while (distance > 0 &&
      depth > 0 &&
      $from.indexAfter(depth) == $from.node(depth).childCount) {
    depth--;
    distance--;
  }
  if (distance > 0) {
    var next = $from.node(depth).maybeChild($from.indexAfter(depth));
    while (distance > 0) {
      if (next == null || next.isLeaf) {
        return true;
      }
      next = next.firstChild;
      distance--;
    }
  }
  return false;
}
