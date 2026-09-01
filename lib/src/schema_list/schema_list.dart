import 'package:prosemirror/prosemirror.dart';

/// An ordered list [node spec](NodeSpec). Has a single attribute, `order`,
/// which determines the number at which the list starts counting, and defaults
/// to 1.
final NodeSpec orderedList = NodeSpec(attrs: {"order": AttributeSpec(defaultValue: 1, validate: "number")});

/// A bullet list node spec.
final NodeSpec bulletList = NodeSpec();

/// A list item spec.
final NodeSpec listItem = NodeSpec(defining: true);

/// Convenience function for adding list-related node types to a map specifying
/// the nodes for a schema. Adds [orderedList] as `"ordered_list"`, [bulletList]
/// as `"bullet_list"`, and [listItem] as `"list_item"`.
///
/// `itemContent` determines the content expression for the list items. If you
/// want the commands defined in this module to apply to your list structure, it
/// should have a shape like `"paragraph block*"` or
/// `"paragraph (ordered_list | bullet_list)*"`. `listGroup` can be given to
/// assign a group name to the list node types, for example `"block"`.
OrderedMap<NodeSpec> addListNodes(OrderedMap<NodeSpec> nodes, String itemContent, [String? listGroup]) {
  return nodes.append({
    "ordered_list": NodeSpec(
      attrs: {"order": AttributeSpec(defaultValue: 1, validate: "number")},
      content: "list_item+",
      group: listGroup,
    ),
    "bullet_list": NodeSpec(content: "list_item+", group: listGroup),
    "list_item": NodeSpec(content: itemContent, defining: true),
  });
}

/// Returns a command function that wraps the selection in a list with the given
/// type and attributes. If `dispatch` is null, only return a value to indicate
/// whether this is possible, but don't actually perform the change.
Command wrapInList(NodeType listType, [Attrs? attrs]) {
  return FunctionCommand((state, [dispatch, view]) {
    final $from = state.selection.$from;
    final $to = state.selection.$to;
    final range = $from.blockRange($to);
    if (range == null) {
      return false;
    }
    final tr = dispatch != null ? state.tr : null;
    if (!wrapRangeInList(tr, range, listType, attrs)) {
      return false;
    }
    if (dispatch != null) {
      dispatch(tr!.scrollIntoView());
    }
    return true;
  });
}

/// Try to wrap the given node range in a list of the given type. Return `true`
/// when this is possible, `false` otherwise. When `tr` is non-null, the
/// wrapping is added to that transaction. When it is `null`, the function only
/// queries whether the wrapping is possible.
bool wrapRangeInList(Transaction? tr, NodeRange range, NodeType listType, [Attrs? attrs]) {
  var doJoin = false;
  var outerRange = range;
  final document = range.$from.doc;
  // This is at the top of an existing list item
  if (range.depth >= 2 && range.$from.node(range.depth - 1).type.compatibleContent(listType) && range.startIndex == 0) {
    // Don't do anything if this is the top of the list
    if (range.$from.index(range.depth - 1) == 0) {
      return false;
    }
    final $insert = document.resolve(range.start - 2);
    outerRange = NodeRange($insert, $insert, range.depth);
    if (range.endIndex < range.parent.childCount) {
      range = NodeRange(range.$from, document.resolve(range.$to.end(range.depth)), range.depth);
    }
    doJoin = true;
  }
  final wrap = findWrapping(outerRange, listType, attrs, range);
  if (wrap == null) {
    return false;
  }
  if (tr != null) {
    _doWrapInList(tr, range, wrap, doJoin, listType);
  }
  return true;
}

void _doWrapInList(
  Transaction tr,
  NodeRange range,
  List<NodeTypeWithAttributes> wrappers,
  bool joinBefore,
  NodeType listType,
) {
  var content = Fragment.empty;
  for (var index = wrappers.length - 1; index >= 0; index--) {
    content = Fragment.from(wrappers[index].type.create(wrappers[index].attrs, content));
  }

  tr.step(
    ReplaceAroundStep(
      range.start - (joinBefore ? 2 : 0),
      range.end,
      range.start,
      range.end,
      Slice(content, 0, 0),
      wrappers.length,
      true,
    ),
  );

  var found = 0;
  for (var index = 0; index < wrappers.length; index++) {
    if (wrappers[index].type == listType) {
      found = index + 1;
    }
  }
  final splitDepth = wrappers.length - found;

  var splitPos = range.start + wrappers.length - (joinBefore ? 2 : 0);
  final parent = range.parent;
  var first = true;
  for (var index = range.startIndex; index < range.endIndex; index++) {
    if (!first && canSplit(tr.doc, splitPos, splitDepth)) {
      tr.split(splitPos, splitDepth);
      splitPos += 2 * splitDepth;
    }
    splitPos += parent.child(index).nodeSize;
    first = false;
  }
}

/// Build a command that splits a non-empty textblock at the top level of a list
/// item by also splitting that list item.
Command splitListItem(NodeType itemType, [Attrs? itemAttrs]) {
  return FunctionCommand((state, [dispatch, view]) {
    final selection = state.selection;
    final $from = selection.$from;
    final $to = selection.$to;
    final node = selection is NodeSelection ? selection.node : null;
    if ((node != null && node.isBlock) || $from.depth < 2 || !$from.sameParent($to)) {
      return false;
    }
    final grandParent = $from.node(-1);
    if (grandParent.type != itemType) {
      return false;
    }
    if ($from.parent.content.size == 0 && $from.node(-1).childCount == $from.indexAfter(-1)) {
      // In an empty block. If this is a nested list, the wrapping list item
      // should be split. Otherwise, bail out and let next command handle
      // lifting.
      if ($from.depth == 3 || $from.node(-3).type != itemType || $from.index(-2) != $from.node(-2).childCount - 1) {
        return false;
      }
      if (dispatch != null) {
        var wrap = Fragment.empty;
        final depthBefore = $from.index(-1) != 0
            ? 1
            : $from.index(-2) != 0
            ? 2
            : 3;
        // Build a fragment containing empty versions of the structure from the
        // outer list item to the parent node of the cursor.
        for (var depth = $from.depth - depthBefore; depth >= $from.depth - 3; depth--) {
          wrap = Fragment.from($from.node(depth).copy(wrap));
        }
        final depthAfter = $from.indexAfter(-1) < $from.node(-2).childCount
            ? 1
            : $from.indexAfter(-2) < $from.node(-3).childCount
            ? 2
            : 3;
        // Add a second list item with an empty default start node.
        wrap = wrap.append(Fragment.from(itemType.createAndFill()));
        final start = $from.before($from.depth - (depthBefore - 1));
        final tr = state.tr;
        tr.replace(start, $from.after(-depthAfter), Slice(wrap, 4 - depthBefore, 0));
        var selectionPos = -1;
        tr.doc.nodesBetween(start, tr.doc.content.size, (descendant, pos, parent, index) {
          if (selectionPos > -1) {
            return false;
          }
          if (descendant.isTextblock && descendant.content.size == 0) {
            selectionPos = pos + 1;
          }
          return null;
        });
        if (selectionPos > -1) {
          tr.setSelection(Selection.near(tr.doc.resolve(selectionPos)));
        }
        dispatch(tr.scrollIntoView());
      }
      return true;
    }
    final nextType = $to.pos == $from.end() ? grandParent.contentMatchAt(0).defaultType : null;
    final tr = state.tr;
    tr.delete($from.pos, $to.pos);
    final types = nextType != null
        ? <NodeTypeWithAttributes?>[
            itemAttrs != null ? (type: itemType, attrs: itemAttrs) : null,
            (type: nextType, attrs: null),
          ]
        : null;
    if (!canSplit(tr.doc, $from.pos, 2, types)) {
      return false;
    }
    if (dispatch != null) {
      tr.split($from.pos, 2, types);
      dispatch(tr.scrollIntoView());
    }
    return true;
  });
}

/// Acts like [splitListItem], but without resetting the set of active marks at
/// the cursor.
Command splitListItemKeepMarks(NodeType itemType, [Attrs? itemAttrs]) {
  final split = splitListItem(itemType, itemAttrs);
  return FunctionCommand((state, [dispatch, view]) {
    return split.execute(
      state,
      dispatch == null
          ? null
          : (tr) {
              final marks =
                  state.storedMarks ?? (state.selection.$to.parentOffset != 0 ? state.selection.$from.marks() : null);
              if (marks != null) {
                tr.ensureMarks(marks);
              }
              dispatch(tr);
            },
    );
  });
}

/// Create a command to lift the list item around the selection up into a
/// wrapping list.
Command liftListItem(NodeType itemType) {
  return FunctionCommand((state, [dispatch, view]) {
    final $from = state.selection.$from;
    final $to = state.selection.$to;
    final range = $from.blockRange($to, (node) => node.childCount > 0 && node.firstChild!.type == itemType);
    if (range == null) {
      return false;
    }
    if (dispatch == null) {
      return true;
    }
    if ($from.node(range.depth - 1).type == itemType) {
      // Inside a parent list
      return _liftToOuterList(state, dispatch, itemType, range);
    } else {
      // Outer list node
      return _liftOutOfList(state, dispatch, range);
    }
  });
}

bool _liftToOuterList(EditorState state, void Function(Transaction) dispatch, NodeType itemType, NodeRange range) {
  final tr = state.tr;
  final end = range.end;
  final endOfList = range.$to.end(range.depth);
  if (end < endOfList) {
    // There are siblings after the lifted items, which must become children of
    // the last item.
    tr.step(
      ReplaceAroundStep(
        end - 1,
        endOfList,
        end,
        endOfList,
        Slice(Fragment.from(itemType.create(null, range.parent.copy())), 1, 0),
        1,
        true,
      ),
    );
    range = NodeRange(tr.doc.resolve(range.$from.pos), tr.doc.resolve(endOfList), range.depth);
  }
  final target = liftTarget(range);
  if (target == null) {
    return false;
  }
  tr.lift(range, target);
  final $after = tr.doc.resolve(tr.mapping.map(end, -1) - 1);
  if (canJoin(tr.doc, $after.pos) && $after.nodeBefore!.type == $after.nodeAfter!.type) {
    tr.join($after.pos);
  }
  dispatch(tr.scrollIntoView());
  return true;
}

bool _liftOutOfList(EditorState state, void Function(Transaction) dispatch, NodeRange range) {
  final tr = state.tr;
  final list = range.parent;
  // Merge the list items into a single big item.
  var pos = range.end;
  for (var index = range.endIndex - 1; index > range.startIndex; index--) {
    pos -= list.child(index).nodeSize;
    tr.delete(pos - 1, pos + 1);
  }
  final $start = tr.doc.resolve(range.start);
  final item = $start.nodeAfter!;
  if (tr.mapping.map(range.end) != range.start + $start.nodeAfter!.nodeSize) {
    return false;
  }
  final atStart = range.startIndex == 0;
  final atEnd = range.endIndex == list.childCount;
  final parent = $start.node(-1);
  final indexBefore = $start.index(-1);
  if (!parent.canReplace(
    indexBefore + (atStart ? 0 : 1),
    indexBefore + 1,
    item.content.append(atEnd ? Fragment.empty : Fragment.from(list)),
  )) {
    return false;
  }
  final start = $start.pos;
  final end = start + item.nodeSize;
  // Strip off the surrounding list. At the sides where we're not at the end of
  // the list, the existing list is closed. At sides where this is the end, it
  // is overwritten to its end.
  tr.step(
    ReplaceAroundStep(
      start - (atStart ? 1 : 0),
      end + (atEnd ? 1 : 0),
      start + 1,
      end - 1,
      Slice(
        (atStart ? Fragment.empty : Fragment.from(list.copy(Fragment.empty))).append(
          atEnd ? Fragment.empty : Fragment.from(list.copy(Fragment.empty)),
        ),
        atStart ? 0 : 1,
        atEnd ? 0 : 1,
      ),
      atStart ? 0 : 1,
    ),
  );
  dispatch(tr.scrollIntoView());
  return true;
}

/// Create a command to sink the list item around the selection down into an
/// inner list.
Command sinkListItem(NodeType itemType) {
  return FunctionCommand((state, [dispatch, view]) {
    final $from = state.selection.$from;
    final $to = state.selection.$to;
    final range = $from.blockRange($to, (node) => node.childCount > 0 && node.firstChild!.type == itemType);
    if (range == null) {
      return false;
    }
    final startIndex = range.startIndex;
    if (startIndex == 0) {
      return false;
    }
    final parent = range.parent;
    final nodeBefore = parent.child(startIndex - 1);
    if (nodeBefore.type != itemType) {
      return false;
    }

    if (dispatch != null) {
      final nestedBefore = nodeBefore.lastChild != null && nodeBefore.lastChild!.type == parent.type;
      final inner = Fragment.from(nestedBefore ? itemType.create() : null);
      final slice = Slice(
        Fragment.from(itemType.create(null, Fragment.from(parent.type.create(null, inner)))),
        nestedBefore ? 3 : 1,
        0,
      );
      final before = range.start;
      final after = range.end;
      final tr = state.tr;
      tr.step(ReplaceAroundStep(before - (nestedBefore ? 3 : 1), after, before, after, slice, 1, true));
      dispatch(tr.scrollIntoView());
    }
    return true;
  });
}
