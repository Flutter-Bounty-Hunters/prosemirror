library;

import 'package:prosemirror/src/model/content.dart';
import 'package:prosemirror/src/model/fragment.dart';
import 'package:prosemirror/src/model/node.dart';
import 'package:prosemirror/src/model/replace.dart';
import 'package:prosemirror/src/model/resolved_pos.dart';
import 'package:prosemirror/src/model/schema.dart';
import 'package:prosemirror/src/state/selection.dart';
import 'package:prosemirror/src/state/transaction.dart';
import 'package:prosemirror/src/state/state.dart';
import 'package:prosemirror/src/transform/step.dart';
import 'package:prosemirror/src/transform/replace_step.dart';
import 'package:prosemirror/src/transform/replace.dart';
import 'package:prosemirror/src/transform/structure.dart';

import 'package:prosemirror/src/commands/platform.dart';

final _whitespaceOnly = RegExp(r'^\s*$');
final _leadingWhitespaceRegExp = RegExp(r'^\s*');
final _trailingWhitespaceRegExp = RegExp(r'\s*$');

/// Create a custom split-block command result.
typedef SplitBlockFunction = SplitBlockType? Function(
  Node node,
  bool atEnd,
  ResolvedPos position,
);

/// Describes the node type to use after splitting a block.
class SplitBlockType {
  /// Creates a split block type description.
  const SplitBlockType({required this.type, this.attrs});

  /// The node type to use after the split.
  final NodeType type;

  /// Attributes for the node after the split.
  final Attrs? attrs;

  NodeTypeWithAttributes get _record => (type: type, attrs: attrs);
}

/// Options for [toggleMark].
class ToggleMarkOptions {
  /// Creates toggle-mark options.
  const ToggleMarkOptions({
    this.removeWhenPresent,
    this.enterInlineAtoms,
    this.includeWhitespace,
  });

  /// Whether to remove a mark when any part of the selection already has it.
  final bool? removeWhenPresent;

  /// Whether the command should enter completely selected inline atoms.
  final bool? enterInlineAtoms;

  /// Whether to include leading and trailing selection whitespace.
  final bool? includeWhitespace;
}

/// Delete the selection, if there is one.
final Command deleteSelection = FunctionCommand(_deleteSelection);

/// Join backward from the start of a textblock.
final Command joinBackward = FunctionCommand(_joinBackward);

/// Join the textblock before the cursor.
final Command joinTextblockBackward = FunctionCommand(_joinTextblockBackward);

/// Join the textblock after the cursor.
final Command joinTextblockForward = FunctionCommand(_joinTextblockForward);

/// Select the node before the cursor.
final Command selectNodeBackward = FunctionCommand(_selectNodeBackward);

/// Join forward from the end of a textblock.
final Command joinForward = FunctionCommand(_joinForward);

/// Select the node after the cursor.
final Command selectNodeForward = FunctionCommand(_selectNodeForward);

/// Join the selected block with the sibling above it.
final Command joinUp = FunctionCommand(_joinUp);

/// Join the selected block with the sibling below it.
final Command joinDown = FunctionCommand(_joinDown);

/// Lift the selected block out of its parent.
final Command lift = FunctionCommand(_lift);

/// Insert a newline when the selection is inside a code block.
final Command newlineInCode = FunctionCommand(_newlineInCode);

/// Move the cursor into a default block after the current code block.
final Command exitCode = FunctionCommand(_exitCode);

/// Create an empty paragraph near a selected block node.
final Command createParagraphNear = FunctionCommand(_createParagraphNear);

/// Lift an empty textblock when possible.
final Command liftEmptyBlock = FunctionCommand(_liftEmptyBlock);

/// Split the parent block while keeping active marks.
final Command splitBlockKeepMarks = FunctionCommand(_splitBlockKeepMarks);

/// Select the node wrapping the current selection.
final Command selectParentNode = FunctionCommand(_selectParentNode);

/// Select the whole document.
final Command selectAll = FunctionCommand(_selectAll);

bool _deleteSelection(
  EditorState state, [
  void Function(Transaction tr)? dispatch,
  Object? view,
]) {
  if (state.selection.empty) {
    return false;
  }
  dispatch?.call(state.tr.deleteSelection().scrollIntoView());
  return true;
}

bool _joinBackward(
  EditorState state, [
  void Function(Transaction tr)? dispatch,
  Object? view,
]) {
  final cursor = _atBlockStart(state, view);
  if (cursor == null) {
    return false;
  }

  final cut = _findCutBefore(cursor);
  if (cut == null) {
    final range = cursor.blockRange();
    final target = range != null ? liftTarget(range) : null;
    if (target == null) {
      return false;
    }
    dispatch?.call((state.tr..lift(range!, target)).scrollIntoView());
    return true;
  }

  final before = cut.nodeBefore!;
  if (_deleteBarrier(state, cut, dispatch, -1)) {
    return true;
  }

  if (cursor.parent.content.size == 0 &&
      (_textblockAt(before, _BlockSide.end) ||
          NodeSelection.isSelectable(before))) {
    for (var depth = cursor.depth; ; depth--) {
      final deleteStep = replaceStep(
        state.doc,
        cursor.before(depth),
        cursor.after(depth),
        Slice.empty,
      );
      if (deleteStep is ReplaceStep &&
          deleteStep.slice.size < deleteStep.to - deleteStep.from) {
        if (dispatch != null) {
          final tr = state.tr.step(deleteStep) as Transaction;
          tr.setSelection(
            _textblockAt(before, _BlockSide.end)
                ? Selection.findFrom(
                    tr.doc.resolve(tr.mapping.map(cut.pos, -1)),
                    -1,
                  )!
                : NodeSelection.create(tr.doc, cut.pos - before.nodeSize),
          );
          dispatch(tr.scrollIntoView());
        }
        return true;
      }
      if (depth == 1 || cursor.node(depth - 1).childCount > 1) {
        break;
      }
    }
  }

  if (before.isAtom && cut.depth == cursor.depth - 1) {
    dispatch?.call(
      (state.tr..delete(cut.pos - before.nodeSize, cut.pos)).scrollIntoView(),
    );
    return true;
  }

  return false;
}

bool _joinTextblockBackward(
  EditorState state, [
  void Function(Transaction tr)? dispatch,
  Object? view,
]) {
  final cursor = _atBlockStart(state, view);
  if (cursor == null) {
    return false;
  }
  final cut = _findCutBefore(cursor);
  return cut != null ? _joinTextblocksAround(state, cut, dispatch) : false;
}

bool _joinTextblockForward(
  EditorState state, [
  void Function(Transaction tr)? dispatch,
  Object? view,
]) {
  final cursor = _atBlockEnd(state, view);
  if (cursor == null) {
    return false;
  }
  final cut = _findCutAfter(cursor);
  return cut != null ? _joinTextblocksAround(state, cut, dispatch) : false;
}

bool _selectNodeBackward(
  EditorState state, [
  void Function(Transaction tr)? dispatch,
  Object? view,
]) {
  final selection = state.selection;
  ResolvedPos? cut = selection.$head;
  if (!selection.empty) {
    return false;
  }

  if (selection.$head.parent.isTextblock) {
    if (!_viewAtTextblock(view, state, "backward") &&
        selection.$head.parentOffset > 0) {
      return false;
    }
    cut = _findCutBefore(selection.$head);
    if (cut == null) {
      return false;
    }
  }

  final node = cut.nodeBefore;
  if (node == null || !NodeSelection.isSelectable(node)) {
    return false;
  }
  dispatch?.call(
    state.tr
        .setSelection(NodeSelection.create(state.doc, cut.pos - node.nodeSize))
        .scrollIntoView(),
  );
  return true;
}

bool _joinForward(
  EditorState state, [
  void Function(Transaction tr)? dispatch,
  Object? view,
]) {
  final cursor = _atBlockEnd(state, view);
  if (cursor == null) {
    return false;
  }

  final cut = _findCutAfter(cursor);
  if (cut == null) {
    return false;
  }

  final after = cut.nodeAfter!;
  if (_deleteBarrier(state, cut, dispatch, 1)) {
    return true;
  }

  if (cursor.parent.content.size == 0 &&
      (_textblockAt(after, _BlockSide.start) ||
          NodeSelection.isSelectable(after))) {
    final deleteStep = replaceStep(
      state.doc,
      cursor.before(),
      cursor.after(),
      Slice.empty,
    );
    if (deleteStep is ReplaceStep &&
        deleteStep.slice.size < deleteStep.to - deleteStep.from) {
      if (dispatch != null) {
        final tr = state.tr.step(deleteStep) as Transaction;
        tr.setSelection(
          _textblockAt(after, _BlockSide.start)
              ? Selection.findFrom(tr.doc.resolve(tr.mapping.map(cut.pos)), 1)!
              : NodeSelection.create(tr.doc, tr.mapping.map(cut.pos)),
        );
        dispatch(tr.scrollIntoView());
      }
      return true;
    }
  }

  if (after.isAtom && cut.depth == cursor.depth - 1) {
    dispatch?.call(
      (state.tr..delete(cut.pos, cut.pos + after.nodeSize)).scrollIntoView(),
    );
    return true;
  }

  return false;
}

bool _selectNodeForward(
  EditorState state, [
  void Function(Transaction tr)? dispatch,
  Object? view,
]) {
  final selection = state.selection;
  ResolvedPos? cut = selection.$head;
  if (!selection.empty) {
    return false;
  }
  if (selection.$head.parent.isTextblock) {
    if (!_viewAtTextblock(view, state, "forward") &&
        selection.$head.parentOffset < selection.$head.parent.content.size) {
      return false;
    }
    cut = _findCutAfter(selection.$head);
    if (cut == null) {
      return false;
    }
  }
  final node = cut.nodeAfter;
  if (node == null || !NodeSelection.isSelectable(node)) {
    return false;
  }
  dispatch?.call(
    state.tr
        .setSelection(NodeSelection.create(state.doc, cut.pos))
        .scrollIntoView(),
  );
  return true;
}

bool _joinUp(
  EditorState state, [
  void Function(Transaction tr)? dispatch,
  Object? view,
]) {
  final selection = state.selection;
  final nodeSelection = selection is NodeSelection;
  int? point;
  if (nodeSelection) {
    if (selection.node.isTextblock || !canJoin(state.doc, selection.from)) {
      return false;
    }
    point = selection.from;
  } else {
    point = joinPoint(state.doc, selection.from, -1);
    if (point == null) {
      return false;
    }
  }
  if (dispatch != null) {
    final tr = state.tr.join(point) as Transaction;
    if (nodeSelection) {
      tr.setSelection(
        NodeSelection.create(
          tr.doc,
          point - state.doc.resolve(point).nodeBefore!.nodeSize,
        ),
      );
    }
    dispatch(tr.scrollIntoView());
  }
  return true;
}

bool _joinDown(
  EditorState state, [
  void Function(Transaction tr)? dispatch,
  Object? view,
]) {
  final selection = state.selection;
  int? point;
  if (selection is NodeSelection) {
    if (selection.node.isTextblock || !canJoin(state.doc, selection.to)) {
      return false;
    }
    point = selection.to;
  } else {
    point = joinPoint(state.doc, selection.to, 1);
    if (point == null) {
      return false;
    }
  }
  dispatch?.call((state.tr..join(point)).scrollIntoView());
  return true;
}

bool _lift(
  EditorState state, [
  void Function(Transaction tr)? dispatch,
  Object? view,
]) {
  final range = state.selection.$from.blockRange(state.selection.$to);
  final target = range != null ? liftTarget(range) : null;
  if (target == null) {
    return false;
  }
  dispatch?.call((state.tr..lift(range!, target)).scrollIntoView());
  return true;
}

bool _newlineInCode(
  EditorState state, [
  void Function(Transaction transaction)? dispatch,
  Object? view,
]) {
  final head = state.selection.$head;
  final anchor = state.selection.$anchor;
  if (!head.parent.type.spec.code || !head.sameParent(anchor)) {
    return false;
  }
  dispatch?.call(state.tr.insertText("\n").scrollIntoView());
  return true;
}

bool _exitCode(
  EditorState state, [
  void Function(Transaction transaction)? dispatch,
  Object? view,
]) {
  final head = state.selection.$head;
  final anchor = state.selection.$anchor;
  if (!head.parent.type.spec.code || !head.sameParent(anchor)) {
    return false;
  }
  final above = head.node(-1);
  final after = head.indexAfter(-1);
  final type = _defaultBlockAt(above.contentMatchAt(after));
  if (type == null || !above.canReplaceWith(after, after, type)) {
    return false;
  }
  if (dispatch != null) {
    final pos = head.after();
    final transaction = state.tr;
    transaction.replaceWith(pos, pos, type.createAndFill()!);
    transaction.setSelection(Selection.near(transaction.doc.resolve(pos), 1));
    dispatch(transaction.scrollIntoView());
  }
  return true;
}

bool _createParagraphNear(
  EditorState state, [
  void Function(Transaction tr)? dispatch,
  Object? view,
]) {
  final selection = state.selection;
  final from = selection.$from;
  final to = selection.$to;
  if (selection is AllSelection ||
      from.parent.inlineContent ||
      to.parent.inlineContent) {
    return false;
  }
  final type = _defaultBlockAt(to.parent.contentMatchAt(to.indexAfter()));
  if (type == null || !type.isTextblock) {
    return false;
  }
  if (dispatch != null) {
    final side = from.parentOffset == 0 && to.index() < to.parent.childCount
        ? from.pos
        : to.pos;
    final tr = state.tr.insert(side, type.createAndFill()!) as Transaction;
    tr.setSelection(TextSelection.create(tr.doc, side + 1));
    dispatch(tr.scrollIntoView());
  }
  return true;
}

bool _liftEmptyBlock(
  EditorState state, [
  void Function(Transaction tr)? dispatch,
  Object? view,
]) {
  final selection = state.selection;
  final cursor = selection is TextSelection ? selection.$cursor : null;
  if (cursor == null || cursor.parent.content.size != 0) {
    return false;
  }
  if (cursor.depth > 1 && cursor.after() != cursor.end(-1)) {
    final before = cursor.before();
    if (canSplit(state.doc, before)) {
      dispatch?.call((state.tr..split(before)).scrollIntoView());
      return true;
    }
  }
  final range = cursor.blockRange();
  final target = range != null ? liftTarget(range) : null;
  if (target == null) {
    return false;
  }
  dispatch?.call((state.tr..lift(range!, target)).scrollIntoView());
  return true;
}

/// Create a [splitBlock] variant that chooses the split-off block type.
Command splitBlockAs([SplitBlockFunction? splitNode]) {
  return _SplitBlockCommand(splitNode);
}

class _SplitBlockCommand implements Command {
  _SplitBlockCommand(this.splitNode);

  final SplitBlockFunction? splitNode;

  @override
  bool execute(
    EditorState state, [
    void Function(Transaction tr)? dispatch,
    Object? view,
  ]) {
    final stateSelection = state.selection;
    if (stateSelection is NodeSelection && stateSelection.node.isBlock) {
      final from = stateSelection.$from;
      if (from.parentOffset == 0 || !canSplit(state.doc, from.pos)) {
        return false;
      }
      dispatch?.call((state.tr..split(from.pos)).scrollIntoView());
      return true;
    }

    if (state.selection.$from.depth == 0) {
      return false;
    }

    final tr = state.tr;
    if (!state.selection.empty &&
        (state.selection is TextSelection || state.selection is AllSelection)) {
      tr.deleteSelection();
    }

    final from = tr.selection.$from;
    final mapFrom = tr.steps.length;
    final types = <NodeTypeWithAttributes?>[];
    late int splitDepth;
    NodeType? defaultType;
    var atEnd = false;
    var atStart = false;
    for (var depth = from.depth; ; depth--) {
      final node = from.node(depth);
      if (node.isBlock) {
        atEnd = from.end(depth) == from.pos + (from.depth - depth);
        atStart = from.start(depth) == from.pos - (from.depth - depth);
        defaultType = _defaultBlockAt(
          from.node(depth - 1).contentMatchAt(from.indexAfter(depth - 1)),
        );
        final splitType = splitNode?.call(from.parent, atEnd, from);
        types.insert(
          0,
          splitType?._record ??
              (atEnd && defaultType != null
                  ? (type: defaultType, attrs: null)
                  : null),
        );
        splitDepth = depth;
        break;
      }
      if (depth == 1) {
        return false;
      }
      types.insert(0, null);
    }

    final splitPos = from.pos;
    var can = _canSplitNullable(tr.doc, splitPos, types.length, types);
    if (!can) {
      types[0] = defaultType != null ? (type: defaultType, attrs: null) : null;
      can = _canSplitNullable(tr.doc, splitPos, types.length, types);
    }
    if (!can) {
      return false;
    }
    tr.split(splitPos, types.length, types);
    if (!atEnd &&
        atStart &&
        !identical(from.node(splitDepth).type, defaultType)) {
      final mapping = tr.mapping.slice(mapFrom);
      final first = mapping.map(from.before(splitDepth));
      final firstResolved = tr.doc.resolve(first);
      if (defaultType != null &&
          from
              .node(splitDepth - 1)
              .canReplaceWith(
                firstResolved.index(),
                firstResolved.index() + 1,
                defaultType,
              )) {
        tr.setNodeMarkup(mapping.map(from.before(splitDepth)), defaultType);
      }
    }
    dispatch?.call(tr.scrollIntoView());
    return true;
  }
}

/// Split the parent block of the selection.
final Command splitBlock = splitBlockAs();

bool _splitBlockKeepMarks(
  EditorState state, [
  void Function(Transaction tr)? dispatch,
  Object? view,
]) {
  final keepMarksDispatch = dispatch != null
      ? _KeepMarksDispatch(state, dispatch).dispatch
      : null;
  return splitBlock.execute(state, keepMarksDispatch, view);
}

class _KeepMarksDispatch {
  _KeepMarksDispatch(this.state, this.dispatchTransaction);

  final EditorState state;
  final void Function(Transaction tr) dispatchTransaction;

  void dispatch(Transaction tr) {
    final marks =
        state.storedMarks ??
        (state.selection.$to.parentOffset != 0
            ? state.selection.$from.marks()
            : null);
    if (marks != null) {
      tr.ensureMarks(marks);
    }
    dispatchTransaction(tr);
  }
}

bool _selectParentNode(
  EditorState state, [
  void Function(Transaction tr)? dispatch,
  Object? view,
]) {
  final from = state.selection.$from;
  final same = from.sharedDepth(state.selection.to);
  if (same == 0) {
    return false;
  }
  final pos = from.before(same);
  dispatch?.call(state.tr.setSelection(NodeSelection.create(state.doc, pos)));
  return true;
}

bool _selectAll(
  EditorState state, [
  void Function(Transaction transaction)? dispatch,
  Object? view,
]) {
  dispatch?.call(state.tr.setSelection(AllSelection(state.doc)));
  return true;
}

/// Moves the cursor to the start of the current textblock.
final Command selectTextblockStart = _selectTextblockSide(-1);

/// Moves the cursor to the end of the current textblock.
final Command selectTextblockEnd = _selectTextblockSide(1);

/// Wrap the selection in a node of the given type.
Command wrapIn(NodeType nodeType, [Attrs? attrs]) {
  return _WrapInCommand(nodeType, attrs);
}

class _WrapInCommand implements Command {
  _WrapInCommand(this.nodeType, this.attrs);

  final NodeType nodeType;
  final Attrs? attrs;

  @override
  bool execute(
    EditorState state, [
    void Function(Transaction tr)? dispatch,
    Object? view,
  ]) {
    final range = state.selection.$from.blockRange(state.selection.$to);
    final wrapping = range != null
        ? findWrapping(range, nodeType, attrs)
        : null;
    if (wrapping == null) {
      return false;
    }
    dispatch?.call((state.tr..wrap(range!, wrapping)).scrollIntoView());
    return true;
  }
}

/// Set selected textblocks to the given node type.
Command setBlockType(NodeType nodeType, [Attrs? attrs]) {
  return _SetBlockTypeCommand(nodeType, attrs);
}

class _SetBlockTypeCommand implements Command {
  _SetBlockTypeCommand(this.nodeType, this.attrs);

  final NodeType nodeType;
  final Attrs? attrs;

  @override
  bool execute(
    EditorState state, [
    void Function(Transaction tr)? dispatch,
    Object? view,
  ]) {
    var applicable = false;
    for (
      var index = 0;
      index < state.selection.ranges.length && !applicable;
      index++
    ) {
      final from = state.selection.ranges[index].$from.pos;
      final to = state.selection.ranges[index].$to.pos;
      state.doc.nodesBetween(from, to, (node, pos, parent, nodeIndex) {
        if (applicable) {
          return false;
        }
        if (!node.isTextblock || node.hasMarkup(nodeType, attrs)) {
          return null;
        }
        if (identical(node.type, nodeType)) {
          applicable = true;
        } else {
          final resolved = state.doc.resolve(pos);
          final index = resolved.index();
          applicable = resolved.parent.canReplaceWith(
            index,
            index + 1,
            nodeType,
          );
        }
        return null;
      });
    }
    if (!applicable) {
      return false;
    }
    if (dispatch != null) {
      final tr = state.tr;
      for (var index = 0; index < state.selection.ranges.length; index++) {
        final from = state.selection.ranges[index].$from.pos;
        final to = state.selection.ranges[index].$to.pos;
        tr.setBlockType(from, to, nodeType, attrs);
      }
      dispatch(tr.scrollIntoView());
    }
    return true;
  }
}

/// Toggle the given mark over the current selection.
Command toggleMark([
  MarkType? markType,
  Attrs? attrs,
  ToggleMarkOptions? options,
]) {
  return _ToggleMarkCommand(markType, attrs, options);
}

class _ToggleMarkCommand implements Command {
  _ToggleMarkCommand(this.markType, this.attrs, this.options);

  final MarkType? markType;
  final Attrs? attrs;
  final ToggleMarkOptions? options;

  @override
  bool execute(
    EditorState state, [
    void Function(Transaction tr)? dispatch,
    Object? view,
  ]) {
    final type = markType;
    if (type == null) {
      return false;
    }
    final selection = state.selection;
    final cursor = selection is TextSelection ? selection.$cursor : null;
    var ranges = selection.ranges;
    final removeWhenPresent = options?.removeWhenPresent != false;
    final enterAtoms = options?.enterInlineAtoms != false;
    final dropSpace = options?.includeWhitespace != true;

    if ((selection.empty && cursor == null) ||
        !_markApplies(state.doc, ranges, type, enterAtoms)) {
      return false;
    }
    if (dispatch == null) {
      return true;
    }

    if (cursor != null) {
      if (type.isInSet(state.storedMarks ?? cursor.marks()) != null) {
        dispatch(state.tr.removeStoredMark(type));
      } else {
        dispatch(state.tr.addStoredMark(type.create(attrs)));
      }
      return true;
    }

    final tr = state.tr;
    if (!enterAtoms) {
      ranges = _removeInlineAtoms(ranges);
    }
    var add = true;
    if (removeWhenPresent) {
      for (final range in ranges) {
        if (state.doc.rangeHasMark(range.$from.pos, range.$to.pos, type)) {
          add = false;
          break;
        }
      }
    } else {
      var everyCovered = true;
      for (final range in ranges) {
        var missing = false;
        tr.doc.nodesBetween(range.$from.pos, range.$to.pos, (
          node,
          pos,
          parent,
          nodeIndex,
        ) {
          if (missing) {
            return false;
          }
          final from = (range.$from.pos - pos).clamp(0, node.nodeSize);
          final to = (range.$to.pos - pos).clamp(0, node.nodeSize);
          missing =
              type.isInSet(node.marks) == null &&
              parent != null &&
              parent.type.allowsMarkType(type) &&
              !(node.isText &&
                  _whitespaceOnly.hasMatch(node.textBetween(from, to)));
          return null;
        });
        if (missing) {
          everyCovered = false;
          break;
        }
      }
      add = !everyCovered;
    }

    for (final range in ranges) {
      final from = range.$from.pos;
      final to = range.$to.pos;
      if (!add) {
        tr.removeMark(from, to, type);
      } else {
        var markFrom = from;
        var markTo = to;
        final start = range.$from.nodeAfter;
        final end = range.$to.nodeBefore;
        final spaceStart = dropSpace && start != null && start.isText
            ? _leadingWhitespace(start.text!)
            : 0;
        final spaceEnd = dropSpace && end != null && end.isText
            ? _trailingWhitespace(end.text!)
            : 0;
        if (markFrom + spaceStart < markTo) {
          markFrom += spaceStart;
          markTo -= spaceEnd;
        }
        tr.addMark(markFrom, markTo, type.create(attrs));
      }
    }
    dispatch(tr.scrollIntoView());
    return true;
  }
}

/// Wrap a command so that newly adjacent joinable nodes are joined.
Command autoJoin(Command command, Object isJoinable) {
  return _AutoJoinCommand(command, _autoJoinPredicate(isJoinable));
}

/// Combine commands into a command that runs them until one succeeds.
Command chainCommands(List<Command> commands) {
  return _ChainCommand(commands);
}

class _ChainCommand implements Command {
  _ChainCommand(this.commands);

  final List<Command> commands;

  @override
  bool execute(
    EditorState state, [
    void Function(Transaction transaction)? dispatch,
    Object? view,
  ]) {
    for (final command in commands) {
      if (command.execute(state, dispatch, view)) {
        return true;
      }
    }
    return false;
  }
}

final Command _backspaceCommand = chainCommands([
  deleteSelection,
  joinBackward,
  selectNodeBackward,
]);

final Command _deleteCommand = chainCommands([
  deleteSelection,
  joinForward,
  selectNodeForward,
]);

/// Basic command bindings that are not specific to any schema.
final Map<String, Command> pcBaseKeymap = {
  "Enter": chainCommands([
    newlineInCode,
    createParagraphNear,
    liftEmptyBlock,
    splitBlock,
  ]),
  "Mod-Enter": exitCode,
  "Backspace": _backspaceCommand,
  "Mod-Backspace": _backspaceCommand,
  "Shift-Backspace": _backspaceCommand,
  "Delete": _deleteCommand,
  "Mod-Delete": _deleteCommand,
  "Mod-a": selectAll,
};

/// Mac-style command bindings that extend [pcBaseKeymap].
final Map<String, Command> macBaseKeymap = {
  "Ctrl-h": pcBaseKeymap["Backspace"]!,
  "Alt-Backspace": pcBaseKeymap["Mod-Backspace"]!,
  "Ctrl-d": pcBaseKeymap["Delete"]!,
  "Ctrl-Alt-Backspace": pcBaseKeymap["Mod-Delete"]!,
  "Alt-Delete": pcBaseKeymap["Mod-Delete"]!,
  "Alt-d": pcBaseKeymap["Mod-Delete"]!,
  "Ctrl-a": selectTextblockStart,
  "Ctrl-e": selectTextblockEnd,
  ...pcBaseKeymap,
};

/// Default command bindings for the current platform.
final Map<String, Command> baseKeymap = isMacPlatform
    ? macBaseKeymap
    : pcBaseKeymap;

_AutoJoinPredicate _autoJoinPredicate(Object isJoinable) {
  if (isJoinable is List<String>) {
    return _AutoJoinNodeNames(isJoinable);
  }
  return _AutoJoinFunction(
    isJoinable as bool Function(Node before, Node after),
  );
}

abstract interface class _AutoJoinPredicate {
  bool matches(Node before, Node after);
}

class _AutoJoinNodeNames implements _AutoJoinPredicate {
  _AutoJoinNodeNames(this.names);

  final List<String> names;

  @override
  bool matches(Node before, Node after) {
    return names.contains(before.type.name);
  }
}

class _AutoJoinFunction implements _AutoJoinPredicate {
  _AutoJoinFunction(this.predicate);

  final bool Function(Node before, Node after) predicate;

  @override
  bool matches(Node before, Node after) {
    return predicate(before, after);
  }
}

class _AutoJoinCommand implements Command {
  _AutoJoinCommand(this.command, this.isJoinable);

  final Command command;
  final _AutoJoinPredicate isJoinable;

  @override
  bool execute(
    EditorState state, [
    void Function(Transaction tr)? dispatch,
    Object? view,
  ]) {
    final joinDispatch = dispatch != null
        ? _JoinDispatch(dispatch, isJoinable).dispatch
        : null;
    return command.execute(state, joinDispatch, view);
  }
}

ResolvedPos? _atBlockStart(EditorState state, Object? view) {
  final selection = state.selection;
  final cursor = selection is TextSelection ? selection.$cursor : null;
  if (cursor == null ||
      (!_viewAtTextblock(view, state, "backward") && cursor.parentOffset > 0)) {
    return null;
  }
  return cursor;
}

ResolvedPos? _atBlockEnd(EditorState state, Object? view) {
  final selection = state.selection;
  final cursor = selection is TextSelection ? selection.$cursor : null;
  if (cursor == null ||
      (!_viewAtTextblock(view, state, "forward") &&
          cursor.parentOffset < cursor.parent.content.size)) {
    return null;
  }
  return cursor;
}

bool _viewAtTextblock(Object? view, EditorState state, String direction) {
  if (view == null) {
    return false;
  }
  final dynamic dynamicView = view;
  try {
    return dynamicView.endOfTextblock(direction, state) as bool;
  } catch (_) {
    return false;
  }
}

bool _joinTextblocksAround(
  EditorState state,
  ResolvedPos cut,
  void Function(Transaction tr)? dispatch,
) {
  var beforeText = cut.nodeBefore!;
  var beforePos = cut.pos - 1;
  for (; !beforeText.isTextblock; beforePos--) {
    if (beforeText.type.spec.isolating) {
      return false;
    }
    final child = beforeText.lastChild;
    if (child == null) {
      return false;
    }
    beforeText = child;
  }
  var afterText = cut.nodeAfter!;
  var afterPos = cut.pos + 1;
  for (; !afterText.isTextblock; afterPos++) {
    if (afterText.type.spec.isolating) {
      return false;
    }
    final child = afterText.firstChild;
    if (child == null) {
      return false;
    }
    afterText = child;
  }
  final step = replaceStep(state.doc, beforePos, afterPos, Slice.empty);
  if (step == null || !_joinsTextblocks(step, beforePos, afterPos)) {
    return false;
  }
  if (dispatch != null) {
    final tr = state.tr.step(step) as Transaction;
    tr.setSelection(TextSelection.create(tr.doc, beforePos));
    dispatch(tr.scrollIntoView());
  }
  return true;
}

bool _joinsTextblocks(Step step, int beforePos, int afterPos) {
  if (step is ReplaceStep) {
    return step.from == beforePos && step.slice.size < afterPos - beforePos;
  }
  if (step is ReplaceAroundStep) {
    return step.slice.size < step.to - step.from;
  }
  return false;
}

enum _BlockSide { start, end }

bool _textblockAt(Node node, _BlockSide side, [bool only = false]) {
  for (Node? scan = node; scan != null;) {
    if (scan.isTextblock) {
      return true;
    }
    if (only && scan.childCount != 1) {
      return false;
    }
    scan = side == _BlockSide.start ? scan.firstChild : scan.lastChild;
  }
  return false;
}

ResolvedPos? _findCutBefore(ResolvedPos position) {
  if (!position.parent.type.spec.isolating) {
    for (var index = position.depth - 1; index >= 0; index--) {
      if (position.index(index) > 0) {
        return position.doc.resolve(position.before(index + 1));
      }
      if (position.node(index).type.spec.isolating) {
        break;
      }
    }
  }
  return null;
}

ResolvedPos? _findCutAfter(ResolvedPos position) {
  if (!position.parent.type.spec.isolating) {
    for (var index = position.depth - 1; index >= 0; index--) {
      final parent = position.node(index);
      if (position.index(index) + 1 < parent.childCount) {
        return position.doc.resolve(position.after(index + 1));
      }
      if (parent.type.spec.isolating) {
        break;
      }
    }
  }
  return null;
}

NodeType? _defaultBlockAt(ContentMatch match) {
  for (var index = 0; index < match.edgeCount; index++) {
    final type = match.edge(index).type;
    if (type.isTextblock && !type.hasRequiredAttrs()) {
      return type;
    }
  }
  return null;
}

bool _joinMaybeClear(
  EditorState state,
  ResolvedPos position,
  void Function(Transaction tr)? dispatch,
) {
  final before = position.nodeBefore;
  final after = position.nodeAfter;
  final index = position.index();
  if (before == null ||
      after == null ||
      !before.type.compatibleContent(after.type)) {
    return false;
  }
  if (before.content.size == 0 &&
      position.parent.canReplace(index - 1, index)) {
    dispatch?.call(
      (state.tr..delete(position.pos - before.nodeSize, position.pos))
          .scrollIntoView(),
    );
    return true;
  }
  if (!position.parent.canReplace(index, index + 1) ||
      !(after.isTextblock || canJoin(state.doc, position.pos))) {
    return false;
  }
  dispatch?.call((state.tr..join(position.pos)).scrollIntoView());
  return true;
}

bool _deleteBarrier(
  EditorState state,
  ResolvedPos cut,
  void Function(Transaction tr)? dispatch,
  int direction,
) {
  final before = cut.nodeBefore!;
  final after = cut.nodeAfter!;
  final isolated = before.type.spec.isolating || after.type.spec.isolating;
  if (!isolated && _joinMaybeClear(state, cut, dispatch)) {
    return true;
  }

  final canDeleteAfter =
      !isolated && cut.parent.canReplace(cut.index(), cut.index() + 1);
  final match = before.contentMatchAt(before.childCount);
  final connection = canDeleteAfter ? match.findWrapping(after.type) : null;
  final connectionType = connection != null && connection.isNotEmpty
      ? connection[0]
      : after.type;
  if (canDeleteAfter &&
      connection != null &&
      match.matchType(connectionType)!.validEnd) {
    if (dispatch != null) {
      final end = cut.pos + after.nodeSize;
      var wrap = Fragment.empty;
      for (var index = connection.length - 1; index >= 0; index--) {
        wrap = Fragment.from(connection[index].create(null, wrap));
      }
      wrap = Fragment.from(before.copy(wrap));
      final tr = state.tr.step(
        ReplaceAroundStep(
          cut.pos - 1,
          end,
          cut.pos,
          end,
          Slice(wrap, 1, 0),
          connection.length,
          true,
        ),
      ) as Transaction;
      final joinAt = tr.doc.resolve(end + 2 * connection.length);
      if (joinAt.nodeAfter != null &&
          identical(joinAt.nodeAfter!.type, before.type) &&
          canJoin(tr.doc, joinAt.pos)) {
        tr.join(joinAt.pos);
      }
      dispatch(tr.scrollIntoView());
    }
    return true;
  }

  final selectionAfter =
      after.type.spec.isolating || (direction > 0 && isolated)
      ? null
      : Selection.findFrom(cut, 1);
  final range = selectionAfter?.$from.blockRange(selectionAfter.$to);
  final target = range != null ? liftTarget(range) : null;
  if (target != null && target >= cut.depth) {
    dispatch?.call((state.tr..lift(range!, target)).scrollIntoView());
    return true;
  }

  if (canDeleteAfter &&
      _textblockAt(after, _BlockSide.start, true) &&
      _textblockAt(before, _BlockSide.end)) {
    var at = before;
    final wrap = <Node>[];
    for (;;) {
      wrap.add(at);
      if (at.isTextblock) {
        break;
      }
      at = at.lastChild!;
    }
    var afterText = after;
    var afterDepth = 1;
    for (; !afterText.isTextblock; afterDepth++) {
      afterText = afterText.firstChild!;
    }
    if (at.canReplace(at.childCount, at.childCount, afterText.content)) {
      if (dispatch != null) {
        var end = Fragment.empty;
        for (var index = wrap.length - 1; index >= 0; index--) {
          end = Fragment.from(wrap[index].copy(end));
        }
        final tr = state.tr.step(
          ReplaceAroundStep(
            cut.pos - wrap.length,
            cut.pos + after.nodeSize,
            cut.pos + afterDepth,
            cut.pos + after.nodeSize - afterDepth,
            Slice(end, wrap.length, 0),
            0,
            true,
          ),
        ) as Transaction;
        dispatch(tr.scrollIntoView());
      }
      return true;
    }
  }

  return false;
}

Command _selectTextblockSide(int side) {
  return _SelectTextblockSideCommand(side);
}

class _SelectTextblockSideCommand implements Command {
  _SelectTextblockSideCommand(this.side);

  final int side;

  @override
  bool execute(
    EditorState state, [
    void Function(Transaction tr)? dispatch,
    Object? view,
  ]) {
    final selection = state.selection;
    final position = side < 0 ? selection.$from : selection.$to;
    var depth = position.depth;
    while (position.node(depth).isInline) {
      if (depth == 0) {
        return false;
      }
      depth--;
    }
    if (!position.node(depth).isTextblock) {
      return false;
    }
    dispatch?.call(
      state.tr.setSelection(
        TextSelection.create(
          state.doc,
          side < 0 ? position.start(depth) : position.end(depth),
        ),
      ),
    );
    return true;
  }
}

bool _markApplies(
  Node doc,
  List<SelectionRange> ranges,
  MarkType type,
  bool enterAtoms,
) {
  for (final range in ranges) {
    var can =
        range.$from.depth == 0 &&
        doc.inlineContent &&
        doc.type.allowsMarkType(type);
    doc.nodesBetween(range.$from.pos, range.$to.pos, (
      node,
      pos,
      parent,
      index,
    ) {
      if (can ||
          (!enterAtoms &&
              node.isAtom &&
              node.isInline &&
              pos >= range.$from.pos &&
              pos + node.nodeSize <= range.$to.pos)) {
        return false;
      }
      can = node.inlineContent && node.type.allowsMarkType(type);
      return null;
    });
    if (can) {
      return true;
    }
  }
  return false;
}

List<SelectionRange> _removeInlineAtoms(List<SelectionRange> ranges) {
  final result = <SelectionRange>[];
  for (final range in ranges) {
    var from = range.$from;
    final to = range.$to;
    from.doc.nodesBetween(from.pos, to.pos, (node, pos, parent, index) {
      if (node.isAtom &&
          node.content.size != 0 &&
          node.isInline &&
          pos >= from.pos &&
          pos + node.nodeSize <= to.pos) {
        if (pos + 1 > from.pos) {
          result.add(SelectionRange(from, from.doc.resolve(pos + 1)));
        }
        from = from.doc.resolve(pos + 1 + node.content.size);
        return false;
      }
      return null;
    });
    if (from.pos < to.pos) {
      result.add(SelectionRange(from, to));
    }
  }
  return result;
}

class _JoinDispatch {
  _JoinDispatch(this.dispatchTransaction, this.isJoinable);

  final void Function(Transaction tr) dispatchTransaction;
  final _AutoJoinPredicate isJoinable;

  void dispatch(Transaction tr) {
    if (!tr.isGeneric) {
      dispatchTransaction(tr);
      return;
    }

    final ranges = <int>[];
    for (final map in tr.mapping.maps) {
      for (var index = 0; index < ranges.length; index++) {
        ranges[index] = map.map(ranges[index]);
      }
      map.forEach((oldStart, oldEnd, from, to) {
        ranges.add(from);
        ranges.add(to);
      });
    }

    final joinable = <int>[];
    for (var rangeIndex = 0; rangeIndex < ranges.length; rangeIndex += 2) {
      final from = ranges[rangeIndex];
      final to = ranges[rangeIndex + 1];
      final resolvedFrom = tr.doc.resolve(from);
      final depth = resolvedFrom.sharedDepth(to);
      final parent = resolvedFrom.node(depth);
      var index = resolvedFrom.indexAfter(depth);
      var pos = resolvedFrom.after(depth + 1);
      while (pos <= to) {
        final after = parent.maybeChild(index);
        if (after == null) {
          break;
        }
        if (index != 0 && !joinable.contains(pos)) {
          final before = parent.child(index - 1);
          if (identical(before.type, after.type) &&
              isJoinable.matches(before, after)) {
            joinable.add(pos);
          }
        }
        pos += after.nodeSize;
        index++;
      }
    }

    joinable.sort();
    for (var index = joinable.length - 1; index >= 0; index--) {
      if (canJoin(tr.doc, joinable[index])) {
        tr.join(joinable[index]);
      }
    }
    dispatchTransaction(tr);
  }
}

bool _canSplitNullable(
  Node doc,
  int pos,
  int depth,
  List<NodeTypeWithAttributes?> types,
) {
  return canSplit(doc, pos, depth, types);
}

int _leadingWhitespace(String text) {
  final match = _leadingWhitespaceRegExp.firstMatch(text);
  return match?.group(0)?.length ?? 0;
}

int _trailingWhitespace(String text) {
  final match = _trailingWhitespaceRegExp.firstMatch(text);
  return match?.group(0)?.length ?? 0;
}
