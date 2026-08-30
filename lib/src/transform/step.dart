import 'package:prosemirror/src/model/model.dart';

import 'package:prosemirror/src/transform/map.dart';
import 'package:prosemirror/src/transform/attr_step.dart';
import 'package:prosemirror/src/transform/mark_step.dart';
import 'package:prosemirror/src/transform/replace_step.dart';

/// The factory signature used to deserialize a [Step] from JSON.
typedef StepJsonFactory = Step Function(Schema schema, Object? json);

final Map<String, StepJsonFactory> _stepsByID = <String, StepJsonFactory>{};
bool _builtinsRegistered = false;

/// A step object represents an atomic change. It generally applies
/// only to the document it was created for, since the positions
/// stored in it will only make sense for that document.
///
/// New steps are defined by creating classes that extend [Step],
/// overriding the [apply], [invert], [map], [getMap] and `fromJSON`
/// methods, and registering your class with a unique
/// JSON-serialization identifier using [Step.jsonID].
abstract class Step {
  /// Applies this step to the given document, returning a result
  /// object that either indicates failure, if the step can not be
  /// applied to this document, or indicates success by containing a
  /// transformed document.
  StepResult apply(Node doc);

  /// Get the step map that represents the changes made by this step,
  /// and which can be used to transform between positions in the old
  /// and the new document.
  StepMap getMap() {
    return StepMap.empty;
  }

  /// Create an inverted version of this step. Needs the document as it
  /// was before the step as argument.
  Step invert(Node doc);

  /// Map this step through a mappable thing, returning either a
  /// version of that step with its positions adjusted, or `null` if
  /// the step was entirely deleted by the mapping.
  Step? map(Mappable mapping);

  /// Try to merge this step with another one, to be applied directly
  /// after it. Returns the merged step when possible, null if the
  /// steps can't be merged.
  Step? merge(Step other) {
    return null;
  }

  /// Create a JSON-serializeable representation of this step. When
  /// defining this for a custom subclass, make sure the result object
  /// includes the step type's JSON id under the `stepType` property.
  Object? toJSON();

  /// Deserialize a step from its JSON representation. Will call
  /// through to the step class' own implementation of this method.
  static Step fromJSON(Schema schema, Object? json) {
    _ensureBuiltinStepsRegistered();
    if (json == null || (json as Map)["stepType"] == null) {
      throw RangeError("Invalid input for Step.fromJSON");
    }
    final type = _stepsByID[json["stepType"]];
    if (type == null) {
      throw RangeError("No step type ${json["stepType"]} defined");
    }
    return type(schema, json);
  }

  /// To be able to serialize steps to JSON, each step needs a string
  /// ID to attach to its JSON representation. Use this method to
  /// register an ID for your step classes. Try to pick something
  /// that's unlikely to clash with steps from other modules.
  static void jsonID(String id, StepJsonFactory stepClass) {
    if (_stepsByID.containsKey(id)) {
      throw RangeError("Duplicate use of step JSON ID $id");
    }
    _stepsByID[id] = stepClass;
  }
}

void _ensureBuiltinStepsRegistered() {
  if (_builtinsRegistered) {
    return;
  }
  _builtinsRegistered = true;
  Step.jsonID("replace", ReplaceStep.fromJSON);
  Step.jsonID("replaceAround", ReplaceAroundStep.fromJSON);
  Step.jsonID("addMark", AddMarkStep.fromJSON);
  Step.jsonID("removeMark", RemoveMarkStep.fromJSON);
  Step.jsonID("addNodeMark", AddNodeMarkStep.fromJSON);
  Step.jsonID("removeNodeMark", RemoveNodeMarkStep.fromJSON);
  Step.jsonID("attr", AttrStep.fromJSON);
  Step.jsonID("docAttr", DocAttrStep.fromJSON);
}

/// The result of [applying](Step.apply) a step. Contains either a
/// new document or a failure value.
class StepResult {
  /// @internal
  StepResult(this.doc, this.failed);

  /// The transformed document, if successful.
  final Node? doc;

  /// The failure message, if unsuccessful.
  final String? failed;

  /// Create a successful step result.
  static StepResult ok(Node doc) {
    return StepResult(doc, null);
  }

  /// Create a failed step result.
  static StepResult fail(String message) {
    return StepResult(null, message);
  }

  /// Call [Node.replace] with the given arguments. Create a successful
  /// result if it succeeds, and a failed one if it throws a
  /// [ReplaceError].
  static StepResult fromReplace(Node doc, int from, int to, Slice slice) {
    try {
      return StepResult.ok(doc.replace(from, to, slice));
    } on ReplaceError catch (error) {
      return StepResult.fail(error.message);
    }
  }
}
