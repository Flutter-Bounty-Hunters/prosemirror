import 'package:prosemirror/tables.dart';
import 'package:test/test.dart';

import 'build.dart';

void main() {
  group("moveRowInArrayOfRows >", () {
    group("single element moves >", () {
      test("should move element down (forward)", () {
        final rows = [0, 1, 2, 3, 4];
        final result = moveRowInArrayOfRows(rows, [1], [3], 0);
        expect(result, [0, 2, 3, 1, 4]);
      });

      test("should move element up (backward)", () {
        final rows = [0, 1, 2, 3, 4];
        final result = moveRowInArrayOfRows(rows, [3], [1], 0);
        expect(result, [0, 3, 1, 2, 4]);
      });

      test("should move first element to end", () {
        final rows = [0, 1, 2, 3];
        final result = moveRowInArrayOfRows(rows, [0], [3], 0);
        expect(result, [1, 2, 3, 0]);
      });

      test("should move last element to beginning", () {
        final rows = [0, 1, 2, 3];
        final result = moveRowInArrayOfRows(rows, [3], [0], 0);
        expect(result, [3, 0, 1, 2]);
      });
    });

    group("multiple element moves >", () {
      test("should move two consecutive elements down", () {
        final rows = [0, 1, 2, 3, 4, 5];
        final result = moveRowInArrayOfRows(rows, [1, 2], [4, 5], 0);
        expect(result, [0, 3, 4, 5, 1, 2]);
      });

      test("should move two consecutive elements up", () {
        final rows = [0, 1, 2, 3, 4, 5];
        final result = moveRowInArrayOfRows(rows, [4, 5], [1, 2], 0);
        expect(result, [0, 4, 5, 1, 2, 3]);
      });

      test("should move three elements", () {
        final rows = [0, 1, 2, 3, 4, 5, 6];
        final result = moveRowInArrayOfRows(rows, [1, 2, 3], [5, 6], 0);
        expect(result, [0, 4, 5, 6, 1, 2, 3]);
      });
    });

    group("direction overrides >", () {
      test("should handle override -1 (force before target)", () {
        final rows = [0, 1, 2, 3, 4, 5];
        final result = moveRowInArrayOfRows(rows, [1], [4], -1);
        expect(result, [0, 2, 3, 1, 4, 5]);
      });

      test("should handle override 0 (natural direction)", () {
        final rows = [0, 1, 2, 3, 4, 5];
        final result = moveRowInArrayOfRows(rows, [1], [4], 0);
        expect(result, [0, 2, 3, 4, 1, 5]);
      });

      test("should handle override +1 (force after target)", () {
        final rows = [0, 1, 2, 3, 4];
        final result = moveRowInArrayOfRows(rows, [3], [1], 1);
        expect(result, [0, 1, 3, 2, 4]);
      });
    });

    group("edge cases >", () {
      test("should handle single element array", () {
        final rows = [0];
        final result = moveRowInArrayOfRows(rows, [0], [0], 0);
        expect(result, [0]);
      });

      test("should handle two element array", () {
        final rows = [0, 1];
        final result = moveRowInArrayOfRows(rows, [0], [1], 0);
        expect(result, [1, 0]);
      });

      test("should handle moving to same position", () {
        final rows = [0, 1, 2, 3];
        final result = moveRowInArrayOfRows(rows, [2], [2], 0);
        expect(result, [0, 1, 2, 3]);
      });

      test("should handle adjacent elements", () {
        final rows = [0, 1, 2, 3];
        final result = moveRowInArrayOfRows(rows, [1], [2], 0);
        expect(result, [0, 2, 1, 3]);
      });
    });

    group("data types >", () {
      test("should work with strings", () {
        final rows = ["a", "b", "c", "d"];
        final result = moveRowInArrayOfRows(rows, [0], [2], 0);
        expect(result, ["b", "c", "a", "d"]);
      });

      test("should work with mixed types", () {
        final rows = <Object?>[1, "a", true, null, 4];
        final result = moveRowInArrayOfRows(rows, [1], [3], 0);
        expect(result, <Object?>[1, true, null, "a", 4]);
      });

      test("should work with table cell nodes", () {
        final rows = [
          [td("0"), td("A")],
          [td("1"), td("B")],
          [td("2"), td("C")],
        ];

        final result = moveRowInArrayOfRows(rows, [2], [0], 0);
        expect(result[0][0].textContent, "2");
        expect(result[1][0].textContent, "0");
        expect(result[2][0].textContent, "1");
      });
    });

    group("complex scenarios >", () {
      test("should handle large arrays", () {
        final rows = List<int>.generate(10, (index) => index);
        final result = moveRowInArrayOfRows(rows, [2, 3, 4], [7, 8, 9], 0);
        expect(result, [0, 1, 5, 6, 7, 8, 9, 2, 3, 4]);
      });

      test("should handle moving entire beginning to end", () {
        final rows = [0, 1, 2, 3, 4];
        final result = moveRowInArrayOfRows(rows, [0, 1, 2], [4], 0);
        expect(result, [3, 4, 0, 1, 2]);
      });

      test("should handle moving entire end to beginning", () {
        final rows = [0, 1, 2, 3, 4];
        final result = moveRowInArrayOfRows(rows, [3, 4], [0, 1], 0);
        expect(result, [3, 4, 0, 1, 2]);
      });
    });
  });
}
