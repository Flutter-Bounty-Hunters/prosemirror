// This file defines a number of table-related commands.

import 'package:prosemirror/prosemirror.dart';

import 'package:prosemirror/src/tables/cellselection.dart';
import 'package:prosemirror/src/tables/schema.dart';
import 'package:prosemirror/src/tables/tablemap.dart';
import 'package:prosemirror/src/tables/util.dart';
import 'package:prosemirror/src/tables/utils/move_column.dart';
import 'package:prosemirror/src/tables/utils/move_row.dart';

/// A selected rectangle in a table. Adds table map, table node, and table start
/// offset for convenience.
class TableRect extends Rect {
  TableRect({
    required super.left,
    required super.top,
    required super.right,
    required super.bottom,
    required this.tableStart,
    required this.map,
    required this.table,
  });

  int tableStart;
  TableMap map;
  Node table;
}

/// Helper to get the selected rectangle in a table, if any.
TableRect selectedRect(EditorState state) {
  final sel = state.selection;
  final $pos = selectionCell(state);
  final table = $pos.node(-1);
  final tableStart = $pos.start(-1);
  final map = TableMap.get(table);
  final Rect rect = sel is CellSelection
      ? map.rectBetween(sel.$anchorCell.pos - tableStart, sel.$headCell.pos - tableStart)
      : map.findCell($pos.pos - tableStart);
  return TableRect(
    left: rect.left,
    top: rect.top,
    right: rect.right,
    bottom: rect.bottom,
    tableStart: tableStart,
    map: map,
    table: table,
  );
}

/// Add a column at the given position in a table.
Transaction addColumn(Transaction tr, TableRect rect, int col) {
  final map = rect.map;
  final table = rect.table;
  final tableStart = rect.tableStart;
  int? refColumn = col > 0 ? -1 : 0;
  if (columnIsHeader(map, table, col + refColumn)) {
    refColumn = col == 0 || col == map.width ? null : 0;
  }

  for (var row = 0; row < map.height; row++) {
    final index = row * map.width + col;
    // If this position falls inside a col-spanning cell.
    if (col > 0 && col < map.width && map.map[index - 1] == map.map[index]) {
      final pos = map.map[index];
      final cell = table.nodeAt(pos)!;
      tr.setNodeMarkup(tr.mapping.map(tableStart + pos), null, addColSpan(cell.attrs, col - map.colCount(pos)));
      // Skip ahead if rowspan > 1.
      row += (cell.attrs["rowspan"] as int) - 1;
    } else {
      final NodeType type = refColumn == null
          ? tableNodeTypes(table.type.schema)[TableRole.cell]!
          : table.nodeAt(map.map[index + refColumn])!.type;
      final pos = map.positionAt(row, col, table);
      tr.insert(tr.mapping.map(tableStart + pos), type.createAndFill()!);
    }
  }
  return tr;
}

/// Command to add a column before the column with the selection.
final Command addColumnBefore = FunctionCommand((state, [dispatch, view]) {
  if (!isInTable(state)) {
    return false;
  }
  if (dispatch != null) {
    final rect = selectedRect(state);
    dispatch(addColumn(state.tr, rect, rect.left));
  }
  return true;
});

/// Command to add a column after the column with the selection.
final Command addColumnAfter = FunctionCommand((state, [dispatch, view]) {
  if (!isInTable(state)) {
    return false;
  }
  if (dispatch != null) {
    final rect = selectedRect(state);
    dispatch(addColumn(state.tr, rect, rect.right));
  }
  return true;
});

/// Remove the column at [col] from the table described by [rect].
void removeColumn(Transaction tr, TableRect rect, int col) {
  final map = rect.map;
  final table = rect.table;
  final tableStart = rect.tableStart;
  final mapStart = tr.mapping.maps.length;
  for (var row = 0; row < map.height;) {
    final index = row * map.width + col;
    final pos = map.map[index];
    final cell = table.nodeAt(pos)!;
    final attrs = cell.attrs;
    // If this is part of a col-spanning cell.
    if ((col > 0 && map.map[index - 1] == pos) || (col < map.width - 1 && map.map[index + 1] == pos)) {
      tr.setNodeMarkup(
        tr.mapping.slice(mapStart).map(tableStart + pos),
        null,
        removeColSpan(attrs, col - map.colCount(pos)),
      );
    } else {
      final start = tr.mapping.slice(mapStart).map(tableStart + pos);
      tr.delete(start, start + cell.nodeSize);
    }
    row += attrs["rowspan"] as int;
  }
}

/// Command function that removes the selected columns from a table.
final Command deleteColumn = FunctionCommand((state, [dispatch, view]) {
  if (!isInTable(state)) {
    return false;
  }
  if (dispatch != null) {
    final rect = selectedRect(state);
    final tr = state.tr;
    if (rect.left == 0 && rect.right == rect.map.width) {
      return false;
    }
    for (var i = rect.right - 1; ; i--) {
      removeColumn(tr, rect, i);
      if (i == rect.left) {
        break;
      }
      final table = rect.tableStart != 0 ? tr.doc.nodeAt(rect.tableStart - 1) : tr.doc;
      if (table == null) {
        throw RangeError("No table found");
      }
      rect.table = table;
      rect.map = TableMap.get(table);
    }
    dispatch(tr);
  }
  return true;
});

/// Whether the row at index [row] consists entirely of header cells.
bool rowIsHeader(TableMap map, Node table, int row) {
  final headerCell = tableNodeTypes(table.type.schema)[TableRole.headerCell];
  for (var col = 0; col < map.width; col++) {
    if (table.nodeAt(map.map[col + row * map.width])?.type != headerCell) {
      return false;
    }
  }
  return true;
}

/// Add a row at the given position in a table.
Transaction addRow(Transaction tr, TableRect rect, int row) {
  final map = rect.map;
  final table = rect.table;
  final tableStart = rect.tableStart;
  var rowPos = tableStart;
  for (var i = 0; i < row; i++) {
    rowPos += table.child(i).nodeSize;
  }
  final cells = <Node>[];
  int? refRow = row > 0 ? -1 : 0;
  if (rowIsHeader(map, table, row + refRow)) {
    refRow = row == 0 || row == map.height ? null : 0;
  }
  for (var col = 0, index = map.width * row; col < map.width; col++, index++) {
    // Covered by a rowspan cell.
    if (row > 0 && row < map.height && map.map[index] == map.map[index - map.width]) {
      final pos = map.map[index];
      final attrs = table.nodeAt(pos)!.attrs;
      tr.setNodeMarkup(tableStart + pos, null, <String, Object?>{...attrs, "rowspan": (attrs["rowspan"] as int) + 1});
      col += (attrs["colspan"] as int) - 1;
    } else {
      final NodeType? type = refRow == null
          ? tableNodeTypes(table.type.schema)[TableRole.cell]
          : table.nodeAt(map.map[index + refRow * map.width])?.type;
      final node = type?.createAndFill();
      if (node != null) {
        cells.add(node);
      }
    }
  }
  tr.insert(rowPos, tableNodeTypes(table.type.schema)[TableRole.row]!.create(null, cells));
  return tr;
}

/// Add a table row before the selection.
final Command addRowBefore = FunctionCommand((state, [dispatch, view]) {
  if (!isInTable(state)) {
    return false;
  }
  if (dispatch != null) {
    final rect = selectedRect(state);
    dispatch(addRow(state.tr, rect, rect.top));
  }
  return true;
});

/// Add a table row after the selection.
final Command addRowAfter = FunctionCommand((state, [dispatch, view]) {
  if (!isInTable(state)) {
    return false;
  }
  if (dispatch != null) {
    final rect = selectedRect(state);
    dispatch(addRow(state.tr, rect, rect.bottom));
  }
  return true;
});

/// Remove the row at [row] from the table described by [rect].
void removeRow(Transaction tr, TableRect rect, int row) {
  final map = rect.map;
  final table = rect.table;
  final tableStart = rect.tableStart;
  var rowPos = 0;
  for (var i = 0; i < row; i++) {
    rowPos += table.child(i).nodeSize;
  }
  final nextRow = rowPos + table.child(row).nodeSize;

  final mapFrom = tr.mapping.maps.length;
  tr.delete(rowPos + tableStart, nextRow + tableStart);

  final seen = <int>{};

  for (var col = 0, index = row * map.width; col < map.width; col++, index++) {
    final pos = map.map[index];

    // Skip cells that are checked already.
    if (seen.contains(pos)) {
      continue;
    }
    seen.add(pos);

    if (row > 0 && pos == map.map[index - map.width]) {
      // If this cell starts in the row above, simply reduce its rowspan.
      final attrs = table.nodeAt(pos)!.attrs;
      tr.setNodeMarkup(tr.mapping.slice(mapFrom).map(pos + tableStart), null, <String, Object?>{
        ...attrs,
        "rowspan": (attrs["rowspan"] as int) - 1,
      });
      col += (attrs["colspan"] as int) - 1;
    } else if (row < map.height && index + map.width < map.map.length && pos == map.map[index + map.width]) {
      // Else, if it continues in the row below, it has to be moved down.
      final cell = table.nodeAt(pos)!;
      final attrs = cell.attrs;
      final copy = cell.type.create(<String, Object?>{
        ...attrs,
        "rowspan": (attrs["rowspan"] as int) - 1,
      }, cell.content);
      final newPos = map.positionAt(row + 1, col, table);
      tr.insert(tr.mapping.slice(mapFrom).map(tableStart + newPos), copy);
      col += (attrs["colspan"] as int) - 1;
    }
  }
}

/// Remove the selected rows from a table.
final Command deleteRow = FunctionCommand((state, [dispatch, view]) {
  if (!isInTable(state)) {
    return false;
  }
  if (dispatch != null) {
    final rect = selectedRect(state);
    final tr = state.tr;
    if (rect.top == 0 && rect.bottom == rect.map.height) {
      return false;
    }
    for (var i = rect.bottom - 1; ; i--) {
      removeRow(tr, rect, i);
      if (i == rect.top) {
        break;
      }
      final table = rect.tableStart != 0 ? tr.doc.nodeAt(rect.tableStart - 1) : tr.doc;
      if (table == null) {
        throw RangeError("No table found");
      }
      rect.table = table;
      rect.map = TableMap.get(rect.table);
    }
    dispatch(tr);
  }
  return true;
});

bool _isEmpty(Node cell) {
  final content = cell.content;
  return content.childCount == 1 && content.child(0).isTextblock && content.child(0).childCount == 0;
}

bool _cellsOverlapRectangle(TableMap map, Rect rect) {
  final width = map.width;
  final height = map.height;
  final mapList = map.map;
  var indexTop = rect.top * width + rect.left;
  var indexLeft = indexTop;
  var indexBottom = (rect.bottom - 1) * width + rect.left;
  var indexRight = indexTop + (rect.right - rect.left - 1);
  for (var i = rect.top; i < rect.bottom; i++) {
    if ((rect.left > 0 && mapList[indexLeft] == mapList[indexLeft - 1]) ||
        (rect.right < width && mapList[indexRight] == mapList[indexRight + 1])) {
      return true;
    }
    indexLeft += width;
    indexRight += width;
  }
  for (var i = rect.left; i < rect.right; i++) {
    if ((rect.top > 0 && mapList[indexTop] == mapList[indexTop - width]) ||
        (rect.bottom < height && mapList[indexBottom] == mapList[indexBottom + width])) {
      return true;
    }
    indexTop++;
    indexBottom++;
  }
  return false;
}

/// Merge the selected cells into a single cell.
final Command mergeCells = FunctionCommand((state, [dispatch, view]) {
  final sel = state.selection;
  if (sel is! CellSelection || sel.$anchorCell.pos == sel.$headCell.pos) {
    return false;
  }
  final rect = selectedRect(state);
  final map = rect.map;
  if (_cellsOverlapRectangle(map, rect)) {
    return false;
  }
  if (dispatch != null) {
    final tr = state.tr;
    final seen = <int>{};
    var content = Fragment.empty;
    int? mergedPos;
    Node? mergedCell;
    for (var row = rect.top; row < rect.bottom; row++) {
      for (var col = rect.left; col < rect.right; col++) {
        final cellPos = map.map[row * map.width + col];
        final cell = rect.table.nodeAt(cellPos);
        if (seen.contains(cellPos) || cell == null) {
          continue;
        }
        seen.add(cellPos);
        if (mergedPos == null) {
          mergedPos = cellPos;
          mergedCell = cell;
        } else {
          if (!_isEmpty(cell)) {
            content = content.append(cell.content);
          }
          final mapped = tr.mapping.map(cellPos + rect.tableStart);
          tr.delete(mapped, mapped + cell.nodeSize);
        }
      }
    }
    if (mergedPos == null || mergedCell == null) {
      return true;
    }

    tr.setNodeMarkup(mergedPos + rect.tableStart, null, <String, Object?>{
      ...addColSpan(
        mergedCell.attrs,
        mergedCell.attrs["colspan"] as int,
        rect.right - rect.left - (mergedCell.attrs["colspan"] as int),
      ),
      "rowspan": rect.bottom - rect.top,
    });
    if (content.size > 0) {
      final end = mergedPos + 1 + mergedCell.content.size;
      final start = _isEmpty(mergedCell) ? mergedPos + 1 : end;
      tr.replaceWith(start + rect.tableStart, end + rect.tableStart, content);
    }
    tr.setSelection(CellSelection(tr.doc.resolve(mergedPos + rect.tableStart)));
    dispatch(tr);
  }
  return true;
});

/// Split a selected cell, whose rowspan or colspan is greater than one, into
/// smaller cells. Uses the first cell type for the new cells.
final Command splitCell = FunctionCommand((state, [dispatch, view]) {
  final nodeTypes = tableNodeTypes(state.schema);
  return splitCellWithType((options) {
    return nodeTypes[tableRoleOf(options.node.type)!]!;
  }).execute(state, dispatch);
});

/// Options passed to the `getCellType` callback of [splitCellWithType].
class GetCellTypeOptions {
  GetCellTypeOptions({required this.node, required this.row, required this.col});

  Node node;
  int row;
  int col;
}

/// Split a selected cell into smaller cells with the cell type returned by
/// [getCellType].
Command splitCellWithType(NodeType Function(GetCellTypeOptions options) getCellType) {
  return FunctionCommand((state, [dispatch, view]) {
    final sel = state.selection;
    Node? cellNode;
    int? cellPos;
    if (sel is! CellSelection) {
      cellNode = cellWrapping(sel.$from);
      if (cellNode == null) {
        return false;
      }
      cellPos = cellAround(sel.$from)?.pos;
    } else {
      if (sel.$anchorCell.pos != sel.$headCell.pos) {
        return false;
      }
      cellNode = sel.$anchorCell.nodeAfter;
      cellPos = sel.$anchorCell.pos;
    }
    if (cellNode == null || cellPos == null) {
      return false;
    }
    if ((cellNode.attrs["colspan"] as int) == 1 && (cellNode.attrs["rowspan"] as int) == 1) {
      return false;
    }
    if (dispatch != null) {
      var baseAttrs = cellNode.attrs;
      final attrs = <Attrs>[];
      final colwidth = baseAttrs["colwidth"] as List?;
      if ((baseAttrs["rowspan"] as int) > 1) {
        baseAttrs = <String, Object?>{...baseAttrs, "rowspan": 1};
      }
      if ((baseAttrs["colspan"] as int) > 1) {
        baseAttrs = <String, Object?>{...baseAttrs, "colspan": 1};
      }
      final rect = selectedRect(state);
      final tr = state.tr;
      for (var i = 0; i < rect.right - rect.left; i++) {
        attrs.add(
          colwidth != null
              ? <String, Object?>{
                  ...baseAttrs,
                  "colwidth": i < colwidth.length && colwidth[i] != 0 ? <int>[colwidth[i] as int] : null,
                }
              : baseAttrs,
        );
      }
      int? lastCell;
      for (var row = rect.top; row < rect.bottom; row++) {
        var pos = rect.map.positionAt(row, rect.left, rect.table);
        if (row == rect.top) {
          pos += cellNode.nodeSize;
        }
        for (var col = rect.left, i = 0; col < rect.right; col++, i++) {
          if (col == rect.left && row == rect.top) {
            continue;
          }
          lastCell = tr.mapping.map(pos + rect.tableStart, 1);
          tr.insert(
            lastCell,
            getCellType(GetCellTypeOptions(node: cellNode, row: row, col: col)).createAndFill(attrs[i])!,
          );
        }
      }
      tr.setNodeMarkup(
        cellPos,
        getCellType(GetCellTypeOptions(node: cellNode, row: rect.top, col: rect.left)),
        attrs[0],
      );
      if (sel is CellSelection) {
        tr.setSelection(
          CellSelection(tr.doc.resolve(sel.$anchorCell.pos), lastCell != null ? tr.doc.resolve(lastCell) : null),
        );
      }
      dispatch(tr);
    }
    return true;
  });
}

/// Returns a command that sets the given attribute to the given value.
Command setCellAttr(String name, Object? value) {
  return FunctionCommand((state, [dispatch, view]) {
    if (!isInTable(state)) {
      return false;
    }
    final $cell = selectionCell(state);
    if ($cell.nodeAfter!.attrs[name] == value) {
      return false;
    }
    if (dispatch != null) {
      final tr = state.tr;
      final sel = state.selection;
      if (sel is CellSelection) {
        sel.forEachCell((node, pos) {
          if (node.attrs[name] != value) {
            tr.setNodeMarkup(pos, null, <String, Object?>{...node.attrs, name: value});
          }
        });
      } else {
        tr.setNodeMarkup($cell.pos, null, <String, Object?>{...$cell.nodeAfter!.attrs, name: value});
      }
      dispatch(tr);
    }
    return true;
  });
}

Command _deprecatedToggleHeader(String type) {
  return FunctionCommand((state, [dispatch, view]) {
    if (!isInTable(state)) {
      return false;
    }
    if (dispatch != null) {
      final types = tableNodeTypes(state.schema);
      final rect = selectedRect(state);
      final tr = state.tr;
      final cells = rect.map.cellsInRect(
        type == "column"
            ? Rect(left: rect.left, top: 0, right: rect.right, bottom: rect.map.height)
            : type == "row"
            ? Rect(left: 0, top: rect.top, right: rect.map.width, bottom: rect.bottom)
            : rect,
      );
      final nodes = cells.map((pos) => rect.table.nodeAt(pos)!).toList();
      for (var i = 0; i < cells.length; i++) {
        // Remove headers, if any.
        if (nodes[i].type == types[TableRole.headerCell]) {
          tr.setNodeMarkup(rect.tableStart + cells[i], types[TableRole.cell], nodes[i].attrs);
        }
      }
      if (tr.steps.isEmpty) {
        for (var i = 0; i < cells.length; i++) {
          // No headers removed, add instead.
          tr.setNodeMarkup(rect.tableStart + cells[i], types[TableRole.headerCell], nodes[i].attrs);
        }
      }
      dispatch(tr);
    }
    return true;
  });
}

bool _isHeaderEnabledByType(String type, TableRect rect, Map<TableRole, NodeType> types) {
  // Get cell positions for first row or first column.
  final cellPositions = rect.map.cellsInRect(
    Rect(left: 0, top: 0, right: type == "row" ? rect.map.width : 1, bottom: type == "column" ? rect.map.height : 1),
  );

  for (var i = 0; i < cellPositions.length; i++) {
    final cell = rect.table.nodeAt(cellPositions[i]);
    if (cell != null && cell.type != types[TableRole.headerCell]) {
      return false;
    }
  }

  return true;
}

/// Toggles between row/column header and normal cells (only applies to first
/// row/column). For deprecated behavior pass [useDeprecatedLogic] as true.
Command toggleHeader(String type, {bool useDeprecatedLogic = false}) {
  if (useDeprecatedLogic) {
    return _deprecatedToggleHeader(type);
  }

  return FunctionCommand((state, [dispatch, view]) {
    if (!isInTable(state)) {
      return false;
    }
    if (dispatch != null) {
      final types = tableNodeTypes(state.schema);
      final rect = selectedRect(state);
      final tr = state.tr;

      final isHeaderRowEnabled = _isHeaderEnabledByType("row", rect, types);
      final isHeaderColumnEnabled = _isHeaderEnabledByType("column", rect, types);

      final isHeaderEnabled = type == "column"
          ? isHeaderRowEnabled
          : type == "row"
          ? isHeaderColumnEnabled
          : false;

      final selectionStartsAt = isHeaderEnabled ? 1 : 0;

      final Rect cellsRect = type == "column"
          ? Rect(left: 0, top: selectionStartsAt, right: 1, bottom: rect.map.height)
          : type == "row"
          ? Rect(left: selectionStartsAt, top: 0, right: rect.map.width, bottom: 1)
          : rect;

      final newType = type == "column"
          ? (isHeaderColumnEnabled ? types[TableRole.cell] : types[TableRole.headerCell])
          : type == "row"
          ? (isHeaderRowEnabled ? types[TableRole.cell] : types[TableRole.headerCell])
          : types[TableRole.cell];

      for (final relativeCellPos in rect.map.cellsInRect(cellsRect)) {
        final cellPos = relativeCellPos + rect.tableStart;
        final cell = tr.doc.nodeAt(cellPos);
        if (cell != null) {
          tr.setNodeMarkup(cellPos, newType, cell.attrs);
        }
      }

      dispatch(tr);
    }
    return true;
  });
}

/// Toggles whether the selected row contains header cells.
final Command toggleHeaderRow = toggleHeader("row", useDeprecatedLogic: true);

/// Toggles whether the selected column contains header cells.
final Command toggleHeaderColumn = toggleHeader("column", useDeprecatedLogic: true);

/// Toggles whether the selected cells are header cells.
final Command toggleHeaderCell = toggleHeader("cell", useDeprecatedLogic: true);

int? _findNextCell(ResolvedPos $cell, int dir) {
  if (dir < 0) {
    final before = $cell.nodeBefore;
    if (before != null) {
      return $cell.pos - before.nodeSize;
    }
    for (var row = $cell.index(-1) - 1, rowEnd = $cell.before(); row >= 0; row--) {
      final rowNode = $cell.node(-1).child(row);
      final lastChild = rowNode.lastChild;
      if (lastChild != null) {
        return rowEnd - 1 - lastChild.nodeSize;
      }
      rowEnd -= rowNode.nodeSize;
    }
  } else {
    if ($cell.index() < $cell.parent.childCount - 1) {
      return $cell.pos + $cell.nodeAfter!.nodeSize;
    }
    final table = $cell.node(-1);
    for (var row = $cell.indexAfter(-1), rowStart = $cell.after(); row < table.childCount; row++) {
      final rowNode = table.child(row);
      if (rowNode.childCount != 0) {
        return rowStart + 1;
      }
      rowStart += rowNode.nodeSize;
    }
  }
  return null;
}

/// Returns a command for selecting the next (direction=1) or previous
/// (direction=-1) cell in a table.
Command goToNextCell(int direction) {
  return FunctionCommand((state, [dispatch, view]) {
    if (!isInTable(state)) {
      return false;
    }
    final cell = _findNextCell(selectionCell(state), direction);
    if (cell == null) {
      return false;
    }
    if (dispatch != null) {
      final $cell = state.doc.resolve(cell);
      dispatch(state.tr.setSelection(TextSelection.between($cell, moveCellForward($cell))).scrollIntoView());
    }
    return true;
  });
}

/// Deletes the table around the selection, if any.
final Command deleteTable = FunctionCommand((state, [dispatch, view]) {
  final $pos = state.selection.$anchor;
  for (var d = $pos.depth; d > 0; d--) {
    final node = $pos.node(d);
    if (tableRoleOf(node.type) == TableRole.table) {
      if (dispatch != null) {
        final tr = state.tr;
        tr.delete($pos.before(d), $pos.after(d));
        tr.scrollIntoView();
        dispatch(tr);
      }
      return true;
    }
  }
  return false;
});

/// Deletes the content of the selected cells, if they are not empty.
final Command deleteCellSelection = FunctionCommand((state, [dispatch, view]) {
  final sel = state.selection;
  if (sel is! CellSelection) {
    return false;
  }
  if (dispatch != null) {
    final tr = state.tr;
    final baseContent = tableNodeTypes(state.schema)[TableRole.cell]!.createAndFill()!.content;
    sel.forEachCell((cell, pos) {
      if (!cell.content.eq(baseContent)) {
        tr.replace(tr.mapping.map(pos + 1), tr.mapping.map(pos + cell.nodeSize - 1), Slice(baseContent, 0, 0));
      }
    });
    if (tr.docChanged) {
      dispatch(tr);
    }
  }
  return true;
});

/// Options for [moveTableRow].
class MoveTableRowOptions {
  MoveTableRowOptions({required this.from, required this.to, this.select = true, this.pos});

  final int from;
  final int to;
  final bool select;
  final int? pos;
}

/// Move a table row from index `from` to index `to`.
Command moveTableRow(MoveTableRowOptions options) {
  return FunctionCommand((state, [dispatch, view]) {
    final tr = state.tr;
    if (moveRow(
      MoveRowParams(
        tr: tr,
        originIndex: options.from,
        targetIndex: options.to,
        select: options.select,
        pos: options.pos ?? state.selection.from,
      ),
    )) {
      if (dispatch != null) {
        dispatch(tr);
      }
      return true;
    }
    return false;
  });
}

/// Options for [moveTableColumn].
class MoveTableColumnOptions {
  MoveTableColumnOptions({required this.from, required this.to, this.select = true, this.pos});

  final int from;
  final int to;
  final bool select;
  final int? pos;
}

/// Move a table column from index `from` to index `to`.
Command moveTableColumn(MoveTableColumnOptions options) {
  return FunctionCommand((state, [dispatch, view]) {
    final tr = state.tr;
    if (moveColumn(
      MoveColumnParams(
        tr: tr,
        originIndex: options.from,
        targetIndex: options.to,
        select: options.select,
        pos: options.pos ?? state.selection.from,
      ),
    )) {
      if (dispatch != null) {
        dispatch(tr);
      }
      return true;
    }
    return false;
  });
}
