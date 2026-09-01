import 'package:prosemirror/prosemirror.dart';

import 'package:prosemirror/src/tables/tablemap.dart';

/// Transforms the table node into a matrix of rows and columns respecting
/// merged cells.
///
/// Cells that are covered by a spanning cell to their left or above are
/// represented as `null`.
List<List<Node?>> convertTableNodeToArrayOfRows(Node tableNode) {
  final map = TableMap.get(tableNode);
  final rows = <List<Node?>>[];
  final rowCount = map.height;
  final columnCount = map.width;
  for (var rowIndex = 0; rowIndex < rowCount; rowIndex++) {
    final row = <Node?>[];
    for (var columnIndex = 0; columnIndex < columnCount; columnIndex++) {
      final cellIndex = rowIndex * columnCount + columnIndex;
      final cellPos = map.map[cellIndex];
      if (rowIndex > 0) {
        final topCellIndex = cellIndex - columnCount;
        final topCellPos = map.map[topCellIndex];
        if (cellPos == topCellPos) {
          row.add(null);
          continue;
        }
      }
      if (columnIndex > 0) {
        final leftCellIndex = cellIndex - 1;
        final leftCellPos = map.map[leftCellIndex];
        if (cellPos == leftCellPos) {
          row.add(null);
          continue;
        }
      }
      row.add(tableNode.nodeAt(cellPos));
    }
    rows.add(row);
  }

  return rows;
}

/// Convert an array of rows to a table node.
Node convertArrayOfRowsToTableNode(Node tableNode, List<List<Node?>> arrayOfNodes) {
  final newRows = <Node>[];
  final map = TableMap.get(tableNode);
  final rowCount = map.height;
  final columnCount = map.width;
  for (var rowIndex = 0; rowIndex < rowCount; rowIndex++) {
    final oldRow = tableNode.child(rowIndex);
    final newCells = <Node>[];

    for (var columnIndex = 0; columnIndex < columnCount; columnIndex++) {
      final cell = arrayOfNodes[rowIndex][columnIndex];
      if (cell == null) {
        continue;
      }

      final cellPos = map.map[rowIndex * map.width + columnIndex];
      final oldCell = tableNode.nodeAt(cellPos);
      if (oldCell == null) {
        continue;
      }

      final newCell = oldCell.type.createChecked(cell.attrs, cell.content, cell.marks);
      newCells.add(newCell);
    }

    final newRow = oldRow.type.createChecked(oldRow.attrs, newCells, oldRow.marks);
    newRows.add(newRow);
  }

  return tableNode.type.createChecked(tableNode.attrs, newRows, tableNode.marks);
}
