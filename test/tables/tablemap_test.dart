import 'package:prosemirror/tables.dart';
import 'package:test/test.dart';

import 'build.dart';

void main() {
  group("TableMap >", () {
    test("finds the right shape for a simple table", () {
      expect(
        TableMap.get(table(tr(c11, c11, c11), tr(c11, c11, c11), tr(c11, c11, c11), tr(c11, c11, c11))).map.join(", "),
        "1, 6, 11, 18, 23, 28, 35, 40, 45, 52, 57, 62",
      );
    });

    test("finds the right shape for colspans", () {
      expect(
        TableMap.get(table(tr(c11, c(2, 1)), tr(c(2, 1), c11), tr(c11, c11, c11))).map.join(", "),
        "1, 6, 6, 13, 13, 18, 25, 30, 35",
      );
    });

    test("finds the right shape for rowspans", () {
      expect(TableMap.get(table(tr(c(1, 2), c11, c(1, 2)), tr(c11))).map.join(", "), "1, 6, 11, 1, 18, 11");
    });

    test("finds the right shape for deep rowspans", () {
      expect(
        TableMap.get(table(tr(c(1, 4), c(2, 1)), tr(c(1, 2), c(1, 2)), tr())).map.join(", "),
        "1, 6, 6, 1, 13, 18, 1, 13, 18",
      );
    });

    test("finds the right shape for larger rectangles", () {
      expect(
        TableMap.get(table(tr(c11, c(4, 4)), tr(c11), tr(c11), tr(c11))).map.join(", "),
        "1, 6, 6, 6, 6, 13, 6, 6, 6, 6, 20, 6, 6, 6, 6, 27, 6, 6, 6, 6",
      );
    });

    final map = TableMap.get(table(tr(c(2, 3), c11, c(1, 2)), tr(c11), tr(c(2, 1))));
    //  1  1  6 11
    //  1  1 18 11
    //  1  1 25 25

    test("can accurately find cell sizes", () {
      expect(map.width, 4);
      expect(map.height, 3);
      expect(_rectEquals(map.findCell(1), 0, 0, 2, 3), isTrue);
      expect(_rectEquals(map.findCell(6), 2, 0, 3, 1), isTrue);
      expect(_rectEquals(map.findCell(11), 3, 0, 4, 2), isTrue);
      expect(_rectEquals(map.findCell(18), 2, 1, 3, 2), isTrue);
      expect(_rectEquals(map.findCell(25), 2, 2, 4, 3), isTrue);
    });

    test("can find the rectangle between two cells", () {
      expect(map.cellsInRect(map.rectBetween(1, 6)).join(", "), "1, 6, 18, 25");
      expect(map.cellsInRect(map.rectBetween(1, 25)).join(", "), "1, 6, 11, 18, 25");
      expect(map.cellsInRect(map.rectBetween(1, 1)).join(", "), "1");
      expect(map.cellsInRect(map.rectBetween(6, 25)).join(", "), "6, 11, 18, 25");
      expect(map.cellsInRect(map.rectBetween(6, 11)).join(", "), "6, 11, 18");
      expect(map.cellsInRect(map.rectBetween(11, 6)).join(", "), "6, 11, 18");
      expect(map.cellsInRect(map.rectBetween(18, 25)).join(", "), "18, 25");
      expect(map.cellsInRect(map.rectBetween(6, 18)).join(", "), "6, 18");
    });

    test("can find adjacent cells", () {
      expect(map.nextCell(1, "horiz", 1), 6);
      expect(map.nextCell(1, "horiz", -1), isNull);
      expect(map.nextCell(1, "vert", 1), isNull);
      expect(map.nextCell(1, "vert", -1), isNull);

      expect(map.nextCell(18, "horiz", 1), 11);
      expect(map.nextCell(18, "horiz", -1), 1);
      expect(map.nextCell(18, "vert", 1), 25);
      expect(map.nextCell(18, "vert", -1), 6);

      expect(map.nextCell(25, "vert", 1), isNull);
      expect(map.nextCell(25, "vert", -1), 18);
      expect(map.nextCell(25, "horiz", 1), isNull);
      expect(map.nextCell(25, "horiz", -1), 1);
    });
  });
}

bool _rectEquals(Rect rect, int left, int top, int right, int bottom) {
  return rect.left == left && rect.top == top && rect.right == right && rect.bottom == bottom;
}
