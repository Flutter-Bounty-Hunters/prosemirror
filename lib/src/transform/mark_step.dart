import 'dart:math' as math;

import 'package:prosemirror/src/model/model.dart';

import 'step.dart';
import 'map.dart';

Fragment _mapFragment(
  Fragment fragment,
  Node Function(Node child, Node parent, int index) callback,
  Node parent,
) {
  final mapped = <Node>[];
  for (var index = 0; index < fragment.childCount; index++) {
    var child = fragment.child(index);
    if (child.content.size != 0) {
      child = child.copy(_mapFragment(child.content, callback, child));
    }
    if (child.isInline) {
      child = callback(child, parent, index);
    }
    mapped.add(child);
  }
  return Fragment.fromArray(mapped);
}

/// Add a mark to all inline content between two positions.
class AddMarkStep extends Step {
  /// Create a mark step.
  AddMarkStep(this.from, this.to, this.mark);

  /// The start of the marked range.
  final int from;

  /// The end of the marked range.
  final int to;

  /// The mark to add.
  final Mark mark;

  @override
  StepResult apply(Node doc) {
    final oldSlice = doc.slice(from, to);
    final $from = doc.resolve(from);
    final parent = $from.node($from.sharedDepth(to));
    final slice = Slice(
      _mapFragment(oldSlice.content, (node, parent, index) {
        if (!node.isAtom || !parent.type.allowsMarkType(mark.type)) {
          return node;
        }
        return node.mark(mark.addToSet(node.marks));
      }, parent),
      oldSlice.openStart,
      oldSlice.openEnd,
    );
    return StepResult.fromReplace(doc, from, to, slice);
  }

  @override
  Step invert(Node doc) {
    return RemoveMarkStep(from, to, mark);
  }

  @override
  Step? map(Mappable mapping) {
    final from = mapping.mapResult(this.from, 1);
    final to = mapping.mapResult(this.to, -1);
    if (from.deleted && to.deleted || from.pos >= to.pos) {
      return null;
    }
    return AddMarkStep(from.pos, to.pos, mark);
  }

  @override
  Step? merge(Step other) {
    if (other is AddMarkStep &&
        other.mark.eq(mark) &&
        from <= other.to &&
        to >= other.from) {
      return AddMarkStep(
        math.min(from, other.from),
        math.max(to, other.to),
        mark,
      );
    }
    return null;
  }

  @override
  Object? toJSON() {
    return <String, Object?>{
      "stepType": "addMark",
      "mark": mark.toJSON(),
      "from": from,
      "to": to,
    };
  }

  /// @internal
  static Step fromJSON(Schema schema, Object? json) {
    final map = json as Map;
    if (map["from"] is! int || map["to"] is! int) {
      throw RangeError("Invalid input for AddMarkStep.fromJSON");
    }
    return AddMarkStep(
      map["from"] as int,
      map["to"] as int,
      schema.markFromJSON(map["mark"]),
    );
  }
}

/// Remove a mark from all inline content between two positions.
class RemoveMarkStep extends Step {
  /// Create a mark-removing step.
  RemoveMarkStep(this.from, this.to, this.mark);

  /// The start of the unmarked range.
  final int from;

  /// The end of the unmarked range.
  final int to;

  /// The mark to remove.
  final Mark mark;

  @override
  StepResult apply(Node doc) {
    final oldSlice = doc.slice(from, to);
    final slice = Slice(
      _mapFragment(oldSlice.content, (node, parent, index) {
        return node.mark(mark.removeFromSet(node.marks));
      }, doc),
      oldSlice.openStart,
      oldSlice.openEnd,
    );
    return StepResult.fromReplace(doc, from, to, slice);
  }

  @override
  Step invert(Node doc) {
    return AddMarkStep(from, to, mark);
  }

  @override
  Step? map(Mappable mapping) {
    final from = mapping.mapResult(this.from, 1);
    final to = mapping.mapResult(this.to, -1);
    if (from.deleted && to.deleted || from.pos >= to.pos) {
      return null;
    }
    return RemoveMarkStep(from.pos, to.pos, mark);
  }

  @override
  Step? merge(Step other) {
    if (other is RemoveMarkStep &&
        other.mark.eq(mark) &&
        from <= other.to &&
        to >= other.from) {
      return RemoveMarkStep(
        math.min(from, other.from),
        math.max(to, other.to),
        mark,
      );
    }
    return null;
  }

  @override
  Object? toJSON() {
    return <String, Object?>{
      "stepType": "removeMark",
      "mark": mark.toJSON(),
      "from": from,
      "to": to,
    };
  }

  /// @internal
  static Step fromJSON(Schema schema, Object? json) {
    final map = json as Map;
    if (map["from"] is! int || map["to"] is! int) {
      throw RangeError("Invalid input for RemoveMarkStep.fromJSON");
    }
    return RemoveMarkStep(
      map["from"] as int,
      map["to"] as int,
      schema.markFromJSON(map["mark"]),
    );
  }
}

/// Add a mark to a specific node.
class AddNodeMarkStep extends Step {
  /// Create a node mark step.
  AddNodeMarkStep(this.pos, this.mark);

  /// The position of the target node.
  final int pos;

  /// The mark to add.
  final Mark mark;

  @override
  StepResult apply(Node doc) {
    final node = doc.nodeAt(pos);
    if (node == null) {
      return StepResult.fail("No node at mark step's position");
    }
    final updated = node.type.create(
      node.attrs,
      null,
      mark.addToSet(node.marks),
    );
    return StepResult.fromReplace(
      doc,
      pos,
      pos + 1,
      Slice(Fragment.from(updated), 0, node.isLeaf ? 0 : 1),
    );
  }

  @override
  Step invert(Node doc) {
    final node = doc.nodeAt(pos);
    if (node != null) {
      final newSet = mark.addToSet(node.marks);
      if (newSet.length == node.marks.length) {
        for (var i = 0; i < node.marks.length; i++) {
          if (!node.marks[i].isInSet(newSet)) {
            return AddNodeMarkStep(pos, node.marks[i]);
          }
        }
        return AddNodeMarkStep(pos, mark);
      }
    }
    return RemoveNodeMarkStep(pos, mark);
  }

  @override
  Step? map(Mappable mapping) {
    final pos = mapping.mapResult(this.pos, 1);
    return pos.deletedAfter ? null : AddNodeMarkStep(pos.pos, mark);
  }

  @override
  Object? toJSON() {
    return <String, Object?>{
      "stepType": "addNodeMark",
      "pos": pos,
      "mark": mark.toJSON(),
    };
  }

  /// @internal
  static Step fromJSON(Schema schema, Object? json) {
    final map = json as Map;
    if (map["pos"] is! int) {
      throw RangeError("Invalid input for AddNodeMarkStep.fromJSON");
    }
    return AddNodeMarkStep(map["pos"] as int, schema.markFromJSON(map["mark"]));
  }
}

/// Remove a mark from a specific node.
class RemoveNodeMarkStep extends Step {
  /// Create a mark-removing step.
  RemoveNodeMarkStep(this.pos, this.mark);

  /// The position of the target node.
  final int pos;

  /// The mark to remove.
  final Mark mark;

  @override
  StepResult apply(Node doc) {
    final node = doc.nodeAt(pos);
    if (node == null) {
      return StepResult.fail("No node at mark step's position");
    }
    final updated = node.type.create(
      node.attrs,
      null,
      mark.removeFromSet(node.marks),
    );
    return StepResult.fromReplace(
      doc,
      pos,
      pos + 1,
      Slice(Fragment.from(updated), 0, node.isLeaf ? 0 : 1),
    );
  }

  @override
  Step invert(Node doc) {
    final node = doc.nodeAt(pos);
    if (node == null || !mark.isInSet(node.marks)) {
      return this;
    }
    return AddNodeMarkStep(pos, mark);
  }

  @override
  Step? map(Mappable mapping) {
    final pos = mapping.mapResult(this.pos, 1);
    return pos.deletedAfter ? null : RemoveNodeMarkStep(pos.pos, mark);
  }

  @override
  Object? toJSON() {
    return <String, Object?>{
      "stepType": "removeNodeMark",
      "pos": pos,
      "mark": mark.toJSON(),
    };
  }

  /// @internal
  static Step fromJSON(Schema schema, Object? json) {
    final map = json as Map;
    if (map["pos"] is! int) {
      throw RangeError("Invalid input for RemoveNodeMarkStep.fromJSON");
    }
    return RemoveNodeMarkStep(
      map["pos"] as int,
      schema.markFromJSON(map["mark"]),
    );
  }
}
