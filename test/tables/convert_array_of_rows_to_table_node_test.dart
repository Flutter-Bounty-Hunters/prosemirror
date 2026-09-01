import 'package:prosemirror/prosemirror.dart';
import 'package:prosemirror/tables.dart';
import 'package:test/test.dart';

import 'build.dart';

void main() {
  group("convertArrayOfRowsToTableNode >", () {
    test("should convert array of rows back to table node (roundtrip)", () {
      final originalTable = table(tr(c(1, 1, "A1"), c(1, 1, "B1")), tr(c(1, 1, "A2"), c(1, 1, "B2")));

      final arrayOfRows = convertTableNodeToArrayOfRows(originalTable);
      final newTable = convertArrayOfRowsToTableNode(originalTable, arrayOfRows);

      _expectTableEquals(originalTable, newTable);
    });

    test("should handle modified cell content", () {
      final originalTable = table(tr(c(1, 1, "A1"), c(1, 1, "B1")), tr(c(1, 1, "A2"), c(1, 1, "B2")));

      final arrayOfRows = convertTableNodeToArrayOfRows(originalTable);
      // Modify the content of one cell
      arrayOfRows[0][1] = td(p("Modified"));

      final newTable = convertArrayOfRowsToTableNode(originalTable, arrayOfRows);

      final expectedTable = table(tr(c(1, 1, "A1"), c(1, 1, "Modified")), tr(c(1, 1, "A2"), c(1, 1, "B2")));

      _expectTableEquals(expectedTable, newTable);
    });

    test("should handle empty cells in array", () {
      final originalTable = table(tr(c(1, 1, "A1"), c(1, 1, "B1")), tr(c(1, 1, "A2"), c(1, 1, "B2")));

      final arrayOfRows = convertTableNodeToArrayOfRows(originalTable);
      // Replace one cell with an empty cell
      arrayOfRows[1][0] = td(p());

      final newTable = convertArrayOfRowsToTableNode(originalTable, arrayOfRows);

      final expectedTable = table(tr(c(1, 1, "A1"), c(1, 1, "B1")), tr(c(1, 1, ""), c(1, 1, "B2")));

      _expectTableEquals(expectedTable, newTable);
    });

    test("should handle multiple cell modifications", () {
      final originalTable = table(
        tr(c(1, 1, "A1"), c(1, 1, "B1"), c(1, 1, "C1")),
        tr(c(1, 1, "A2"), c(1, 1, "B2"), c(1, 1, "C2")),
        tr(c(1, 1, "A3"), c(1, 1, "B3"), c(1, 1, "C3")),
      );

      final arrayOfRows = convertTableNodeToArrayOfRows(originalTable);
      // Modify multiple cells
      arrayOfRows[0][0] = td(p("New A1"));
      arrayOfRows[1][1] = td(p("New B2"));
      arrayOfRows[2][2] = td(p("New C3"));

      final newTable = convertArrayOfRowsToTableNode(originalTable, arrayOfRows);

      final expectedTable = table(
        tr(c(1, 1, "New A1"), c(1, 1, "B1"), c(1, 1, "C1")),
        tr(c(1, 1, "A2"), c(1, 1, "New B2"), c(1, 1, "C2")),
        tr(c(1, 1, "A3"), c(1, 1, "B3"), c(1, 1, "New C3")),
      );

      _expectTableEquals(expectedTable, newTable);
    });

    test("should handle tables with merged cells", () {
      final originalTable = table(
        tr(c(1, 1, "A1"), c(1, 1, "B1"), c(2, 1, "C1")),
        tr(c(1, 1, "A2"), c(2, 1, "B2"), c(1, 2, "D1")),
        tr(c(1, 1, "A3"), c(1, 1, "B3"), c(1, 1, "C3")),
      );

      final arrayOfRows = convertTableNodeToArrayOfRows(originalTable);
      final newTable = convertArrayOfRowsToTableNode(originalTable, arrayOfRows);

      _expectTableEquals(originalTable, newTable);
    });

    test("should handle modified cells in merged table", () {
      final originalTable = table(
        tr(c(1, 1, "A1"), c(1, 1, "B1"), c(2, 1, "C1")),
        tr(c(1, 1, "A2"), c(2, 1, "B2"), c(1, 2, "D1")),
        tr(c(1, 1, "A3"), c(1, 1, "B3"), c(1, 1, "C3")),
      );

      final arrayOfRows = convertTableNodeToArrayOfRows(originalTable);
      // Modify a cell in the merged table
      arrayOfRows[0][2] = td({"colspan": 2, "rowspan": 1, "colwidth": null}, p("Modified C1"));

      final newTable = convertArrayOfRowsToTableNode(originalTable, arrayOfRows);

      final expectedTable = table(
        tr(c(1, 1, "A1"), c(1, 1, "B1"), c(2, 1, "Modified C1")),
        tr(c(1, 1, "A2"), c(2, 1, "B2"), c(1, 2, "D1")),
        tr(c(1, 1, "A3"), c(1, 1, "B3"), c(1, 1, "C3")),
      );

      _expectTableEquals(expectedTable, newTable);
    });

    test("should handle single row table conversion", () {
      final originalTable = table(tr(c(1, 1, "Single"), c(1, 1, "Row"), c(1, 1, "Table")));

      final arrayOfRows = convertTableNodeToArrayOfRows(originalTable);
      // Modify middle cell
      arrayOfRows[0][1] = td(p("Modified"));

      final newTable = convertArrayOfRowsToTableNode(originalTable, arrayOfRows);

      final expectedTable = table(tr(c(1, 1, "Single"), c(1, 1, "Modified"), c(1, 1, "Table")));

      _expectTableEquals(expectedTable, newTable);
    });

    test("should handle single column table conversion", () {
      final originalTable = table(tr(c(1, 1, "A1")), tr(c(1, 1, "A2")), tr(c(1, 1, "A3")));

      final arrayOfRows = convertTableNodeToArrayOfRows(originalTable);
      // Modify middle cell
      arrayOfRows[1][0] = td(p("Modified A2"));

      final newTable = convertArrayOfRowsToTableNode(originalTable, arrayOfRows);

      final expectedTable = table(tr(c(1, 1, "A1")), tr(c(1, 1, "Modified A2")), tr(c(1, 1, "A3")));

      _expectTableEquals(expectedTable, newTable);
    });

    test("should preserve cell attributes when modifying content", () {
      final originalTable = table(
        tr(c(1, 1, "A1"), c(2, 1, "B1")),
        tr(c(1, 2, "A2"), c(1, 1, "B2"), c(1, 1, "C2")),
        tr(c(1, 1, "B3"), c(1, 1, "C3")),
      );

      final arrayOfRows = convertTableNodeToArrayOfRows(originalTable);
      // Modify content while preserving attributes
      arrayOfRows[0][1] = td({"colspan": 2, "rowspan": 1, "colwidth": null}, p("Modified B1"));
      arrayOfRows[1][0] = td({"colspan": 1, "rowspan": 2, "colwidth": null}, p("Modified A2"));

      final newTable = convertArrayOfRowsToTableNode(originalTable, arrayOfRows);

      final expectedTable = table(
        tr(c(1, 1, "A1"), c(2, 1, "Modified B1")),
        tr(c(1, 2, "Modified A2"), c(1, 1, "B2"), c(1, 1, "C2")),
        tr(c(1, 1, "B3"), c(1, 1, "C3")),
      );

      _expectTableEquals(expectedTable, newTable);
    });
  });
}

void _expectTableEquals(Node a, Node b) {
  // a and b are not the same node
  expect(identical(a, b), isFalse);

  // a and b have the same data
  expect(a.eq(b), isTrue);
}
