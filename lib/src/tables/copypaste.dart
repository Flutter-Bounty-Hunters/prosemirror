// Utilities used for copy/paste handling.
//
// This module handles pasting cell content into tables, or pasting anything
// into a cell selection, as replacing a block of cells with the content of the
// selection.

import 'dart:math' as math;

import 'package:prosemirror/prosemirror.dart';

import 'package:prosemirror/src/tables/cellselection.dart';
import 'package:prosemirror/src/tables/schema.dart';
import 'package:prosemirror/src/tables/tablemap.dart';
import 'package:prosemirror/src/tables/util.dart';

/// A rectangular area of table cells.
class Area {
  Area({required this.width, required this.height, required this.rows});

  final int width;
  final int height;
  final List<Fragment> rows;
}

/// Get a rectangular area of cells from a slice, or null if the outer nodes of
/// the slice aren't table cells or rows.
Area? pastedCells(Slice slice) {
  if (slice.size == 0) {
    return null;
  }
  var content = slice.content;
  var openStart = slice.openStart;
  var openEnd = slice.openEnd;
  while (content.childCount == 1 &&
      ((openStart > 0 && openEnd > 0) || tableRoleOf(content.child(0).type) == TableRole.table)) {
    openStart--;
    openEnd--;
    content = content.child(0).content;
  }
  final first = content.child(0);
  final role = tableRoleOf(first.type);
  final schema = first.type.schema;
  final rows = <Fragment>[];
  if (role == TableRole.row) {
    for (var i = 0; i < content.childCount; i++) {
      var cells = content.child(i).content;
      final left = i != 0 ? 0 : math.max(0, openStart - 1);
      final right = i < content.childCount - 1 ? 0 : math.max(0, openEnd - 1);
      if (left != 0 || right != 0) {
        cells = fitSlice(tableNodeTypes(schema)[TableRole.row]!, Slice(cells, left, right)).content;
      }
      rows.add(cells);
    }
  } else if (role == TableRole.cell || role == TableRole.headerCell) {
    rows.add(
      openStart != 0 || openEnd != 0
          ? fitSlice(tableNodeTypes(schema)[TableRole.row]!, Slice(content, openStart, openEnd)).content
          : content,
    );
  } else {
    return null;
  }
  return _ensureRectangular(schema, rows);
}

// Compute the width and height of a set of cells, and make sure each row has
// the same number of cells.
Area _ensureRectangular(Schema schema, List<Fragment> rows) {
  final widths = <int>[];
  for (var i = 0; i < rows.length; i++) {
    final row = rows[i];
    for (var j = row.childCount - 1; j >= 0; j--) {
      final rowspan = row.child(j).attrs["rowspan"] as int;
      final colspan = row.child(j).attrs["colspan"] as int;
      for (var r = i; r < i + rowspan; r++) {
        while (widths.length <= r) {
          widths.add(0);
        }
        widths[r] = widths[r] + colspan;
      }
    }
  }
  var width = 0;
  for (var r = 0; r < widths.length; r++) {
    width = math.max(width, widths[r]);
  }
  for (var r = 0; r < widths.length; r++) {
    if (r >= rows.length) {
      rows.add(Fragment.empty);
    }
    if (widths[r] < width) {
      final empty = tableNodeTypes(schema)[TableRole.cell]!.createAndFill()!;
      final cells = <Node>[];
      for (var i = widths[r]; i < width; i++) {
        cells.add(empty);
      }
      rows[r] = rows[r].append(Fragment.from(cells));
    }
  }
  return Area(height: rows.length, width: width, rows: rows);
}

/// Build a node of the given [nodeType] and fill it with the content of
/// [slice].
Node fitSlice(NodeType nodeType, Slice slice) {
  final node = nodeType.createAndFill()!;
  final tr = Transform(node).replace(0, node.content.size, slice);
  return tr.doc;
}

/// Clip or extend (repeat) the given set of cells to cover the given width and
/// height.
Area clipCells(Area cells, int newWidth, int newHeight) {
  var width = cells.width;
  var height = cells.height;
  var rows = cells.rows;

  if (width != newWidth) {
    final added = <int>[];
    final newRows = <Fragment>[];
    for (var row = 0; row < rows.length; row++) {
      final frag = rows[row];
      final cellList = <Node>[];
      for (var col = row < added.length ? added[row] : 0, i = 0; col < newWidth; i++) {
        var cell = frag.child(i % frag.childCount);
        final colspan = cell.attrs["colspan"] as int;
        if (col + colspan > newWidth) {
          cell = cell.type.createChecked(removeColSpan(cell.attrs, colspan, col + colspan - newWidth), cell.content);
        }
        cellList.add(cell);
        col += cell.attrs["colspan"] as int;
        for (var j = 1; j < (cell.attrs["rowspan"] as int); j++) {
          while (added.length <= row + j) {
            added.add(0);
          }
          added[row + j] = added[row + j] + (cell.attrs["colspan"] as int);
        }
      }
      newRows.add(Fragment.from(cellList));
    }
    rows = newRows;
    width = newWidth;
  }

  if (height != newHeight) {
    final newRows = <Fragment>[];
    for (var row = 0, i = 0; row < newHeight; row++, i++) {
      final cellList = <Node>[];
      final source = rows[i % height];
      for (var j = 0; j < source.childCount; j++) {
        var cell = source.child(j);
        final rowspan = cell.attrs["rowspan"] as int;
        if (row + rowspan > newHeight) {
          cell = cell.type.create(<String, Object?>{
            ...cell.attrs,
            "rowspan": math.max(1, newHeight - rowspan),
          }, cell.content);
        }
        cellList.add(cell);
      }
      newRows.add(Fragment.from(cellList));
    }
    rows = newRows;
    height = newHeight;
  }

  return Area(width: width, height: height, rows: rows);
}

// Make sure a table has at least the given width and height. Return true if
// something was changed.
bool _growTable(Transaction tr, TableMap map, Node table, int start, int width, int height, int mapFrom) {
  final schema = tr.doc.type.schema;
  final types = tableNodeTypes(schema);
  Node? empty;
  Node? emptyHead;
  if (width > map.width) {
    for (var row = 0, rowEnd = 0; row < map.height; row++) {
      final rowNode = table.child(row);
      rowEnd += rowNode.nodeSize;
      final cells = <Node>[];
      Node add;
      if (rowNode.lastChild == null || rowNode.lastChild!.type == types[TableRole.cell]) {
        add = empty ??= types[TableRole.cell]!.createAndFill()!;
      } else {
        add = emptyHead ??= types[TableRole.headerCell]!.createAndFill()!;
      }
      for (var i = map.width; i < width; i++) {
        cells.add(add);
      }
      tr.insert(tr.mapping.slice(mapFrom).map(rowEnd - 1 + start), cells);
    }
  }
  if (height > map.height) {
    final cells = <Node>[];
    for (var i = 0, start = (map.height - 1) * map.width; i < math.max(map.width, width); i++) {
      final header = i >= map.width ? false : table.nodeAt(map.map[start + i])!.type == types[TableRole.headerCell];
      cells.add(
        header
            ? (emptyHead ??= types[TableRole.headerCell]!.createAndFill()!)
            : (empty ??= types[TableRole.cell]!.createAndFill()!),
      );
    }

    final emptyRow = types[TableRole.row]!.create(null, Fragment.from(cells));
    final rows = <Node>[];
    for (var i = map.height; i < height; i++) {
      rows.add(emptyRow);
    }
    tr.insert(tr.mapping.slice(mapFrom).map(start + table.nodeSize - 2), rows);
  }
  return empty != null || emptyHead != null;
}

// Make sure the given horizontal line doesn't cross any rowspan cells by
// splitting cells that cross it. Return true if something changed.
bool _isolateHorizontal(
  Transaction tr,
  TableMap map,
  Node table,
  int start,
  int left,
  int right,
  int top,
  int mapFrom,
) {
  if (top == 0 || top == map.height) {
    return false;
  }
  var found = false;
  for (var col = left; col < right; col++) {
    final index = top * map.width + col;
    final pos = map.map[index];
    if (map.map[index - map.width] == pos) {
      found = true;
      final cell = table.nodeAt(pos)!;
      final cellRect = map.findCell(pos);
      tr.setNodeMarkup(tr.mapping.slice(mapFrom).map(pos + start), null, <String, Object?>{
        ...cell.attrs,
        "rowspan": top - cellRect.top,
      });
      tr.insert(
        tr.mapping.slice(mapFrom).map(map.positionAt(top, cellRect.left, table)),
        cell.type.createAndFill(<String, Object?>{
          ...cell.attrs,
          "rowspan": cellRect.top + (cell.attrs["rowspan"] as int) - top,
        })!,
      );
      col += (cell.attrs["colspan"] as int) - 1;
    }
  }
  return found;
}

// Make sure the given vertical line doesn't cross any colspan cells by
// splitting cells that cross it. Return true if something changed.
bool _isolateVertical(Transaction tr, TableMap map, Node table, int start, int top, int bottom, int left, int mapFrom) {
  if (left == 0 || left == map.width) {
    return false;
  }
  var found = false;
  for (var row = top; row < bottom; row++) {
    final index = row * map.width + left;
    final pos = map.map[index];
    if (map.map[index - 1] == pos) {
      found = true;
      final cell = table.nodeAt(pos)!;
      final cellLeft = map.colCount(pos);
      final updatePos = tr.mapping.slice(mapFrom).map(pos + start);
      tr.setNodeMarkup(
        updatePos,
        null,
        removeColSpan(cell.attrs, left - cellLeft, (cell.attrs["colspan"] as int) - (left - cellLeft)),
      );
      tr.insert(updatePos + cell.nodeSize, cell.type.createAndFill(removeColSpan(cell.attrs, 0, left - cellLeft))!);
      row += (cell.attrs["rowspan"] as int) - 1;
    }
  }
  return found;
}

/// Insert the given set of cells (as returned by [pastedCells]) into a table,
/// at the position pointed at by [rect].
void insertCells(EditorState state, void Function(Transaction tr) dispatch, int tableStart, Rect rect, Area cells) {
  var table = tableStart != 0 ? state.doc.nodeAt(tableStart - 1) : state.doc;
  if (table == null) {
    throw StateError("No table found");
  }
  var map = TableMap.get(table);
  final top = rect.top;
  final left = rect.left;
  final right = left + cells.width;
  final bottom = top + cells.height;
  final tr = state.tr;
  var mapFrom = 0;

  // Prepare the table to be large enough and not have any cells crossing the
  // boundaries of the rectangle that we want to insert into.
  if (_growTable(tr, map, table, tableStart, right, bottom, mapFrom)) {
    final result = _recomp(tr, tableStart);
    table = result.table;
    map = result.map;
    mapFrom = result.mapFrom;
  }
  if (_isolateHorizontal(tr, map, table, tableStart, left, right, top, mapFrom)) {
    final result = _recomp(tr, tableStart);
    table = result.table;
    map = result.map;
    mapFrom = result.mapFrom;
  }
  if (_isolateHorizontal(tr, map, table, tableStart, left, right, bottom, mapFrom)) {
    final result = _recomp(tr, tableStart);
    table = result.table;
    map = result.map;
    mapFrom = result.mapFrom;
  }
  if (_isolateVertical(tr, map, table, tableStart, top, bottom, left, mapFrom)) {
    final result = _recomp(tr, tableStart);
    table = result.table;
    map = result.map;
    mapFrom = result.mapFrom;
  }
  if (_isolateVertical(tr, map, table, tableStart, top, bottom, right, mapFrom)) {
    final result = _recomp(tr, tableStart);
    table = result.table;
    map = result.map;
    mapFrom = result.mapFrom;
  }

  for (var row = top; row < bottom; row++) {
    final from = map.positionAt(row, left, table);
    final to = map.positionAt(row, right, table);
    tr.replace(
      tr.mapping.slice(mapFrom).map(from + tableStart),
      tr.mapping.slice(mapFrom).map(to + tableStart),
      Slice(cells.rows[row - top], 0, 0),
    );
  }
  final result = _recomp(tr, tableStart);
  table = result.table;
  map = result.map;
  mapFrom = result.mapFrom;
  tr.setSelection(
    CellSelection(
      tr.doc.resolve(tableStart + map.positionAt(top, left, table)),
      tr.doc.resolve(tableStart + map.positionAt(bottom - 1, right - 1, table)),
    ),
  );
  dispatch(tr);
}

({Node table, TableMap map, int mapFrom}) _recomp(Transaction tr, int tableStart) {
  final table = tableStart != 0 ? tr.doc.nodeAt(tableStart - 1) : tr.doc;
  if (table == null) {
    throw StateError("No table found");
  }
  return (table: table, map: TableMap.get(table), mapFrom: tr.mapping.maps.length);
}
