import 'package:prosemirror/prosemirror.dart';

import 'package:prosemirror/src/tables/tablemap.dart';
import 'package:prosemirror/src/tables/utils/query.dart';

/// Returns an array of cells in a column at the specified [columnIndex].
List<FindNodeResult>? getCellsInColumn(int columnIndex, Selection selection) {
  final table = findTable(selection.$from);
  if (table == null) {
    return null;
  }

  final map = TableMap.get(table.node);

  if (columnIndex < 0 || columnIndex > map.width - 1) {
    return null;
  }

  final cells = map.cellsInRect(Rect(left: columnIndex, right: columnIndex + 1, top: 0, bottom: map.height));

  return cells.map((nodePos) {
    final node = table.node.nodeAt(nodePos)!;
    final pos = nodePos + table.start;
    return FindNodeResult(node: node, pos: pos, start: pos + 1, depth: table.depth + 2);
  }).toList();
}

/// Returns an array of cells in a row at the specified [rowIndex].
List<FindNodeResult>? getCellsInRow(int rowIndex, Selection selection) {
  final table = findTable(selection.$from);
  if (table == null) {
    return null;
  }

  final map = TableMap.get(table.node);

  if (rowIndex < 0 || rowIndex > map.height - 1) {
    return null;
  }

  final cells = map.cellsInRect(Rect(left: 0, right: map.width, top: rowIndex, bottom: rowIndex + 1));

  return cells.map((nodePos) {
    final node = table.node.nodeAt(nodePos)!;
    final pos = nodePos + table.start;
    return FindNodeResult(node: node, pos: pos, start: pos + 1, depth: table.depth + 2);
  }).toList();
}
