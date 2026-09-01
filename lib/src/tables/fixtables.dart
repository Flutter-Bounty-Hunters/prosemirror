// This file defines helpers for normalizing tables, making sure no cells
// overlap (which can happen, if you have the wrong col- and rowspans) and that
// each row has the same width. Uses the problems reported by `TableMap`.

import 'dart:math' as math;

import 'package:prosemirror/prosemirror.dart';

import 'package:prosemirror/src/tables/schema.dart';
import 'package:prosemirror/src/tables/tablemap.dart';
import 'package:prosemirror/src/tables/util.dart';

/// Plugin key used by the table fixing logic.
final PluginKey fixTablesKey = PluginKey("fix-tables");

/// Helper for iterating through the nodes in a document that changed compared
/// to the given previous document.
void _changedDescendants(Node old, Node cur, int offset, NodesBetweenCallback f) {
  final oldSize = old.childCount;
  final curSize = cur.childCount;
  outer:
  for (var i = 0, j = 0; i < curSize; i++) {
    final child = cur.child(i);
    for (var scan = j, e = math.min(oldSize, i + 3); scan < e; scan++) {
      if (identical(old.child(scan), child)) {
        j = scan + 1;
        offset += child.nodeSize;
        continue outer;
      }
    }
    f(child, offset, null, 0);
    if (j < oldSize && old.child(j).sameMarkup(child)) {
      _changedDescendants(old.child(j), child, offset + 1, f);
    } else {
      child.nodesBetween(0, child.content.size, f, offset + 1);
    }
    offset += child.nodeSize;
  }
}

/// Inspect all tables in the given state's document and return a transaction
/// that fixes them, if necessary. If [oldState] was provided, that is assumed
/// to hold a previous, known-good state, which will be used to avoid
/// re-scanning unchanged parts of the document.
Transaction? fixTables(EditorState state, [EditorState? oldState]) {
  Transaction? tr;
  if (oldState == null) {
    state.doc.descendants((node, pos, parent, index) {
      if (tableRoleOf(node.type) == TableRole.table) {
        tr = fixTable(state, node, pos, tr);
      }
      return null;
    });
  } else if (!identical(oldState.doc, state.doc)) {
    _changedDescendants(oldState.doc, state.doc, 0, (node, pos, parent, index) {
      if (tableRoleOf(node.type) == TableRole.table) {
        tr = fixTable(state, node, pos, tr);
      }
      return null;
    });
  }
  return tr;
}

/// Fix the given table, if necessary. Will append to the transaction it was
/// given, if non-null, or create a new one if necessary.
Transaction? fixTable(EditorState state, Node table, int tablePos, Transaction? tr) {
  final map = TableMap.get(table);
  final problems = map.problems;
  if (problems == null) {
    return tr;
  }
  tr ??= state.tr;

  // Track which rows we must add cells to, so that we can adjust that when
  // fixing collisions.
  final mustAdd = <int>[];
  for (var i = 0; i < map.height; i++) {
    mustAdd.add(0);
  }
  for (var i = 0; i < problems.length; i++) {
    final prob = problems[i];
    if (prob is CollisionProblem) {
      final cell = table.nodeAt(prob.pos);
      if (cell == null) {
        continue;
      }
      final attrs = cell.attrs;
      for (var j = 0; j < (attrs["rowspan"] as int); j++) {
        mustAdd[prob.row + j] += prob.n;
      }
      tr.setNodeMarkup(
        tr.mapping.map(tablePos + 1 + prob.pos),
        null,
        removeColSpan(attrs, (attrs["colspan"] as int) - prob.n, prob.n),
      );
    } else if (prob is MissingProblem) {
      mustAdd[prob.row] += prob.n;
    } else if (prob is OverlongRowspanProblem) {
      final cell = table.nodeAt(prob.pos);
      if (cell == null) {
        continue;
      }
      tr.setNodeMarkup(tr.mapping.map(tablePos + 1 + prob.pos), null, <String, Object?>{
        ...cell.attrs,
        "rowspan": (cell.attrs["rowspan"] as int) - prob.n,
      });
    } else if (prob is ColwidthMismatchProblem) {
      final cell = table.nodeAt(prob.pos);
      if (cell == null) {
        continue;
      }
      tr.setNodeMarkup(tr.mapping.map(tablePos + 1 + prob.pos), null, <String, Object?>{
        ...cell.attrs,
        "colwidth": prob.colwidth,
      });
    } else if (prob is ZeroSizedProblem) {
      final pos = tr.mapping.map(tablePos);
      tr.delete(pos, pos + table.nodeSize);
    }
  }
  int? first;
  int? last;
  for (var i = 0; i < mustAdd.length; i++) {
    if (mustAdd[i] != 0) {
      first ??= i;
      last = i;
    }
  }
  // Add the necessary cells, using a heuristic for whether to add the cells at
  // the start or end of the rows.
  for (var i = 0, pos = tablePos + 1; i < map.height; i++) {
    final row = table.child(i);
    final end = pos + row.nodeSize;
    final add = mustAdd[i];
    if (add > 0) {
      var role = TableRole.cell;
      if (row.firstChild != null) {
        role = tableRoleOf(row.firstChild!.type)!;
      }
      final nodes = <Node>[];
      for (var j = 0; j < add; j++) {
        final node = tableNodeTypes(state.schema)[role]!.createAndFill();
        if (node != null) {
          nodes.add(node);
        }
      }
      final side = (i == 0 || first == i - 1) && last == i ? pos + 1 : end - 1;
      tr.insert(tr.mapping.map(side), nodes);
    }
    pos = end;
  }
  return tr.setMeta(fixTablesKey, <String, Object?>{"fixTables": true});
}
