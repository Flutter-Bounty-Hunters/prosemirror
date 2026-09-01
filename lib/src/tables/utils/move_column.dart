import 'package:prosemirror/prosemirror.dart';

import 'package:prosemirror/src/tables/cellselection.dart';
import 'package:prosemirror/src/tables/tablemap.dart';
import 'package:prosemirror/src/tables/utils/convert.dart';
import 'package:prosemirror/src/tables/utils/move_row_in_array_of_rows.dart';
import 'package:prosemirror/src/tables/utils/query.dart';
import 'package:prosemirror/src/tables/utils/selection_range.dart';
import 'package:prosemirror/src/tables/utils/transpose.dart';

/// Parameters for moving a column in a table.
class MoveColumnParams {
  MoveColumnParams({
    required this.tr,
    required this.originIndex,
    required this.targetIndex,
    required this.select,
    required this.pos,
  });

  final Transaction tr;
  final int originIndex;
  final int targetIndex;
  final bool select;
  final int pos;
}

/// Move a column from index `origin` to index `target`.
bool moveColumn(MoveColumnParams moveColParams) {
  final tr = moveColParams.tr;
  final originIndex = moveColParams.originIndex;
  final targetIndex = moveColParams.targetIndex;
  final select = moveColParams.select;
  final pos = moveColParams.pos;

  final $pos = tr.doc.resolve(pos);
  final table = findTable($pos);
  if (table == null) {
    return false;
  }

  final indexesOriginColumn = getSelectionRangeInColumn(tr, originIndex)?.indexes;
  final indexesTargetColumn = getSelectionRangeInColumn(tr, targetIndex)?.indexes;

  if (indexesOriginColumn == null || indexesTargetColumn == null) {
    return false;
  }

  if (indexesOriginColumn.contains(targetIndex)) {
    return false;
  }

  final newTable = _moveTableColumn(table.node, indexesOriginColumn, indexesTargetColumn, 0);

  tr.replaceWith(table.pos, table.pos + table.node.nodeSize, newTable);

  if (!select) {
    return true;
  }

  final map = TableMap.get(newTable);
  final start = table.start;
  final index = targetIndex;
  final lastCell = map.positionAt(map.height - 1, index, newTable);
  final $lastCell = tr.doc.resolve(start + lastCell);

  final firstCell = map.positionAt(0, index, newTable);
  final $firstCell = tr.doc.resolve(start + firstCell);

  tr.setSelection(CellSelection.colSelection($lastCell, $firstCell));
  return true;
}

Node _moveTableColumn(Node table, List<int> indexesOrigin, List<int> indexesTarget, int direction) {
  var rows = transpose(convertTableNodeToArrayOfRows(table));

  rows = moveRowInArrayOfRows(rows, indexesOrigin, indexesTarget, direction);
  rows = transpose(rows);

  return convertArrayOfRowsToTableNode(table, rows);
}
