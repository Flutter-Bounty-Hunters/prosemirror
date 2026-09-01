import 'package:prosemirror/tables.dart';
import 'package:test/test.dart';

void main() {
  group("transpose >", () {
    final arr = [
      ["a1", "a2", "a3"],
      ["b1", "b2", "b3"],
      ["c1", "c2", "c3"],
      ["d1", "d2", "d3"],
    ];

    final expected = [
      ["a1", "b1", "c1", "d1"],
      ["a2", "b2", "c2", "d2"],
      ["a3", "b3", "c3", "d3"],
    ];

    test("should invert columns to rows", () {
      expect(transpose(arr), expected);
    });

    test("should guarantee the reflection to be true", () {
      expect(transpose(expected), arr);
    });
  });
}
