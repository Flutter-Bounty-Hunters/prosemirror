import 'package:prosemirror/prosemirror.dart';
import 'package:prosemirror/tables.dart';
import 'package:test/test.dart';

import 'build.dart';

void main() {
  group("pastedCells >", () {
    test("returns simple cells", () {
      _testPasted(doc(table(tr("<a>", cEmpty, cEmpty, "<b>"))), 2, 1, [
        [cEmpty, cEmpty],
      ]);
    });

    test("returns cells wrapped in a row", () {
      _testPasted(table("<a>", tr(cEmpty, cEmpty), "<b>"), 2, 1, [
        [cEmpty, cEmpty],
      ]);
    });

    test("returns cells when the cursor is inside them", () {
      _testPasted(table(tr(td(p("<a>foo")), td(p("<b>bar")))), 2, 1, [
        [td(p("foo")), cEmpty],
      ]);
    });

    test("returns multiple rows", () {
      _testPasted(table(tr("<a>", cEmpty, cEmpty), tr(cEmpty, c11), "<b>"), 2, 2, [
        [cEmpty, cEmpty],
        [cEmpty, c11],
      ]);
    });

    test("will enter a fully selected table", () {
      _testPasted(doc("<a>", table(tr(c11)), "<b>"), 1, 1, [
        [c11],
      ]);
    });

    test("can normalize a partially-selected row", () {
      _testPasted(table(tr(td(p(), "<a>"), cEmpty, c11), tr(c11, c11), "<b>"), 2, 2, [
        [cEmpty, c11],
        [c11, c11],
      ]);
    });

    test("will make sure the result is rectangular", () {
      _testPasted(table("<a>", tr(c(2, 2), c11), tr(), tr(c11, c11), "<b>"), 3, 3, [
        [c(2, 2), c11],
        [cEmpty],
        [c11, c11, cEmpty],
      ]);
    });

    test("can handle rowspans sticking out", () {
      _testPasted(table("<a>", tr(c(1, 3), c11), "<b>"), 2, 3, [
        [c(1, 3), c11],
        [cEmpty],
        [cEmpty],
      ]);
    });

    test("returns null for non-cell selection", () {
      _testPasted(doc(p("foo<a>bar"), p("baz<b>")), null, null, null);
    });
  });

  group("clipCells >", () {
    test("can clip off excess cells", () {
      _testClip(table("<a>", tr(cEmpty, c11), tr(c11, c11), "<b>"), 1, 1, [
        [cEmpty],
      ]);
    });

    test("will pad by repeating cells", () {
      _testClip(table("<a>", tr(cEmpty, c11), tr(c11, cEmpty), "<b>"), 4, 4, [
        [cEmpty, c11, cEmpty, c11],
        [c11, cEmpty, c11, cEmpty],
        [cEmpty, c11, cEmpty, c11],
        [c11, cEmpty, c11, cEmpty],
      ]);
    });

    test("takes rowspan into account when counting width", () {
      _testClip(table("<a>", tr(c(2, 2), c11), tr(c11), "<b>"), 6, 2, [
        [c(2, 2), c11, c(2, 2), c11],
        [c11, c11],
      ]);
    });

    test("clips off excess colspan", () {
      _testClip(table("<a>", tr(c(2, 2), c11), tr(c11), "<b>"), 4, 2, [
        [c(2, 2), c11, c(1, 2)],
        [c11],
      ]);
    });

    test("clips off excess rowspan", () {
      _testClip(table("<a>", tr(c(2, 2), c11), tr(c11), "<b>"), 2, 3, [
        [c(2, 2)],
        [],
        [c(2, 1)],
      ]);
    });

    test("clips off excess rowspan when new table height is bigger than the current table height", () {
      _testClip(table("<a>", tr(c(1, 2), c(2, 1)), tr(c11, c11), "<b>"), 3, 1, [
        [c(1, 1), c(2, 1)],
      ]);
    });
  });

  group("insertCells >", () {
    test("keeps the original cells", () {
      _testInsert(
        doc(table(tr(cAnchor, c11, c11), tr(c11, c11, c11))),
        doc(table(tr(td(p("<a>foo")), cEmpty), tr(c(2, 1), "<b>"))),
        doc(table(tr(td(p("foo")), cEmpty, c11), tr(c(2, 1), c11))),
      );
    });

    test("makes sure the table is big enough", () {
      _testInsert(
        doc(table(tr(cAnchor))),
        doc(table(tr(td(p("<a>foo")), cEmpty), tr(c(2, 1), "<b>"))),
        doc(table(tr(td(p("foo")), cEmpty), tr(c(2, 1)))),
      );
    });

    test("preserves headers while growing a table", () {
      _testInsert(
        doc(table(tr(h11, h11, h11), tr(h11, c11, c11), tr(h11, c11, cAnchor))),
        doc(table(tr(td(p("<a>foo")), cEmpty), tr(c11, c11, "<b>"))),
        doc(
          table(
            tr(h11, h11, h11, hEmpty),
            tr(h11, c11, c11, cEmpty),
            tr(h11, c11, td(p("foo")), cEmpty),
            tr(hEmpty, cEmpty, c11, c11),
          ),
        ),
      );
    });

    test("will split interfering rowspan cells", () {
      _testInsert(
        doc(table(tr(c11, c(1, 4), c11), tr(cAnchor, c11), tr(c11, c11), tr(c11, c11))),
        doc(table(tr("<a>", cEmpty, cEmpty, cEmpty, "<b>"))),
        doc(table(tr(c11, c11, c11), tr(cEmpty, cEmpty, cEmpty), tr(c11, td({"rowspan": 2}, p()), c11), tr(c11, c11))),
      );
    });

    test("will split interfering colspan cells", () {
      _testInsert(
        doc(table(tr(c11, cAnchor, c11), tr(c(2, 1), c11), tr(c11, c(2, 1)))),
        doc(table("<a>", tr(cEmpty), tr(cEmpty), tr(cEmpty), "<b>")),
        doc(table(tr(c11, cEmpty, c11), tr(c11, cEmpty, c11), tr(c11, cEmpty, cEmpty))),
      );
    });

    test("preserves widths when splitting", () {
      _testInsert(
        doc(
          table(
            tr(c11, cAnchor, c11),
            tr(
              td({
                "colspan": 3,
                "colwidth": [100, 200, 300],
              }, p("x")),
            ),
          ),
        ),
        doc(table("<a>", tr(cEmpty), tr(cEmpty), "<b>")),
        doc(
          table(
            tr(c11, cEmpty, c11),
            tr(
              td({
                "colwidth": [100],
              }, p("x")),
              cEmpty,
              td({
                "colwidth": [300],
              }, p()),
            ),
          ),
        ),
      );
    });
  });
}

void _testPasted(Node slice, int? width, int? height, [List<List<Node>>? content]) {
  final result = pastedCells(slice.slice(slice.tag["a"]!, slice.tag["b"]));
  if (width == null) {
    expect(result, isNull);
    return;
  }
  if (result == null) {
    throw StateError("Can't paste cells");
  }
  expect(result.rows.length, result.height);
  expect(result.width, width);
  expect(result.height, height);
  if (content != null) {
    for (var i = 0; i < result.rows.length; i++) {
      expect(eq(result.rows[i], Fragment.from(content[i])), isTrue);
    }
  }
}

void _testClip(Node slice, int width, int height, [List<List<Node>>? content]) {
  final result = clipCells(pastedCells(slice.slice(slice.tag["a"]!, slice.tag["b"]))!, width, height);
  expect(result.rows.length, result.height);
  expect(result.width, width);
  expect(result.height, height);
  if (content != null) {
    for (var i = 0; i < result.rows.length; i++) {
      expect(eq(result.rows[i], Fragment.from(content[i])), isTrue);
    }
  }
}

void _testInsert(Node document, Node cells, Node result) {
  if (document.type.name != "doc" || cells.type.name != "doc" || result.type.name != "doc") {
    throw StateError("Invalid test");
  }

  var state = EditorState.create(EditorStateConfig(doc: document));
  final $cell = cellAround(document.resolve(document.tag["anchor"]!));
  if ($cell == null) {
    throw StateError("No cell found");
  }

  Node? tableNode;
  var tableStart = 0;
  document.descendants((node, pos, parent, index) {
    if (node.type.name == "table") {
      tableNode = node;
      tableStart = pos + 1;
    }
    return tableNode == null;
  });

  if (tableNode == null) {
    throw StateError("No table found: $document");
  }

  final map = TableMap.get(tableNode!);
  insertCells(
    state,
    (tr) => state = state.apply(tr),
    tableStart,
    map.findCell($cell.pos - tableStart),
    pastedCells(cells.slice(cells.tag["a"]!, cells.tag["b"]))!,
  );
  expect(eq(state.doc, result), isTrue);
}
