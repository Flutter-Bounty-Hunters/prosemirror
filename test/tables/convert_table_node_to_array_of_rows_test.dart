import 'package:prosemirror/prosemirror.dart';
import 'package:prosemirror/tables.dart';
import 'package:test/test.dart';

import 'build.dart';

void main() {
  group("convertTableNodeToArrayOfRows >", () {
    test("should convert a simple table to array of rows", () {
      final tableNode = table(tr(td("A1"), td("B1")), tr(td("A2"), td("B2")));

      expect(_convert(tableNode), [
        ["A1", "B1"],
        ["A2", "B2"],
      ]);
    });

    test("should handle empty cells", () {
      final tableNode = table(tr(td("A1"), td()), tr(td(), td("B2")));

      expect(_convert(tableNode), [
        ["A1", ""],
        ["", "B2"],
      ]);
    });

    test("should handle tables with equal row lengths", () {
      final tableNode = table(tr(td("A1"), td("B1"), td("C1")), tr(td("A2"), td("B2"), td("C2")));

      expect(_convert(tableNode), [
        ["A1", "B1", "C1"],
        ["A2", "B2", "C2"],
      ]);
    });

    test("should handle single row table", () {
      final tableNode = table(tr(td("Single"), td("Row")));

      expect(_convert(tableNode), [
        ["Single", "Row"],
      ]);
    });

    test("should handle single column table", () {
      final tableNode = table(tr(td("A1")), tr(td("A2")), tr(td("A3")));

      expect(_convert(tableNode), [
        ["A1"],
        ["A2"],
        ["A3"],
      ]);
    });

    test("should handle table with merged cells", () {
      // ┌──────┬──────┬─────────────┐
      // │  A1  │  B1  │     C1      │
      // ├──────┼──────┴──────┬──────┤
      // │  A2  │     B2      │      │
      // ├──────┼─────────────┤  D1  │
      // │  A3  │  B3  │  C3  │      │
      // └──────┴──────┴──────┴──────┘
      final tableNode = table(
        tr(td("A1"), td("B1"), td({"colspan": 2}, p("C1"))),
        tr(td("A2"), td({"colspan": 2}, p("B2")), td({"rowspan": 2}, p("D1"))),
        tr(td("A3"), td("B3"), td("C3")),
      );

      expect(_convert(tableNode), [
        ["A1", "B1", "C1", null],
        ["A2", "B2", null, "D1"],
        ["A3", "B3", "C3", null],
      ]);
    });
  });
}

List<List<String?>> _convert(Node tableNode) {
  final rows = convertTableNodeToArrayOfRows(tableNode);
  return rows.map((row) => row.map((cell) => cell?.textContent).toList()).toList();
}
