import 'package:prosemirror/prosemirror.dart';
import 'package:test/test.dart';

void main() {
  group("mergeChanges >", () {
    test("can merge simple insertions", () {
      _test(
        [
          [1, 1, 1, 2],
        ],
        [
          [1, 1, 1, 2],
        ],
        [
          [1, 1, 1, 3],
        ],
      );
    });

    test("can merge simple deletions", () {
      _test(
        [
          [1, 2, 1, 1],
        ],
        [
          [1, 2, 1, 1],
        ],
        [
          [1, 3, 1, 1],
        ],
      );
    });

    test("can merge insertion before deletion", () {
      _test(
        [
          [2, 3, 2, 2],
        ],
        [
          [1, 1, 1, 2],
        ],
        [
          [1, 1, 1, 2],
          [2, 3, 3, 3],
        ],
      );
    });

    test("can merge insertion after deletion", () {
      _test(
        [
          [2, 3, 2, 2],
        ],
        [
          [2, 2, 2, 3],
        ],
        [
          [2, 3, 2, 3],
        ],
      );
    });

    test("can merge deletion before insertion", () {
      _test(
        [
          [2, 2, 2, 3],
        ],
        [
          [1, 2, 1, 1],
        ],
        [
          [1, 2, 1, 2],
        ],
      );
    });

    test("can merge deletion after insertion", () {
      _test(
        [
          [2, 2, 2, 3],
        ],
        [
          [3, 4, 3, 3],
        ],
        [
          [2, 3, 2, 3],
        ],
      );
    });

    test("can merge deletion of insertion", () {
      _test(
        [
          [2, 2, 2, 3],
        ],
        [
          [2, 3, 2, 2],
        ],
        [],
      );
    });

    test("can merge insertion after replace", () {
      _test(
        [
          [2, 3, 2, 3],
        ],
        [
          [3, 3, 3, 4],
        ],
        [
          [2, 3, 2, 4],
        ],
      );
    });

    test("can merge insertion before replace", () {
      _test(
        [
          [2, 3, 2, 3],
        ],
        [
          [2, 2, 2, 3],
        ],
        [
          [2, 3, 2, 4],
        ],
      );
    });

    test("can merge replace after insert", () {
      _test(
        [
          [2, 2, 2, 3],
        ],
        [
          [2, 3, 2, 3],
        ],
        [
          [2, 2, 2, 3],
        ],
      );
    });
  });
}

void _test(
  List<List<int>> changeA,
  List<List<int>> changeB,
  List<List<int>> expected,
) {
  final merged = Change.merge<int>(
    changeA.map(_range).toList(),
    changeB.map(_range).toList(),
    (a, b) => a,
  );
  final result = merged
      .map((change) => [change.fromA, change.toA, change.fromB, change.toB])
      .toList();
  expect(result, expected);
}

Change<int> _range(List<int> array, [int author = 0]) {
  final fromA = array[0];
  final toA = array[1];
  final fromB = array.length > 2 ? array[2] : array[0];
  final toB = array.length > 2 ? array[3] : array[1];
  return Change<int>(
    fromA,
    toA,
    fromB,
    toB,
    [Span<int>(toA - fromA, author)],
    [Span<int>(toB - fromB, author)],
  );
}
