// The non-UI public surface of the tables module.

export 'package:prosemirror/src/tables/cellselection.dart' show CellSelection, CellBookmark, CellSelectionJSON;
export 'package:prosemirror/src/tables/commands.dart';
export 'package:prosemirror/src/tables/copypaste.dart' show Area, pastedCells, clipCells, insertCells, fitSlice;
export 'package:prosemirror/src/tables/fixtables.dart' show fixTables, fixTable, fixTablesKey;
export 'package:prosemirror/src/tables/schema.dart'
    show tableNodes, tableNodeTypes, TableRole, TableNodesOptions, CellAttributes, tableRoleOf;
export 'package:prosemirror/src/tables/tablemap.dart'
    show
        TableMap,
        Rect,
        Problem,
        ColWidths,
        ColwidthMismatchProblem,
        CollisionProblem,
        MissingProblem,
        OverlongRowspanProblem,
        ZeroSizedProblem;
export 'package:prosemirror/src/tables/util.dart'
    show
        cellAround,
        cellNear,
        cellWrapping,
        selectionCell,
        isInTable,
        nextCell,
        findCell,
        colCount,
        addColSpan,
        removeColSpan,
        columnIsHeader,
        pointsAtCell,
        moveCellForward,
        inSameTable,
        tableEditingKey,
        CellAttrs,
        MutableAttrs;
export 'package:prosemirror/src/tables/utils/convert.dart'
    show convertTableNodeToArrayOfRows, convertArrayOfRowsToTableNode;
export 'package:prosemirror/src/tables/utils/move_row_in_array_of_rows.dart' show moveRowInArrayOfRows;
export 'package:prosemirror/src/tables/utils/query.dart' show findTable, findCellPos, findCellRange, FindNodeResult;
export 'package:prosemirror/src/tables/utils/transpose.dart' show transpose;
