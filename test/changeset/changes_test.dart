import 'package:prosemirror/prosemirror.dart';
import 'package:test/test.dart';

import '../model/support/builders.dart';

void main() {
  group("ChangeSet >", () {
    test("finds a single insertion", () {
      _find(
        doc(p("hello")),
        [(tr) => tr.insert(3, _text("XY"))],
        [
          [3, 3, 3, 5],
        ],
      );
    });

    test("finds a single deletion", () {
      _find(
        doc(p("hello")),
        [(tr) => tr.delete(3, 5)],
        [
          [3, 5, 3, 3],
        ],
      );
    });

    test("identifies a replacement", () {
      _find(
        doc(p("hello")),
        [(tr) => tr.replaceWith(3, 5, _text("juj"))],
        [
          [3, 5, 3, 6],
        ],
      );
    });

    test("merges adjacent canceling edits", () {
      _find(doc(p("hello")), [
        (tr) => tr.delete(3, 5).insert(3, _text("ll")),
      ], []);
    });

    test("doesn't crash when cancelling edits are followed by others", () {
      _find(
        doc(p("hello")),
        [(tr) => tr.delete(2, 3).insert(2, _text("e")).delete(5, 6)],
        [
          [5, 6, 5, 5],
        ],
      );
    });

    test("stops handling an inserted span after collapsing it", () {
      _find(
        doc(p("abcba")),
        [(tr) => tr.insert(2, _text("b")).insert(6, _text("b")).delete(3, 6)],
        [
          [3, 4, 3, 3],
        ],
      );
    });

    test("partially merges insert at start", () {
      _find(
        doc(p("helLo")),
        [(tr) => tr.delete(3, 5).insert(3, _text("l"))],
        [
          [4, 5, 4, 4],
        ],
      );
    });

    test("partially merges insert at end", () {
      _find(
        doc(p("helLo")),
        [(tr) => tr.delete(3, 5).insert(3, _text("L"))],
        [
          [3, 4, 3, 3],
        ],
      );
    });

    test("partially merges delete at start", () {
      _find(
        doc(p("abc")),
        [(tr) => tr.insert(3, _text("xyz")).delete(3, 4)],
        [
          [3, 3, 3, 5],
        ],
      );
    });

    test("partially merges delete at end", () {
      _find(
        doc(p("abc")),
        [(tr) => tr.insert(3, _text("xyz")).delete(5, 6)],
        [
          [3, 3, 3, 5],
        ],
      );
    });

    test("finds multiple insertions", () {
      _find(
        doc(p("abc")),
        [(tr) => tr.insert(1, _text("x")).insert(5, _text("y"))],
        [
          [1, 1, 1, 2],
          [4, 4, 5, 6],
        ],
      );
    });

    test("finds multiple deletions", () {
      _find(
        doc(p("xyz")),
        [(tr) => tr.delete(1, 2).delete(2, 3)],
        [
          [1, 2, 1, 1],
          [3, 4, 2, 2],
        ],
      );
    });

    test("identifies a deletion between insertions", () {
      _find(
        doc(p("zyz")),
        [(tr) => tr.insert(2, _text("A")).insert(4, _text("B")).delete(3, 4)],
        [
          [2, 3, 2, 4],
        ],
      );
    });

    test("can add a deletion in a new addStep call", () {
      _find(
        doc(p("hello")),
        [(tr) => tr.delete(1, 2), (tr) => tr.delete(2, 3)],
        [
          [1, 2, 1, 1],
          [3, 4, 2, 2],
        ],
      );
    });

    test("merges delete/insert from different addStep calls", () {
      _find(doc(p("hello")), [
        (tr) => tr.delete(3, 5),
        (tr) => tr.insert(3, _text("ll")),
      ], []);
    });

    test("revert a deletion by inserting the character again", () {
      _find(
        doc(p("bar")),
        [
          (tr) => tr.delete(2, 3),
          (tr) => tr.insert(2, _text("x")),
          (tr) => tr.insert(2, _text("a")),
        ],
        [
          [3, 3, 3, 4],
        ],
      );
    });

    test("insert character before changed character", () {
      _find(
        doc(p("bar")),
        [
          (tr) => tr.delete(2, 3),
          (tr) => tr.insert(2, _text("x")),
          (tr) => tr.insert(2, _text("x")),
        ],
        [
          [2, 3, 2, 4],
        ],
      );
    });

    test("partially merges delete/insert from different addStep calls", () {
      _find(
        doc(p("heljo")),
        [(tr) => tr.delete(3, 5), (tr) => tr.insert(3, _text("ll"))],
        [
          [4, 5, 4, 5],
        ],
      );
    });

    test("merges insert/delete from different addStep calls", () {
      _find(doc(p("ok")), [
        (tr) => tr.insert(2, _text("--")),
        (tr) => tr.delete(2, 4),
      ], []);
    });

    test("partially merges insert/delete from different addStep calls", () {
      _find(
        doc(p("ok")),
        [(tr) => tr.insert(2, _text("--")), (tr) => tr.delete(2, 3)],
        [
          [2, 2, 2, 3],
        ],
      );
    });

    test("maps deletions forward", () {
      _find(
        doc(p("foobar")),
        [(tr) => tr.delete(5, 6), (tr) => tr.insert(1, _text("OKAY"))],
        [
          [1, 1, 1, 5],
          [5, 6, 9, 9],
        ],
      );
    });

    test("can incrementally undo then redo", () {
      _find(
        doc(p("bar")),
        [
          (tr) => tr.delete(2, 3),
          (tr) => tr.insert(2, _text("a")),
          (tr) => tr.delete(2, 3),
        ],
        [
          [2, 3, 2, 2],
        ],
      );
    });

    test("can map through complicated changesets", () {
      _find(
        doc(p("12345678901234")),
        [
          (tr) => tr
              .delete(9, 12)
              .insert(6, _text("xyz"))
              .replaceWith(2, 3, _text("uv")),
          (tr) => tr.delete(14, 15).insert(13, _text("90")).delete(8, 9),
        ],
        [
          [2, 3, 2, 4],
          [6, 6, 7, 9],
          [11, 12, 14, 14],
          [13, 14, 15, 15],
        ],
      );
    });

    test("computes a proper diff of the changes", () {
      _find(
        doc(p("abcd"), p("efgh")),
        [(tr) => tr.delete(2, 10).insert(2, _text("cdef"))],
        [
          [2, 3, 2, 2],
          [5, 7, 4, 4],
          [9, 10, 6, 6],
        ],
      );
    });

    test("handles re-adding content step by step", () {
      _find(
        doc(p("one two three")),
        [
          (tr) => tr.delete(1, 14),
          (tr) => tr.insert(1, _text("two")),
          (tr) => tr.insert(4, _text(" ")),
          (tr) => tr.insert(5, _text("three")),
        ],
        [
          [1, 5, 1, 1],
        ],
      );
    });

    test("doesn't get confused by split deletions", () {
      _find(
        doc(blockquote(h1("one"), p("two four"))),
        [
          (tr) => tr.delete(7, 11),
          (tr) => tr.replaceWith(0, 13, blockquote(h1("one"), p("four"))),
        ],
        [
          [
            7,
            11,
            7,
            7,
            [
              [4, 0],
            ],
            [],
          ],
        ],
        true,
      );
    });

    test("doesn't get confused by multiply split deletions", () {
      _find(
        doc(blockquote(h1("one"), p("two three"))),
        [
          (tr) => tr.delete(14, 16),
          (tr) => tr.delete(7, 11),
          (tr) => tr.delete(3, 5),
          (tr) => tr.replaceWith(0, 10, blockquote(h1("o"), p("thr"))),
        ],
        [
          [
            3,
            5,
            3,
            3,
            [
              [2, 2],
            ],
            [],
          ],
          [
            8,
            12,
            6,
            6,
            [
              [3, 1],
              [1, 3],
            ],
            [],
          ],
          [
            14,
            16,
            8,
            8,
            [
              [2, 0],
            ],
            [],
          ],
        ],
        true,
      );
    });

    test("won't lose the order of overlapping changes", () {
      _find(
        doc(p("12345")),
        [
          (tr) => tr.delete(4, 5),
          (tr) => tr.replaceWith(2, 2, _text("a")),
          (tr) => tr.delete(1, 6),
          (tr) => tr.replaceWith(1, 1, _text("1a235")),
        ],
        [
          [
            2,
            2,
            2,
            3,
            [],
            [
              [1, 1],
            ],
          ],
          [
            4,
            5,
            5,
            5,
            [
              [1, 0],
            ],
            [],
          ],
        ],
        [0, 0, 1, 1],
      );
    });

    test("properly maps deleted positions", () {
      _find(
        doc(p("jTKqvPrzApX")),
        [
          (tr) => tr.delete(8, 11),
          (tr) => tr.replaceWith(1, 1, _text("MPu")),
          (tr) => tr.delete(2, 12),
          (tr) => tr.replaceWith(2, 2, _text("PujTKqvPrX")),
        ],
        [
          [
            1,
            1,
            1,
            4,
            [],
            [
              [3, 2],
            ],
          ],
          [
            8,
            11,
            11,
            11,
            [
              [3, 1],
            ],
            [],
          ],
        ],
        [1, 2, 2, 2],
      );
    });

    test("fuzz issue 1", () {
      _find(
        doc(p("hzwiKqBPzn")),
        [
          (tr) => tr.delete(3, 7),
          (tr) => tr.replaceWith(5, 5, _text("LH")),
          (tr) => tr.replaceWith(6, 6, _text("uE")),
          (tr) => tr.delete(1, 6),
          (tr) => tr.delete(3, 6),
        ],
        [
          [
            1,
            11,
            1,
            3,
            [
              [2, 1],
              [4, 0],
              [2, 1],
              [2, 0],
            ],
            [
              [2, 0],
            ],
          ],
        ],
        [0, 1, 0, 1, 0],
      );
    });

    test("fuzz issue 2", () {
      _find(
        doc(p("eAMISWgauf")),
        [
          (tr) => tr.delete(5, 10),
          (tr) => tr.replaceWith(5, 5, _text("KkM")),
          (tr) => tr.replaceWith(3, 3, _text("UDO")),
          (tr) => tr.delete(1, 12),
          (tr) => tr.replaceWith(1, 1, _text("eAUDOMIKkMf")),
          (tr) => tr.delete(5, 8),
          (tr) => tr.replaceWith(3, 3, _text("qX")),
        ],
        [
          [
            3,
            10,
            3,
            10,
            [
              [2, 0],
              [5, 2],
            ],
            [
              [7, 0],
            ],
          ],
        ],
        [2, 0, 0, 0, 0, 0, 0],
      );
    });

    test("fuzz issue 3", () {
      _find(
        doc(p("hfxjahnOuH")),
        [
          (tr) => tr.delete(1, 5),
          (tr) => tr.replaceWith(3, 3, _text("X")),
          (tr) => tr.delete(1, 8),
          (tr) => tr.replaceWith(1, 1, _text("ahXnOuH")),
          (tr) => tr.delete(2, 4),
          (tr) => tr.replaceWith(2, 2, _text("tn")),
          (tr) => tr.delete(5, 7),
          (tr) => tr.delete(1, 6),
          (tr) => tr.replaceWith(1, 1, _text("atnnH")),
          (tr) => tr.delete(2, 6),
        ],
        [
          [
            1,
            11,
            1,
            2,
            [
              [4, 1],
              [1, 0],
              [1, 1],
              [1, 0],
              [2, 1],
              [1, 0],
            ],
            [
              [1, 0],
            ],
          ],
        ],
        [1, 0, 1, 1, 1, 1, 1, 0, 0, 0],
      );
    });

    test("correctly handles steps with multiple map entries", () {
      _find(
        doc(p()),
        [
          (tr) => tr.replaceWith(1, 1, _text("ab")),
          (tr) => tr.wrap(tr.doc.resolve(1).blockRange()!, [
            (type: schema.nodes["blockquote"]!, attrs: null),
          ]),
        ],
        [
          [0, 0, 0, 1],
          [1, 1, 2, 4],
          [2, 2, 5, 6],
        ],
      );
    });
  });
}

void _find(
  Node document,
  List<void Function(Transform)> builds,
  List<Object> changes, [
  Object? separator,
]) {
  var set = ChangeSet.create(document);
  var currentDocument = document;
  for (var index = 0; index < builds.length; index++) {
    final transform = Transform(currentDocument);
    builds[index](transform);
    set = set.addSteps(
      transform.doc,
      transform.mapping.maps,
      _dataFor(separator, index),
    );
    currentDocument = transform.doc;
  }

  final owner =
      separator != null &&
      changes.isNotEmpty &&
      (changes[0] as List).length > 4;
  final actual = <List<Object>>[];
  for (final change in set.changes) {
    final entry = <Object>[change.fromA, change.toA, change.fromB, change.toB];
    if (owner) {
      entry.add([
        for (final span in change.deleted) [span.length, span.data],
      ]);
      entry.add([
        for (final span in change.inserted) [span.length, span.data],
      ]);
    }
    actual.add(entry);
  }
  expect(actual, changes);
}

Object _dataFor(Object? separator, int index) {
  if (separator == null) {
    return 0;
  }
  if (separator is List) {
    return separator[index] as int;
  }
  return index;
}

Node _text(String string) => schema.text(string);
