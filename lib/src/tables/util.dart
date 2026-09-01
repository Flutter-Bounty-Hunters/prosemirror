// Various helper functions for working with tables.

import 'package:prosemirror/prosemirror.dart';

import 'package:prosemirror/src/tables/cellselection.dart';
import 'package:prosemirror/src/tables/schema.dart';
import 'package:prosemirror/src/tables/tablemap.dart';

/// A mutable attribute object.
typedef MutableAttrs = Map<String, Object?>;

/// The attributes stored on a table cell.
typedef CellAttrs = Map<String, Object?>;

/// Plugin key used to track ongoing cell selections.
final PluginKey tableEditingKey = PluginKey("selectingCells");

/// Returns the resolved position in front of the cell wrapping [$pos], if any.
ResolvedPos? cellAround(ResolvedPos $pos) {
  for (var d = $pos.depth - 1; d > 0; d--) {
    if (tableRoleOf($pos.node(d).type) == TableRole.row) {
      return $pos.node(0).resolve($pos.before(d + 1));
    }
  }
  return null;
}

/// Returns the cell node wrapping [$pos], if any.
Node? cellWrapping(ResolvedPos $pos) {
  for (var d = $pos.depth; d > 0; d--) {
    // Sometimes the cell can be in the same depth.
    final role = tableRoleOf($pos.node(d).type);
    if (role == TableRole.cell || role == TableRole.headerCell) {
      return $pos.node(d);
    }
  }
  return null;
}

/// Whether the selection in [state] is inside a table.
bool isInTable(EditorState state) {
  final $head = state.selection.$head;
  for (var d = $head.depth; d > 0; d--) {
    if (tableRoleOf($head.node(d).type) == TableRole.row) {
      return true;
    }
  }
  return false;
}

/// Returns the resolved position in front of the cell the selection is in.
ResolvedPos selectionCell(EditorState state) {
  final sel = state.selection;
  if (sel is CellSelection) {
    return sel.$anchorCell.pos > sel.$headCell.pos ? sel.$anchorCell : sel.$headCell;
  } else if (sel is NodeSelection && tableRoleOf(sel.node.type) == TableRole.cell) {
    return sel.$anchor;
  }
  final $cell = cellAround(sel.$head) ?? cellNear(sel.$head);
  if ($cell != null) {
    return $cell;
  }
  throw RangeError("No cell found around position ${sel.head}");
}

/// Returns the resolved position in front of a cell near [$pos], if any.
ResolvedPos? cellNear(ResolvedPos $pos) {
  var pos = $pos.pos;
  for (Node? after = $pos.nodeAfter; after != null; after = after.firstChild, pos++) {
    final role = tableRoleOf(after.type);
    if (role == TableRole.cell || role == TableRole.headerCell) {
      return $pos.doc.resolve(pos);
    }
  }
  pos = $pos.pos;
  for (Node? before = $pos.nodeBefore; before != null; before = before.lastChild, pos--) {
    final role = tableRoleOf(before.type);
    if (role == TableRole.cell || role == TableRole.headerCell) {
      return $pos.doc.resolve(pos - before.nodeSize);
    }
  }
  return null;
}

/// Whether [$pos] points directly in front of a cell.
bool pointsAtCell(ResolvedPos $pos) {
  return tableRoleOf($pos.parent.type) == TableRole.row && $pos.nodeAfter != null;
}

/// Returns the resolved position in front of the cell after the one [$pos]
/// points at.
ResolvedPos moveCellForward(ResolvedPos $pos) {
  return $pos.node(0).resolve($pos.pos + $pos.nodeAfter!.nodeSize);
}

/// Whether the two given cell positions are in the same table.
bool inSameTable(ResolvedPos $cellA, ResolvedPos $cellB) {
  return $cellA.depth == $cellB.depth && $cellA.pos >= $cellB.start(-1) && $cellA.pos <= $cellB.end(-1);
}

/// Returns the rectangle of the cell that [$pos] points at.
Rect findCell(ResolvedPos $pos) {
  return TableMap.get($pos.node(-1)).findCell($pos.pos - $pos.start(-1));
}

/// Returns the column index of the cell [$pos] points at.
int colCount(ResolvedPos $pos) {
  return TableMap.get($pos.node(-1)).colCount($pos.pos - $pos.start(-1));
}

/// Returns the resolved position of the next cell in the given direction, or
/// null if there is none.
ResolvedPos? nextCell(ResolvedPos $pos, String axis, int dir) {
  final table = $pos.node(-1);
  final map = TableMap.get(table);
  final tableStart = $pos.start(-1);

  final moved = map.nextCell($pos.pos - tableStart, axis, dir);
  return moved == null ? null : $pos.node(0).resolve(tableStart + moved);
}

/// Returns a copy of [attrs] with the colspan reduced by [n] columns starting
/// at [pos].
CellAttrs removeColSpan(CellAttrs attrs, int pos, [int n = 1]) {
  final result = <String, Object?>{...attrs, "colspan": (attrs["colspan"] as int) - n};
  final colwidth = result["colwidth"] as List?;
  if (colwidth != null) {
    final updated = List<int>.from(colwidth);
    updated.removeRange(pos, pos + n);
    result["colwidth"] = updated.any((w) => w > 0) ? updated : null;
  }
  return result;
}

/// Returns a copy of [attrs] with the colspan increased by [n] columns at
/// [pos].
Attrs addColSpan(CellAttrs attrs, int pos, [int n = 1]) {
  final result = <String, Object?>{...attrs, "colspan": (attrs["colspan"] as int) + n};
  final colwidth = result["colwidth"] as List?;
  if (colwidth != null) {
    final updated = List<int>.from(colwidth);
    for (var i = 0; i < n; i++) {
      updated.insert(pos, 0);
    }
    result["colwidth"] = updated;
  }
  return result;
}

/// Whether the column at index [col] consists entirely of header cells.
bool columnIsHeader(TableMap map, Node table, int col) {
  final headerCell = tableNodeTypes(table.type.schema)[TableRole.headerCell];
  for (var row = 0; row < map.height; row++) {
    if (table.nodeAt(map.map[col + row * map.width])!.type != headerCell) {
      return false;
    }
  }
  return true;
}
