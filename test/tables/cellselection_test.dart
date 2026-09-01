import 'package:prosemirror/prosemirror.dart';
import 'package:prosemirror/tables.dart';
import 'package:test/test.dart';

import 'build.dart';

void main() {
  group("CellSelection >", () {
    test("will put its head/anchor around the head cell", () {
      var s = CellSelection.create(_cellSelectionDoc, 2, 24);
      expect(s.anchor, 25);
      expect(s.head, 27);
      s = CellSelection.create(_cellSelectionDoc, 24, 2);
      expect(s.anchor, 3);
      expect(s.head, 5);
      s = CellSelection.create(_cellSelectionDoc, 10, 30);
      expect(s.anchor, 31);
      expect(s.head, 33);
      s = CellSelection.create(_cellSelectionDoc, 30, 10);
      expect(s.anchor, 11);
      expect(s.head, 13);
    });

    test("extends a row selection when adding a row", () {
      var sel = _run(34, 6, addRowBefore).selection as CellSelection;
      expect(sel.$anchorCell.pos, 48);
      expect(sel.$headCell.pos, 6);
      sel = _run(6, 30, addRowAfter).selection as CellSelection;
      expect(sel.$anchorCell.pos, 6);
      expect(sel.$headCell.pos, 44);
    });

    test("extends a col selection when adding a column", () {
      var sel = _run(16, 24, addColumnAfter).selection as CellSelection;
      expect(sel.$anchorCell.pos, 20);
      expect(sel.$headCell.pos, 32);
      sel = _run(24, 30, addColumnBefore).selection as CellSelection;
      expect(sel.$anchorCell.pos, 32);
      expect(sel.$headCell.pos, 38);
    });
  });

  group("CellSelection.content >", () {
    test("contains only the selected cells", () {
      expect(
        eq(
          selectionFor(table(tr(c11, cAnchor, cEmpty), tr(c11, cEmpty, cHead), tr(c11, c11, c11))).content(),
          _slice(table("<a>", tr(c11, cEmpty), tr(cEmpty, c11))),
        ),
        isTrue,
      );
    });

    test("understands spanning cells", () {
      expect(
        eq(
          selectionFor(table(tr(cAnchor, c(2, 2), c11, c11), tr(c11, cHead, c11, c11))).content(),
          _slice(table(tr(c11, c(2, 2), c11), tr(c11, c11))),
        ),
        isTrue,
      );
    });

    test("cuts off cells sticking out horizontally", () {
      expect(
        eq(
          selectionFor(table(tr(c11, cAnchor, c(2, 1)), tr(c(4, 1)), tr(c(2, 1), cHead, c11))).content(),
          _slice(table(tr(c11, c11), tr(td({"colspan": 2}, p())), tr(cEmpty, c11))),
        ),
        isTrue,
      );
    });

    test("cuts off cells sticking out vertically", () {
      expect(
        eq(
          selectionFor(table(tr(c11, c(1, 4), c(1, 2)), tr(cAnchor), tr(c(1, 2), cHead), tr(c11))).content(),
          _slice(table(tr(c11, td({"rowspan": 2}, p()), cEmpty), tr(c11, c11))),
        ),
        isTrue,
      );
    });

    test("preserves column widths", () {
      expect(
        eq(
          selectionFor(
            table(
              tr(c11, cAnchor, c11),
              tr(
                td({
                  "colspan": 3,
                  "colwidth": [100, 200, 300],
                }, p("x")),
              ),
              tr(c11, cHead, c11),
            ),
          ).content(),
          _slice(
            table(
              tr(c11),
              tr(
                td({
                  "colwidth": [200],
                }, p()),
              ),
              tr(c11),
            ),
          ),
        ),
        isTrue,
      );
    });
  });
}

final Node _cellSelectionDoc = doc(
  table(
    tr(/* 2*/ cEmpty, /* 6*/ cEmpty, /*10*/ cEmpty),
    tr(/*16*/ cEmpty, /*20*/ cEmpty, /*24*/ cEmpty),
    tr(/*30*/ cEmpty, /*34*/ cEmpty, /*36*/ cEmpty),
  ),
);

EditorState _run(int anchor, int head, Command command) {
  var state = EditorState.create(
    EditorStateConfig(doc: _cellSelectionDoc, selection: CellSelection.create(_cellSelectionDoc, anchor, head)),
  );
  command.execute(state, (tr) => state = state.apply(tr));
  return state;
}

Slice _slice(Node document) {
  return Slice(document.content, 1, 1);
}
