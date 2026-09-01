import 'package:prosemirror/prosemirror.dart';
import 'package:test/test.dart';

void main() {
  group("Mapping >", () {
    test("can map through a single insertion", () {
      _testMapping(
        _mk([
          [2, 0, 4],
        ], []),
        [
          [0, 0],
          [2, 6],
          [2, 2, -1],
          [3, 7],
        ],
      );
    });

    test("can map through a single deletion", () {
      _testMapping(
        _mk([
          [2, 4, 0],
        ], []),
        [
          [0, 0],
          [2, 2, -1],
          [3, 2, 1, true],
          [6, 2, 1],
          [6, 2, -1, true],
          [7, 3],
        ],
      );
    });

    test("can map through a single replace", () {
      _testMapping(
        _mk([
          [2, 4, 4],
        ], []),
        [
          [0, 0],
          [2, 2, 1],
          [4, 6, 1, true],
          [4, 2, -1, true],
          [6, 6, -1],
          [8, 8],
        ],
      );
    });

    test("can map through a mirrorred delete-insert", () {
      _testMapping(
        _mk(
          [
            [2, 4, 0],
            [2, 0, 4],
          ],
          [
            {0: 1},
          ],
        ),
        [
          [0, 0],
          [2, 2],
          [4, 4],
          [6, 6],
          [7, 7],
        ],
      );
    });

    test("cap map through a mirrorred insert-delete", () {
      _testMapping(
        _mk(
          [
            [2, 0, 4],
            [2, 4, 0],
          ],
          [
            {0: 1},
          ],
        ),
        [
          [0, 0],
          [2, 2],
          [3, 3],
        ],
      );
    });

    test("can map through an delete-insert with an insert in between", () {
      _testMapping(
        _mk(
          [
            [2, 4, 0],
            [1, 0, 1],
            [3, 0, 4],
          ],
          [
            {0: 2},
          ],
        ),
        [
          [0, 0],
          [1, 2],
          [4, 5],
          [6, 7],
          [7, 8],
        ],
      );
    });

    test("assigns the correct deleted flags when deletions happen before", () {
      _testDel(
        _mk([
          [0, 2, 0],
        ], []),
        2,
        -1,
        "db",
      );
      _testDel(
        _mk([
          [0, 2, 0],
        ], []),
        2,
        1,
        "b",
      );
      _testDel(
        _mk([
          [0, 2, 2],
        ], []),
        2,
        -1,
        "db",
      );
      _testDel(
        _mk([
          [0, 1, 0],
          [0, 1, 0],
        ], []),
        2,
        -1,
        "db",
      );
      _testDel(
        _mk([
          [0, 1, 0],
        ], []),
        2,
        -1,
        "",
      );
    });

    test("assigns the correct deleted flags when deletions happen after", () {
      _testDel(
        _mk([
          [2, 2, 0],
        ], []),
        2,
        -1,
        "a",
      );
      _testDel(
        _mk([
          [2, 2, 0],
        ], []),
        2,
        1,
        "da",
      );
      _testDel(
        _mk([
          [2, 2, 2],
        ], []),
        2,
        1,
        "da",
      );
      _testDel(
        _mk([
          [2, 1, 0],
          [2, 1, 0],
        ], []),
        2,
        1,
        "da",
      );
      _testDel(
        _mk([
          [3, 2, 0],
        ], []),
        2,
        -1,
        "",
      );
    });

    test("assigns the correct deleted flags when deletions happen across", () {
      _testDel(
        _mk([
          [0, 4, 0],
        ], []),
        2,
        -1,
        "dbax",
      );
      _testDel(
        _mk([
          [0, 4, 0],
        ], []),
        2,
        1,
        "dbax",
      );
      _testDel(
        _mk([
          [0, 4, 0],
        ], []),
        2,
        1,
        "dbax",
      );
      _testDel(
        _mk([
          [0, 1, 0],
          [4, 1, 0],
          [0, 3, 0],
        ], []),
        2,
        1,
        "dbax",
      );
    });

    test("assigns the correct deleted flags when deletions happen around", () {
      _testDel(
        _mk([
          [4, 1, 0],
          [0, 1, 0],
        ], []),
        2,
        -1,
        "",
      );
      _testDel(
        _mk([
          [2, 1, 0],
          [0, 2, 0],
        ], []),
        2,
        -1,
        "dba",
      );
      _testDel(
        _mk([
          [2, 1, 0],
          [0, 1, 0],
        ], []),
        2,
        -1,
        "a",
      );
      _testDel(
        _mk([
          [3, 1, 0],
          [0, 2, 0],
        ], []),
        2,
        -1,
        "db",
      );
    });
  });
}

Mapping _mk(List<List<int>> maps, List<Map<int, int>> mirrors) {
  final mapping = Mapping();
  for (final ranges in maps) {
    mapping.appendMap(StepMap(ranges));
  }
  for (final mirror in mirrors) {
    mirror.forEach((from, to) {
      mapping.setMirror(from, to);
    });
  }
  return mapping;
}

void _testMapping(Mapping mapping, List<List<Object?>> cases) {
  final inverted = mapping.invert();
  for (final testCase in cases) {
    final from = testCase[0] as int;
    final to = testCase[1] as int;
    final bias = testCase.length > 2 && testCase[2] != null ? testCase[2] as int : 1;
    final lossy = testCase.length > 3 && testCase[3] == true;
    expect(mapping.map(from, bias), to);
    if (!lossy) {
      expect(inverted.map(to, bias), from);
    }
  }
}

void _testDel(Mapping mapping, int pos, int side, String flags) {
  final result = mapping.mapResult(pos, side);
  var found = "";
  if (result.deleted) {
    found += "d";
  }
  if (result.deletedBefore) {
    found += "b";
  }
  if (result.deletedAfter) {
    found += "a";
  }
  if (result.deletedAcross) {
    found += "x";
  }
  expect(found, flags);
}
