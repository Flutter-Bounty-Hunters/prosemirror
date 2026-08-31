import 'package:prosemirror/src/inputrules/inputrules.dart';
import 'package:prosemirror/src/model/node.dart';
import 'package:prosemirror/src/model/schema.dart';
import 'package:prosemirror/src/state/state.dart';
import 'package:prosemirror/src/transform/structure.dart';

/// Build an input rule for automatically wrapping a textblock when a given
/// string is typed. The [regexp] argument is directly passed through to the
/// [InputRule] constructor. You'll probably want the regexp to start with `^`,
/// so that the pattern can only occur at the start of a textblock.
///
/// [nodeType] is the type of node to wrap in. If it needs attributes, you can
/// either pass them directly (as [Attrs]), or pass a function that will
/// compute them from the regular expression match.
///
/// By default, if there's a node with the same type above the newly wrapped
/// node, the rule will try to join those two nodes. You can pass a
/// [joinPredicate], which takes a regular expression match and the node before
/// the wrapped node, and can return a boolean to indicate whether a join
/// should happen.
InputRule wrappingInputRule(
  RegExp regexp,
  NodeType nodeType, [
  Object? getAttrs,
  bool Function(RegExpMatch match, Node node)? joinPredicate,
]) {
  return InputRule(regexp, (
    EditorState state,
    RegExpMatch match,
    int start,
    int end,
  ) {
    final Attrs? attrs;
    if (getAttrs is Attrs? Function(RegExpMatch)) {
      attrs = getAttrs(match);
    } else {
      attrs = getAttrs as Attrs?;
    }
    final tr = state.tr;
    tr.delete(start, end);
    final $start = tr.doc.resolve(start);
    final range = $start.blockRange();
    final wrapping = range != null
        ? findWrapping(range, nodeType, attrs)
        : null;
    if (wrapping == null) {
      return null;
    }
    tr.wrap(range!, wrapping);
    final before = tr.doc.resolve(start - 1).nodeBefore;
    if (before != null &&
        before.type == nodeType &&
        canJoin(tr.doc, start - 1) &&
        (joinPredicate == null || joinPredicate(match, before))) {
      tr.join(start - 1);
    }
    return tr;
  });
}

/// Build an input rule that changes the type of a textblock when the matched
/// text is typed into it. You'll usually want to start your regexp with `^` so
/// that it is only matched at the start of a textblock. The optional
/// [getAttrs] parameter can be used to compute the new node's attributes, and
/// works the same as in the [wrappingInputRule] function.
InputRule textblockTypeInputRule(
  RegExp regexp,
  NodeType nodeType, [
  Object? getAttrs,
]) {
  return InputRule(regexp, (
    EditorState state,
    RegExpMatch match,
    int start,
    int end,
  ) {
    final $start = state.doc.resolve(start);
    final Attrs? attrs;
    if (getAttrs is Attrs? Function(RegExpMatch)) {
      attrs = getAttrs(match);
    } else {
      attrs = getAttrs as Attrs?;
    }
    if (!$start
        .node(-1)
        .canReplaceWith($start.index(-1), $start.indexAfter(-1), nodeType)) {
      return null;
    }
    final tr = state.tr;
    tr.delete(start, end);
    tr.setBlockType(start, start, nodeType, attrs);
    return tr;
  });
}
