import 'package:prosemirror/prosemirror.dart';
import 'package:prosemirror/tables.dart';
import 'package:test/test.dart';

import 'build.dart';

void main() {
  group("addColumnAfter >", () {
    test("can add a plain column", () {
      _test(
        table(tr(c11, c11, c11), tr(c11, cCursor, c11), tr(c11, c11, c11)),
        addColumnAfter,
        table(tr(c11, c11, cEmpty, c11), tr(c11, c11, cEmpty, c11), tr(c11, c11, cEmpty, c11)),
      );
    });

    test("can add a column at the right of the table", () {
      _test(
        table(tr(c11, c11, c11), tr(c11, c11, c11), tr(c11, c11, cCursor)),
        addColumnAfter,
        table(tr(c11, c11, c11, cEmpty), tr(c11, c11, c11, cEmpty), tr(c11, c11, c11, cEmpty)),
      );
    });

    test("can add a second cell", () {
      _test(table(tr(cCursor)), addColumnAfter, table(tr(c11, cEmpty)));
    });

    test("can grow a colspan cell", () {
      _test(table(tr(cCursor, c11), tr(c(2, 1))), addColumnAfter, table(tr(c11, cEmpty, c11), tr(c(3, 1))));
    });

    test("places new cells in the right spot when there's row spans", () {
      _test(
        table(tr(c11, c(1, 2), c(1, 2)), tr(c11), tr(c11, cCursor, c11)),
        addColumnAfter,
        table(tr(c11, c(1, 2), cEmpty, c(1, 2)), tr(c11, cEmpty), tr(c11, c11, cEmpty, c11)),
      );
    });

    test("can place new cells into an empty row", () {
      _test(
        table(tr(c(1, 2), c(1, 2)), tr(), tr(cCursor, c11)),
        addColumnAfter,
        table(tr(c(1, 2), cEmpty, c(1, 2)), tr(cEmpty), tr(c11, cEmpty, c11)),
      );
    });

    test("will skip ahead when growing a rowspan cell", () {
      _test(
        table(tr(c(2, 2), c11), tr(c11), tr(cCursor, c11, c11)),
        addColumnAfter,
        table(tr(c(3, 2), c11), tr(c11), tr(cCursor, cEmpty, c11, c11)),
      );
    });

    test("will use the right side of a single cell selection", () {
      _test(table(tr(cAnchor, c11), tr(c11, c11)), addColumnAfter, table(tr(c11, cEmpty, c11), tr(c11, cEmpty, c11)));
    });

    test("will use the right side of a bigger cell selection", () {
      _test(
        table(tr(cHead, c11, c11), tr(c11, cAnchor, c11)),
        addColumnAfter,
        table(tr(c11, c11, cEmpty, c11), tr(c11, c11, cEmpty, c11)),
      );
    });

    test("properly handles a cell node selection", () {
      _test(
        table(tr("<node>", c11, c11), tr(c11, c11)),
        addColumnAfter,
        table(tr(c11, cEmpty, c11), tr(c11, cEmpty, c11)),
      );
    });

    test("preserves header rows", () {
      _test(table(tr(h11, h11), tr(c11, cCursor)), addColumnAfter, table(tr(h11, h11, hEmpty), tr(c11, c11, cEmpty)));
    });

    test("uses column after as reference when header column before", () {
      _test(table(tr(h11, h11), tr(hCursor, c11)), addColumnAfter, table(tr(h11, hEmpty, h11), tr(h11, cEmpty, c11)));
    });

    test("creates regular cells when only next to a header column", () {
      _test(table(tr(c11, h11), tr(c11, hCursor)), addColumnAfter, table(tr(c11, h11, cEmpty), tr(c11, h11, cEmpty)));
    });

    test("does nothing outside of a table", () {
      _test(doc(p("foo<cursor>")), addColumnAfter, null);
    });

    test("preserves column widths", () {
      _test(
        table(
          tr(cAnchor, c11),
          tr(
            td({
              "colspan": 2,
              "colwidth": [100, 200],
            }, p("a")),
          ),
        ),
        addColumnAfter,
        table(
          tr(cAnchor, cEmpty, c11),
          tr(
            td({
              "colspan": 3,
              "colwidth": [100, 0, 200],
            }, p("a")),
          ),
        ),
      );
    });
  });

  group("addColumnBefore >", () {
    test("can add a plain column", () {
      _test(
        table(tr(c11, c11, c11), tr(c11, cCursor, c11), tr(c11, c11, c11)),
        addColumnBefore,
        table(tr(c11, cEmpty, c11, c11), tr(c11, cEmpty, c11, c11), tr(c11, cEmpty, c11, c11)),
      );
    });

    test("can add a column at the left of the table", () {
      _test(
        table(tr(cCursor, c11, c11), tr(c11, c11, c11), tr(c11, c11, c11)),
        addColumnBefore,
        table(tr(cEmpty, c11, c11, c11), tr(cEmpty, c11, c11, c11), tr(cEmpty, c11, c11, c11)),
      );
    });

    test("will use the left side of a single cell selection", () {
      _test(table(tr(cAnchor, c11), tr(c11, c11)), addColumnBefore, table(tr(cEmpty, c11, c11), tr(cEmpty, c11, c11)));
    });

    test("will use the left side of a bigger cell selection", () {
      _test(
        table(tr(c11, cHead, c11), tr(c11, c11, cAnchor)),
        addColumnBefore,
        table(tr(c11, cEmpty, c11, c11), tr(c11, cEmpty, c11, c11)),
      );
    });

    test("preserves header rows", () {
      _test(table(tr(h11, h11), tr(cCursor, c11)), addColumnBefore, table(tr(hEmpty, h11, h11), tr(cEmpty, c11, c11)));
    });
  });

  group("deleteColumn >", () {
    test("can delete a plain column", () {
      _test(
        table(tr(cEmpty, c11, c11), tr(c11, cCursor, c11), tr(c11, c11, cEmpty)),
        deleteColumn,
        table(tr(cEmpty, c11), tr(c11, c11), tr(c11, cEmpty)),
      );
    });

    test("can delete the first column", () {
      _test(
        table(tr(cCursor, cEmpty, c11), tr(c11, c11, c11), tr(c11, c11, c11)),
        deleteColumn,
        table(tr(cEmpty, c11), tr(c11, c11), tr(c11, c11)),
      );
    });

    test("can delete the last column", () {
      _test(
        table(tr(c11, cEmpty, cCursor), tr(c11, c11, c11), tr(c11, c11, c11)),
        deleteColumn,
        table(tr(c11, cEmpty), tr(c11, c11), tr(c11, c11)),
      );
    });

    test("can reduce a cell's colspan", () {
      _test(table(tr(c11, cCursor), tr(c(2, 1))), deleteColumn, table(tr(c11), tr(c11)));
    });

    test("will skip rows after a rowspan", () {
      _test(table(tr(c11, cCursor), tr(c11, c(1, 2)), tr(c11)), deleteColumn, table(tr(c11), tr(c11), tr(c11)));
    });

    test("will delete all columns under a colspan cell", () {
      _test(
        table(tr(c11, td({"colspan": 2}, p("<cursor>"))), tr(cEmpty, c11, c11)),
        deleteColumn,
        table(tr(c11), tr(cEmpty)),
      );
    });

    test("deletes a cell-selected column", () {
      _test(table(tr(cEmpty, cAnchor), tr(c11, cHead)), deleteColumn, table(tr(cEmpty), tr(c11)));
    });

    test("deletes multiple cell-selected columns", () {
      _test(
        table(tr(c(1, 2), cAnchor, c11), tr(c11, cEmpty), tr(cHead, c11, c11)),
        deleteColumn,
        table(tr(c11), tr(cEmpty), tr(c11)),
      );
    });

    test("leaves column widths intact", () {
      _test(
        table(
          tr(c11, cAnchor, c11),
          tr(
            td({
              "colspan": 3,
              "colwidth": [100, 200, 300],
            }, p("y")),
          ),
        ),
        deleteColumn,
        table(
          tr(c11, c11),
          tr(
            td({
              "colspan": 2,
              "colwidth": [100, 300],
            }, p("y")),
          ),
        ),
      );
    });

    test("resets column width when all zeroes", () {
      _test(
        table(
          tr(c11, cAnchor, c11),
          tr(
            td({
              "colspan": 3,
              "colwidth": [0, 200, 0],
            }, p("y")),
          ),
        ),
        deleteColumn,
        table(tr(c11, c11), tr(td({"colspan": 2}, p("y")))),
      );
    });
  });

  group("addRowAfter >", () {
    test("can add a simple row", () {
      _test(table(tr(cCursor, c11), tr(c11, c11)), addRowAfter, table(tr(c11, c11), tr(cEmpty, cEmpty), tr(c11, c11)));
    });

    test("can add a row at the end", () {
      _test(table(tr(c11, c11), tr(c11, cCursor)), addRowAfter, table(tr(c11, c11), tr(c11, c11), tr(cEmpty, cEmpty)));
    });

    test("increases rowspan when needed", () {
      _test(table(tr(cCursor, c(1, 2)), tr(c11)), addRowAfter, table(tr(c11, c(1, 3)), tr(cEmpty), tr(c11)));
    });

    test("skips columns for colspan cells", () {
      _test(table(tr(cCursor, c(2, 2)), tr(c11)), addRowAfter, table(tr(c11, c(2, 3)), tr(cEmpty), tr(c11)));
    });

    test("picks the row after a cell selection", () {
      _test(
        table(tr(cHead, c11, c11), tr(c11, cAnchor, c11), tr(c(3, 1))),
        addRowAfter,
        table(tr(c11, c11, c11), tr(c11, c11, c11), tr(cEmpty, cEmpty, cEmpty), tr(c(3, 1))),
      );
    });

    test("preserves header columns", () {
      _test(table(tr(c11, hCursor), tr(c11, h11)), addRowAfter, table(tr(c11, h11), tr(cEmpty, hEmpty), tr(c11, h11)));
    });

    test("uses next row as reference when row before is a header", () {
      _test(table(tr(h11, hCursor), tr(c11, h11)), addRowAfter, table(tr(h11, h11), tr(cEmpty, hEmpty), tr(c11, h11)));
    });

    test("creates regular cells when no reference row is available", () {
      _test(table(tr(h11, hCursor)), addRowAfter, table(tr(h11, h11), tr(cEmpty, cEmpty)));
    });
  });

  group("addRowBefore >", () {
    test("can add a simple row", () {
      _test(table(tr(c11, c11), tr(cCursor, c11)), addRowBefore, table(tr(c11, c11), tr(cEmpty, cEmpty), tr(c11, c11)));
    });

    test("can add a row at the start", () {
      _test(table(tr(cCursor, c11), tr(c11, c11)), addRowBefore, table(tr(cEmpty, cEmpty), tr(c11, c11), tr(c11, c11)));
    });

    test("picks the row before a cell selection", () {
      _test(
        table(tr(c11, c(2, 1)), tr(cAnchor, c11, c11), tr(c11, cHead, c11)),
        addRowBefore,
        table(tr(c11, c(2, 1)), tr(cEmpty, cEmpty, cEmpty), tr(c11, c11, c11), tr(c11, c11, c11)),
      );
    });

    test("preserves header columns", () {
      _test(table(tr(hCursor, c11), tr(h11, c11)), addRowBefore, table(tr(hEmpty, cEmpty), tr(h11, c11), tr(h11, c11)));
    });
  });

  group("deleteRow >", () {
    test("can delete a simple row", () {
      _test(
        table(tr(c11, cEmpty), tr(cCursor, c11), tr(c11, cEmpty)),
        deleteRow,
        table(tr(c11, cEmpty), tr(c11, cEmpty)),
      );
    });

    test("can delete the first row", () {
      _test(
        table(tr(c11, cCursor), tr(cEmpty, c11), tr(c11, cEmpty)),
        deleteRow,
        table(tr(cEmpty, c11), tr(c11, cEmpty)),
      );
    });

    test("can delete the last row", () {
      _test(
        table(tr(cEmpty, c11), tr(c11, cEmpty), tr(c11, cCursor)),
        deleteRow,
        table(tr(cEmpty, c11), tr(c11, cEmpty)),
      );
    });

    test("can shrink rowspan cells", () {
      _test(
        table(tr(c(1, 2), c11, c(1, 3)), tr(cCursor), tr(c11, c11)),
        deleteRow,
        table(tr(c11, c11, c(1, 2)), tr(c11, c11)),
      );
    });

    test("can move cells that start in the deleted row", () {
      _test(table(tr(c(1, 2), cCursor), tr(cEmpty)), deleteRow, table(tr(c11, cEmpty)));

      _test(
        table(tr(td({"rowspan": 3}, p("<cursor>")), c11), tr(c11), tr(c(1, 3)), tr(c11), tr(c11)),
        deleteRow,
        table(tr(c11, c(1, 2)), tr(c11)),
      );
    });

    test("moves the same cell with colspan greater than 1 that start in the deleted row only once", () {
      _test(
        table(tr(c(3, 2), c11, c(2, 2), cCursor), tr(c11, cEmpty)),
        deleteRow,
        table(tr(c(3, 1), c11, c(2, 1), cEmpty)),
      );
    });

    test("deletes multiple rows when the start cell has a rowspan", () {
      _test(
        table(tr(td({"rowspan": 3}, p("<cursor>")), c11), tr(c11), tr(c11), tr(c11, c11)),
        deleteRow,
        table(tr(c11, c11)),
      );
    });

    test("moves the same cell with colspan greater than 1 that start in the deleted row only once when deleting multiple rows", () {
      _test(
        table(tr(c(2, 4), td({"rowspan": 3}, p("<cursor>")), c11), tr(c11), tr(c11), tr(c11, c11)),
        deleteRow,
        table(tr(c(2, 1), c11, c11)),
      );
    });

    test("skips columns when adjusting rowspan", () {
      _test(table(tr(cCursor, c(2, 2)), tr(c11)), deleteRow, table(tr(c11, c(2, 1))));
    });

    test("can delete a cell selection", () {
      _test(table(tr(cAnchor, c11), tr(c11, cEmpty)), deleteRow, table(tr(c11, cEmpty)));
    });

    test("will delete all rows in the cell selection", () {
      _test(
        table(tr(c11, cEmpty), tr(cAnchor, c11), tr(c11, cHead), tr(cEmpty, c11)),
        deleteRow,
        table(tr(c11, cEmpty), tr(cEmpty, c11)),
      );
    });
  });

  group("mergeCells >", () {
    test("doesn't do anything when only one cell is selected", () {
      _test(table(tr(cAnchor, c11)), mergeCells, null);
    });

    test("doesn't do anything when the selection cuts across spanning cells", () {
      _test(table(tr(cAnchor, c(2, 1)), tr(c11, cHead, c11)), mergeCells, null);
    });

    test("can merge two cells in a column", () {
      _test(table(tr(cAnchor, cHead, c11)), mergeCells, table(tr(td({"colspan": 2}, p("x"), p("x")), c11)));
    });

    test("can merge two cells in a row", () {
      _test(
        table(tr(cAnchor, c11), tr(cHead, c11)),
        mergeCells,
        table(tr(td({"rowspan": 2}, p("x"), p("x")), c11), tr(c11)),
      );
    });

    test("can merge a rectangle of cells", () {
      _test(
        table(tr(c11, cAnchor, cEmpty, cEmpty, c11), tr(c11, cEmpty, cEmpty, cHead, c11)),
        mergeCells,
        table(tr(c11, td({"rowspan": 2, "colspan": 3}, p("x"), p("x")), c11), tr(c11, c11)),
      );
    });

    test("can merge already spanning cells", () {
      _test(
        table(tr(c11, cAnchor, c(1, 2), cEmpty, c11), tr(c11, cEmpty, cHead, c11)),
        mergeCells,
        table(tr(c11, td({"rowspan": 2, "colspan": 3}, p("x"), p("x"), p("x")), c11), tr(c11, c11)),
      );
    });

    test("keeps the column width of the first col", () {
      _test(
        table(
          tr(
            td({
              "colwidth": [100],
            }, p("x<anchor>")),
            c11,
          ),
          tr(c11, cHead),
        ),
        mergeCells,
        table(
          tr(
            td(
              {
                "colspan": 2,
                "rowspan": 2,
                "colwidth": [100, 0],
              },
              p("x"),
              p("x"),
              p("x"),
              p("x"),
            ),
          ),
          tr(),
        ),
      );
    });
  });

  group("splitCell >", () {
    test("does nothing when cursor is inside of a cell with attributes colspan = 1 and rowspan = 1", () {
      _test(table(tr(cCursor, c11)), splitCell, null);
    });

    test("can split when col-spanning cell with cursor", () {
      _test(table(tr(td({"colspan": 2}, p("foo<cursor>")), c11)), splitCell, table(tr(td(p("foo")), cEmpty, c11)));
    });

    test("can split when col-spanning header-cell with cursor", () {
      _test(table(tr(th({"colspan": 2}, p("foo<cursor>")))), splitCell, table(tr(th(p("foo")), hEmpty)));
    });

    test("does nothing for a multi-cell selection", () {
      _test(table(tr(cAnchor, cHead, c11)), splitCell, null);
    });

    test("does nothing when the selected cell doesn't span anything", () {
      _test(table(tr(cAnchor, c11)), splitCell, null);
    });

    test("can split a col-spanning cell", () {
      _test(table(tr(td({"colspan": 2}, p("foo<anchor>")), c11)), splitCell, table(tr(td(p("foo")), cEmpty, c11)));
    });

    test("can split a row-spanning cell", () {
      _test(
        table(tr(c11, td({"rowspan": 2}, p("foo<anchor>")), c11), tr(c11, c11)),
        splitCell,
        table(tr(c11, td(p("foo")), c11), tr(c11, cEmpty, c11)),
      );
    });

    test("can split a rectangular cell", () {
      _test(
        table(tr(c(4, 1)), tr(c11, td({"rowspan": 2, "colspan": 2}, p("foo<anchor>")), c11), tr(c11, c11)),
        splitCell,
        table(tr(c(4, 1)), tr(c11, td(p("foo")), cEmpty, c11), tr(c11, cEmpty, cEmpty, c11)),
      );
    });

    test("distributes column widths", () {
      _test(
        table(
          tr(
            td({
              "colspan": 3,
              "colwidth": [100, 0, 200],
            }, p("a<anchor>")),
          ),
        ),
        splitCell,
        table(
          tr(
            td({
              "colwidth": [100],
            }, p("a")),
            cEmpty,
            td({
              "colwidth": [200],
            }, p()),
          ),
        ),
      );
    });

    group("with custom cell type >", () {
      test("can split a row-spanning header cell into a header and normal cell", () {
        _test(
          table(tr(c11, td({"rowspan": 2}, p("foo<anchor>")), c11), tr(c11, c11)),
          _splitCellWithOnlyHeaderInColumnZero,
          table(tr(c11, th(p("foo")), c11), tr(c11, cEmpty, c11)),
        );
      });
    });
  });

  group("setCellAttr >", () {
    final cAttr = td({"test": "value"}, p("x"));

    test("can set an attribute on a parent cell", () {
      _test(table(tr(cCursor, c11)), setCellAttr("test", "value"), table(tr(cAttr, c11)));
    });

    test("does nothing when the attribute is already there", () {
      _test(table(tr(cCursor, c11)), setCellAttr("test", "default"), null);
    });

    test("will set attributes on all cells covered by a cell selection", () {
      _test(
        table(tr(c11, cAnchor, c11), tr(c(2, 1), cHead), tr(c11, c11, c11)),
        setCellAttr("test", "value"),
        table(tr(c11, cAttr, cAttr), tr(c(2, 1), cAttr), tr(c11, c11, c11)),
      );
    });
  });

  group("toggleHeaderRow >", () {
    test("turns a non-header row into header", () {
      _test(doc(table(tr(cCursor, c11), tr(c11, c11))), toggleHeaderRow, doc(table(tr(h11, h11), tr(c11, c11))));
    });

    test("turns a header row into regular cells", () {
      _test(doc(table(tr(hCursor, h11), tr(c11, c11))), toggleHeaderRow, doc(table(tr(c11, c11), tr(c11, c11))));
    });

    test("turns a partial header row into regular cells", () {
      _test(doc(table(tr(cCursor, h11), tr(c11, c11))), toggleHeaderRow, doc(table(tr(c11, c11), tr(c11, c11))));
    });

    test("leaves cell spans intact", () {
      _test(
        doc(table(tr(cCursor, c(2, 2)), tr(c11), tr(c11, c11, c11))),
        toggleHeaderRow,
        doc(table(tr(h11, h(2, 2)), tr(c11), tr(c11, c11, c11))),
      );
    });
  });

  group("toggleHeaderColumn >", () {
    test("turns a non-header column into header", () {
      _test(doc(table(tr(cCursor, c11), tr(c11, c11))), toggleHeaderColumn, doc(table(tr(h11, c11), tr(h11, c11))));
    });

    test("turns a header column into regular cells", () {
      _test(doc(table(tr(hCursor, h11), tr(h11, c11))), toggleHeaderColumn, doc(table(tr(c11, h11), tr(c11, c11))));
    });

    test("turns a partial header column into regular cells", () {
      _test(doc(table(tr(hCursor, c11), tr(c11, c11))), toggleHeaderColumn, doc(table(tr(c11, c11), tr(c11, c11))));
    });
  });

  group("toggleHeader >", () {
    test("turns a header row with colspan and rowspan into a regular cell", () {
      _test(
        doc(p("x"), table(tr(h(2, 1), h(1, 2)), tr(cCursor, c11), tr(c11, c11, c11))),
        toggleHeader("row", useDeprecatedLogic: false),
        doc(p("x"), table(tr(c(2, 1), c(1, 2)), tr(cCursor, c11), tr(c11, c11, c11))),
      );
    });

    test("turns a header column with colspan and rowspan into a regular cell", () {
      _test(
        doc(p("x"), table(tr(h(2, 1), h(1, 2)), tr(cCursor, c11), tr(c11, c11, c11))),
        toggleHeader("column", useDeprecatedLogic: false),
        doc(p("x"), table(tr(h(2, 1), h(1, 2)), tr(h11, c11), tr(h11, c11, c11))),
      );
    });

    test("should keep first cell as header when the column header is enabled", () {
      _test(
        doc(p("x"), table(tr(h11, c11), tr(hCursor, c11), tr(h11, c11))),
        toggleHeader("row", useDeprecatedLogic: false),
        doc(p("x"), table(tr(h11, h11), tr(h11, c11), tr(h11, c11))),
      );
    });

    group("new behavior >", () {
      test("turns a header column into regular cells without override header row", () {
        _test(
          doc(table(tr(hCursor, h11), tr(h11, c11))),
          toggleHeader("column", useDeprecatedLogic: false),
          doc(table(tr(hCursor, h11), tr(c11, c11))),
        );
      });
    });
  });
}

final Command _splitCellWithOnlyHeaderInColumnZero = FunctionCommand((state, [dispatch, view]) {
  return splitCellWithType((options) {
    if (options.row == 0) {
      return state.schema.nodes["table_header"]!;
    }
    return state.schema.nodes["table_cell"]!;
  }).execute(state, dispatch);
});

void _test(Node document, Command command, Node? result) {
  var state = EditorState.create(EditorStateConfig(doc: document, selection: selectionFor(document)));
  final ran = command.execute(state, (tr) => state = state.apply(tr));
  if (result == null) {
    expect(ran, isFalse);
  } else {
    expect(eq(state.doc, result), isTrue);
  }
}
