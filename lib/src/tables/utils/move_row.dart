import 'package:prosemirror/prosemirror.dart';

import 'package:prosemirror/src/tables/cellselection.dart';
import 'package:prosemirror/src/tables/tablemap.dart';
import 'package:prosemirror/src/tables/utils/convert.dart';
import 'package:prosemirror/src/tables/utils/move_row_in_array_of_rows.dart';
import 'package:prosemirror/src/tables/utils/query.dart';
import 'package:prosemirror/src/tables/utils/selection_range.dart';

/// Parameters for moving a row in a table.
class MoveRowParams {
  MoveRowParams({
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

/// Move a row from index `origin` to index `target`.
bool moveRow(MoveRowParams moveRowParams) {
  final tr = moveRowParams.tr;
  final originIndex = moveRowParams.originIndex;
  final targetIndex = moveRowParams.targetIndex;
  final select = moveRowParams.select;
  final pos = moveRowParams.pos;

  final $pos = tr.doc.resolve(pos);
  final table = findTable($pos);
  if (table == null) {
    return false;
  }

  final indexesOriginRow = getSelectionRangeInRow(tr, originIndex)?.indexes;
  final indexesTargetRow = getSelectionRangeInRow(tr, targetIndex)?.indexes;

  if (indexesOriginRow == null || indexesTargetRow == null) {
    return false;
  }

  if (indexesOriginRow.contains(targetIndex)) {
    return false;
  }

  final newTable = _moveTableRow(table.node, indexesOriginRow, indexesTargetRow, 0);

  tr.replaceWith(table.pos, table.pos + table.node.nodeSize, newTable);

  if (!select) {
    return true;
  }

  final map = TableMap.get(newTable);
  final start = table.start;
  final index = targetIndex;
  final lastCell = map.positionAt(index, map.width - 1, newTable);
  final $lastCell = tr.doc.resolve(start + lastCell);

  final firstCell = map.positionAt(index, 0, newTable);
  final $firstCell = tr.doc.resolve(start + firstCell);

  tr.setSelection(CellSelection.rowSelection($lastCell, $firstCell));
  return true;
}

Node _moveTableRow(Node table, List<int> indexesOrigin, List<int> indexesTarget, int direction) {
  var rows = convertTableNodeToArrayOfRows(table);

  rows = moveRowInArrayOfRows(rows, indexesOrigin, indexesTarget, direction);

  return convertArrayOfRowsToTableNode(table, rows);
}
