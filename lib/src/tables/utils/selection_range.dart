import 'package:prosemirror/prosemirror.dart';

import 'package:prosemirror/src/tables/utils/get_cells.dart';
import 'package:prosemirror/src/tables/utils/query.dart';

/// A range of a rectangular cell selection, together with the covered indexes.
class CellSelectionRange {
  CellSelectionRange({required this.$anchor, required this.$head, required this.indexes});

  final ResolvedPos $anchor;
  final ResolvedPos $head;

  /// An array of column/row indexes.
  final List<int> indexes;
}

/// Returns a range of rectangular selection spanning all merged cells around a
/// column at index [startColIndex].
CellSelectionRange? getSelectionRangeInColumn(Transaction tr, int startColIndex, [int? endColIndex]) {
  var startIndex = startColIndex;
  var endIndex = endColIndex ?? startColIndex;

  // Looking for selection start column (startIndex).
  for (var i = startColIndex; i >= 0; i--) {
    final cells = getCellsInColumn(i, tr.selection);
    if (cells != null) {
      for (final cell in cells) {
        final maybeEndIndex = (cell.node.attrs["colspan"] as int) + i - 1;
        if (maybeEndIndex >= startIndex) {
          startIndex = i;
        }
        if (maybeEndIndex > endIndex) {
          endIndex = maybeEndIndex;
        }
      }
    }
  }
  // Looking for selection end column (endIndex).
  for (var i = startColIndex; i <= endIndex; i++) {
    final cells = getCellsInColumn(i, tr.selection);
    if (cells != null) {
      for (final cell in cells) {
        final maybeEndIndex = (cell.node.attrs["colspan"] as int) + i - 1;
        if ((cell.node.attrs["colspan"] as int) > 1 && maybeEndIndex > endIndex) {
          endIndex = maybeEndIndex;
        }
      }
    }
  }

  // Filter out columns without cells.
  final indexes = <int>[];
  for (var i = startIndex; i <= endIndex; i++) {
    final maybeCells = getCellsInColumn(i, tr.selection);
    if (maybeCells != null && maybeCells.isNotEmpty) {
      indexes.add(i);
    }
  }
  startIndex = indexes[0];
  endIndex = indexes[indexes.length - 1];

  final firstSelectedColumnCells = getCellsInColumn(startIndex, tr.selection);
  final firstRowCells = getCellsInRow(0, tr.selection);
  if (firstSelectedColumnCells == null || firstRowCells == null) {
    return null;
  }

  final $anchor = tr.doc.resolve(firstSelectedColumnCells[firstSelectedColumnCells.length - 1].pos);

  FindNodeResult? headCell;
  for (var i = endIndex; i >= startIndex; i--) {
    final columnCells = getCellsInColumn(i, tr.selection);
    if (columnCells != null && columnCells.isNotEmpty) {
      for (var j = firstRowCells.length - 1; j >= 0; j--) {
        if (firstRowCells[j].pos == columnCells[0].pos) {
          headCell = columnCells[0];
          break;
        }
      }
      if (headCell != null) {
        break;
      }
    }
  }
  if (headCell == null) {
    return null;
  }

  final $head = tr.doc.resolve(headCell.pos);
  return CellSelectionRange($anchor: $anchor, $head: $head, indexes: indexes);
}

/// Returns a range of rectangular selection spanning all merged cells around a
/// row at index [startRowIndex].
CellSelectionRange? getSelectionRangeInRow(Transaction tr, int startRowIndex, [int? endRowIndex]) {
  var startIndex = startRowIndex;
  var endIndex = endRowIndex ?? startRowIndex;

  // Looking for selection start row (startIndex).
  for (var i = startRowIndex; i >= 0; i--) {
    final cells = getCellsInRow(i, tr.selection);
    if (cells != null) {
      for (final cell in cells) {
        final maybeEndIndex = (cell.node.attrs["rowspan"] as int) + i - 1;
        if (maybeEndIndex >= startIndex) {
          startIndex = i;
        }
        if (maybeEndIndex > endIndex) {
          endIndex = maybeEndIndex;
        }
      }
    }
  }
  // Looking for selection end row (endIndex).
  for (var i = startRowIndex; i <= endIndex; i++) {
    final cells = getCellsInRow(i, tr.selection);
    if (cells != null) {
      for (final cell in cells) {
        final maybeEndIndex = (cell.node.attrs["rowspan"] as int) + i - 1;
        if ((cell.node.attrs["rowspan"] as int) > 1 && maybeEndIndex > endIndex) {
          endIndex = maybeEndIndex;
        }
      }
    }
  }

  // Filter out rows without cells.
  final indexes = <int>[];
  for (var i = startIndex; i <= endIndex; i++) {
    final maybeCells = getCellsInRow(i, tr.selection);
    if (maybeCells != null && maybeCells.isNotEmpty) {
      indexes.add(i);
    }
  }
  startIndex = indexes[0];
  endIndex = indexes[indexes.length - 1];

  final firstSelectedRowCells = getCellsInRow(startIndex, tr.selection);
  final firstColumnCells = getCellsInColumn(0, tr.selection);
  if (firstSelectedRowCells == null || firstColumnCells == null) {
    return null;
  }

  final $anchor = tr.doc.resolve(firstSelectedRowCells[firstSelectedRowCells.length - 1].pos);

  FindNodeResult? headCell;
  for (var i = endIndex; i >= startIndex; i--) {
    final rowCells = getCellsInRow(i, tr.selection);
    if (rowCells != null && rowCells.isNotEmpty) {
      for (var j = firstColumnCells.length - 1; j >= 0; j--) {
        if (firstColumnCells[j].pos == rowCells[0].pos) {
          headCell = rowCells[0];
          break;
        }
      }
      if (headCell != null) {
        break;
      }
    }
  }
  if (headCell == null) {
    return null;
  }

  final $head = tr.doc.resolve(headCell.pos);
  return CellSelectionRange($anchor: $anchor, $head: $head, indexes: indexes);
}
