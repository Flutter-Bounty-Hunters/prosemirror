import 'package:prosemirror/src/model/model.dart';

import 'package:prosemirror/src/transform/map.dart';
import 'package:prosemirror/src/transform/step.dart';
import 'package:prosemirror/src/transform/mark.dart' as mark_methods;
import 'package:prosemirror/src/transform/replace.dart' as replace_methods;
import 'package:prosemirror/src/transform/structure.dart' as structure_methods;
import 'package:prosemirror/src/transform/attr_step.dart';
import 'package:prosemirror/src/transform/mark_step.dart';

/// @internal
class TransformError extends Error {
  TransformError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Abstraction to build up and track an array of [Step]s representing a
/// document transformation.
///
/// Most transforming methods return the `Transform` object itself, so
/// that they can be chained.
class Transform {
  /// Create a transform that starts with the given document.
  Transform(this.doc);

  /// The current document (the result of applying the steps in the
  /// transform).
  Node doc;

  /// The steps in this transform.
  final List<Step> steps = <Step>[];

  /// The documents before each of the steps.
  final List<Node> docs = <Node>[];

  /// A mapping with the maps for each of the steps in this transform.
  final Mapping mapping = Mapping();

  /// The starting document.
  Node get before => docs.isNotEmpty ? docs[0] : doc;

  /// Apply a new step in this transform, saving the result. Throws an
  /// error when the step fails.
  Transform step(Step step) {
    final result = maybeStep(step);
    if (result.failed != null) {
      throw TransformError(result.failed!);
    }
    return this;
  }

  /// Try to apply a step in this transformation, ignoring it if it
  /// fails. Returns the step result.
  StepResult maybeStep(Step step) {
    final result = step.apply(doc);
    if (result.failed == null) {
      addStep(step, result.doc!);
    }
    return result;
  }

  /// True when the document has been changed (when there are any steps).
  bool get docChanged => steps.isNotEmpty;

  /// Return a single range, in post-transform document positions, that
  /// covers all content changed by this transform. Returns null if no
  /// replacements are made. Note that this will ignore changes that
  /// add/remove marks without replacing the underlying content.
  ({int from, int to})? changedRange() {
    var from = 1000000000;
    var to = -1000000000;
    for (var i = 0; i < mapping.maps.length; i++) {
      final map = mapping.maps[i];
      if (i != 0) {
        from = map.map(from, 1);
        to = map.map(to, -1);
      }
      map.forEach((_, _, fromB, toB) {
        from = from < fromB ? from : fromB;
        to = to > toB ? to : toB;
      });
    }
    return from == 1000000000 ? null : (from: from, to: to);
  }

  /// @internal
  void addStep(Step step, Node doc) {
    docs.add(this.doc);
    steps.add(step);
    mapping.appendMap(step.getMap());
    this.doc = doc;
  }

  /// Replace the part of the document between `from` and `to` with the
  /// given `slice`.
  Transform replace(int from, [int? to, Slice? slice]) {
    to ??= from;
    slice ??= Slice.empty;
    final step = replace_methods.replaceStep(doc, from, to, slice);
    if (step != null) {
      this.step(step);
    }
    return this;
  }

  /// Replace the given range with the given content, which may be a
  /// fragment, node, or array of nodes.
  Transform replaceWith(int from, int to, Object content) {
    return replace(from, to, Slice(Fragment.from(content), 0, 0));
  }

  /// Delete the content between the given positions.
  Transform delete(int from, int to) {
    return replace(from, to, Slice.empty);
  }

  /// Insert the given content at the given position.
  Transform insert(int pos, Object content) {
    return replaceWith(pos, pos, content);
  }

  /// Replace a range of the document with a given slice, using `from`,
  /// `to`, and the slice's [openStart](Slice.openStart) property as
  /// hints, rather than fixed start and end points.
  Transform replaceRange(int from, int to, Slice slice) {
    replace_methods.replaceRange(this, from, to, slice);
    return this;
  }

  /// Replace the given range with a node, but use `from` and `to` as
  /// hints, rather than precise positions.
  Transform replaceRangeWith(int from, int to, Node node) {
    replace_methods.replaceRangeWith(this, from, to, node);
    return this;
  }

  /// Delete the given range, expanding it to cover fully covered parent
  /// nodes until a valid replace is found.
  Transform deleteRange(int from, int to) {
    replace_methods.deleteRange(this, from, to);
    return this;
  }

  /// Split the content in the given range off from its parent, if there
  /// is sibling content before or after it, and move it up the tree to
  /// the depth specified by `target`.
  Transform lift(NodeRange range, int target) {
    structure_methods.lift(this, range, target);
    return this;
  }

  /// Join the blocks around the given position. If depth is 2, their
  /// last and first siblings are also joined, and so on.
  Transform join(int pos, [int depth = 1]) {
    structure_methods.join(this, pos, depth);
    return this;
  }

  /// Wrap the given [range](NodeRange) in the given set of wrappers.
  Transform wrap(
    NodeRange range,
    List<({NodeType type, Attrs? attrs})> wrappers,
  ) {
    structure_methods.wrap(this, range, wrappers);
    return this;
  }

  /// Set the type of all textblocks (partly) between `from` and `to` to
  /// the given node type with the given attributes.
  Transform setBlockType(int from, int to, NodeType type, [Object? attrs]) {
    structure_methods.setBlockType(this, from, to, type, attrs);
    return this;
  }

  /// Change the type, attributes, and/or marks of the node at `pos`.
  /// When `type` isn't given, the existing node type is preserved.
  Transform setNodeMarkup(
    int pos, [
    NodeType? type,
    Attrs? attrs,
    List<Mark>? marks,
  ]) {
    structure_methods.setNodeMarkup(this, pos, type, attrs, marks);
    return this;
  }

  /// Set a single attribute on a given node to a new value. The `pos`
  /// addresses the document content. Use [setDocAttribute] to set
  /// attributes on the document itself.
  Transform setNodeAttribute(int pos, String attr, Object? value) {
    step(AttrStep(pos, attr, value));
    return this;
  }

  /// Set a single attribute on the document to a new value.
  Transform setDocAttribute(String attr, Object? value) {
    step(DocAttrStep(attr, value));
    return this;
  }

  /// Add a mark to the node at position `pos`.
  Transform addNodeMark(int pos, Mark mark) {
    step(AddNodeMarkStep(pos, mark));
    return this;
  }

  /// Remove a mark (or all marks of the given type) from the node at
  /// position `pos`.
  Transform removeNodeMark(int pos, Object mark) {
    final node = doc.nodeAt(pos);
    if (node == null) {
      throw RangeError("No node at position $pos");
    }
    if (mark is Mark) {
      if (mark.isInSet(node.marks)) {
        step(RemoveNodeMarkStep(pos, mark));
      }
    } else {
      final markType = mark as MarkType;
      var set = node.marks;
      Mark? found;
      final foundSteps = <Step>[];
      while ((found = markType.isInSet(set)) != null) {
        foundSteps.add(RemoveNodeMarkStep(pos, found!));
        set = found.removeFromSet(set);
      }
      for (var i = foundSteps.length - 1; i >= 0; i--) {
        step(foundSteps[i]);
      }
    }
    return this;
  }

  /// Split the node at the given position, and optionally, if `depth`
  /// is greater than one, any number of nodes above that.
  Transform split(
    int pos, [
    int depth = 1,
    List<({NodeType type, Attrs? attrs})>? typesAfter,
  ]) {
    structure_methods.split(this, pos, depth, typesAfter);
    return this;
  }

  /// Add the given mark to the inline content between `from` and `to`.
  Transform addMark(int from, int to, Mark mark) {
    mark_methods.addMark(this, from, to, mark);
    return this;
  }

  /// Remove marks from inline nodes between `from` and `to`. When
  /// `mark` is a single mark, remove precisely that mark. When it is a
  /// mark type, remove all marks of that type. When it is null, remove
  /// all marks of any type.
  Transform removeMark(int from, int to, [Object? mark]) {
    mark_methods.removeMark(this, from, to, mark);
    return this;
  }

  /// Removes all marks and nodes from the content of the node at `pos`
  /// that don't match the given new parent node type.
  Transform clearIncompatible(
    int pos,
    NodeType parentType, [
    ContentMatch? match,
  ]) {
    mark_methods.clearIncompatible(this, pos, parentType, match);
    return this;
  }
}
