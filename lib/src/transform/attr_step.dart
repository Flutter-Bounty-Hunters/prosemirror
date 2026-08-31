import 'package:prosemirror/src/model/fragment.dart';
import 'package:prosemirror/src/model/node.dart';
import 'package:prosemirror/src/model/replace.dart';
import 'package:prosemirror/src/model/schema.dart';

import 'package:prosemirror/src/transform/step.dart';
import 'package:prosemirror/src/transform/map.dart';

/// Update an attribute in a specific node.
class AttrStep extends Step {
  /// Construct an attribute step.
  AttrStep(this.pos, this.attr, this.value);

  /// The position of the target node.
  final int pos;

  /// The attribute to set.
  final String attr;

  /// The attribute's new value.
  final Object? value;

  @override
  StepResult apply(Node doc) {
    final node = doc.nodeAt(pos);
    if (node == null) {
      return StepResult.fail("No node at attribute step's position");
    }
    final attrs = <String, Object?>{};
    for (final name in node.attrs.keys) {
      attrs[name] = node.attrs[name];
    }
    attrs[attr] = value;
    final updated = node.type.create(attrs, null, node.marks);
    return StepResult.fromReplace(
      doc,
      pos,
      pos + 1,
      Slice(Fragment.from(updated), 0, node.isLeaf ? 0 : 1),
    );
  }

  @override
  StepMap getMap() {
    return StepMap.empty;
  }

  @override
  Step invert(Node doc) {
    return AttrStep(pos, attr, doc.nodeAt(pos)!.attrs[attr]);
  }

  @override
  Step? map(Mappable mapping) {
    final pos = mapping.mapResult(this.pos, 1);
    return pos.deletedAfter ? null : AttrStep(pos.pos, attr, value);
  }

  @override
  Object? toJSON() {
    return <String, Object?>{
      "stepType": "attr",
      "pos": pos,
      "attr": attr,
      "value": value,
    };
  }

  /// @internal
  static Step fromJSON(Schema schema, Object? json) {
    final map = json as Map;
    if (map["pos"] is! int || map["attr"] is! String) {
      throw RangeError("Invalid input for AttrStep.fromJSON");
    }
    return AttrStep(map["pos"] as int, map["attr"] as String, map["value"]);
  }
}

/// Update an attribute in the doc node.
class DocAttrStep extends Step {
  /// Construct an attribute step.
  DocAttrStep(this.attr, this.value);

  /// The attribute to set.
  final String attr;

  /// The attribute's new value.
  final Object? value;

  @override
  StepResult apply(Node doc) {
    final attrs = <String, Object?>{};
    for (final name in doc.attrs.keys) {
      attrs[name] = doc.attrs[name];
    }
    attrs[attr] = value;
    final updated = doc.type.create(attrs, doc.content, doc.marks);
    return StepResult.ok(updated);
  }

  @override
  StepMap getMap() {
    return StepMap.empty;
  }

  @override
  Step invert(Node doc) {
    return DocAttrStep(attr, doc.attrs[attr]);
  }

  @override
  Step? map(Mappable mapping) {
    return this;
  }

  @override
  Object? toJSON() {
    return <String, Object?>{
      "stepType": "docAttr",
      "attr": attr,
      "value": value,
    };
  }

  /// @internal
  static Step fromJSON(Schema schema, Object? json) {
    final map = json as Map;
    if (map["attr"] is! String) {
      throw RangeError("Invalid input for DocAttrStep.fromJSON");
    }
    return DocAttrStep(map["attr"] as String, map["value"]);
  }
}
