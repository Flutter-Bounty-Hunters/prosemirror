import 'package:prosemirror/prosemirror.dart';
import 'package:prosemirror/tables.dart';
import 'package:test/test.dart';

import 'build.dart';

void main() {
  group("fixTable >", () {
    test("doesn't touch correct tables", () {
      expect(_fix(table(tr(c11, c11, c(1, 2)), tr(c11, c11))), isNull);
    });

    test("adds trivially missing cells", () {
      expect(eq(_fix(table(tr(c11, c11, c(1, 2)), tr(c11))), table(tr(c11, c11, c(1, 2)), tr(c11, cEmpty))), isTrue);
    });

    test("can add to multiple rows", () {
      expect(
        eq(
          _fix(table(tr(c11), tr(c11, c11), tr(c(3, 1)))),
          table(tr(c11, cEmpty, cEmpty), tr(cEmpty, c11, c11), tr(c(3, 1))),
        ),
        isTrue,
      );
    });

    test("will default to adding at the start of the first row", () {
      expect(eq(_fix(table(tr(c11), tr(c11, c11))), table(tr(cEmpty, c11), tr(c11, c11))), isTrue);
    });

    test("will default to adding at the end of the non-first row", () {
      expect(eq(_fix(table(tr(c11, c11), tr(c11))), table(tr(c11, c11), tr(c11, cEmpty))), isTrue);
    });

    test("will fix overlapping cells", () {
      expect(
        eq(_fix(table(tr(c11, c(1, 2), c11), tr(c(2, 1)))), table(tr(c11, c(1, 2), c11), tr(c11, cEmpty, cEmpty))),
        isTrue,
      );
    });

    test("will fix a rowspan that sticks out of the table", () {
      expect(eq(_fix(table(tr(c11, c11), tr(c(1, 2), c11))), table(tr(c11, c11), tr(c11, c11))), isTrue);
    });

    test("makes sure column widths are coherent", () {
      expect(
        eq(
          _fix(table(tr(c11, c11, _cw200), tr(_cw100, c11, c11))),
          table(tr(_cw100, c11, _cw200), tr(_cw100, c11, _cw200)),
        ),
        isTrue,
      );
    });

    test("can update column widths on colspan cells", () {
      expect(
        eq(
          _fix(table(tr(c11, c11, _cw200), tr(c(3, 2)), tr())),
          table(
            tr(c11, c11, _cw200),
            tr(
              td({
                "colspan": 3,
                "rowspan": 2,
                "colwidth": [0, 0, 200],
              }, p("x")),
            ),
            tr(),
          ),
        ),
        isTrue,
      );
    });

    test("will update the odd one out when column widths disagree", () {
      expect(
        eq(
          _fix(table(tr(_cw100, _cw100, _cw100), tr(_cw200, _cw200, _cw100), tr(_cw100, _cw200, _cw200))),
          table(tr(_cw100, _cw200, _cw100), tr(_cw100, _cw200, _cw100), tr(_cw100, _cw200, _cw100)),
        ),
        isTrue,
      );
    });

    test("respects table role when inserting a cell", () {
      expect(
        eq(
          _fix(table(tr(h11), tr(c11, c11), tr(c(3, 1)))),
          table(tr(h11, hEmpty, hEmpty), tr(cEmpty, c11, c11), tr(c(3, 1))),
        ),
        isTrue,
      );
    });

    test("will remove zero-sized table", () {
      expect(eq(_fix(doc(table(tr()), table(tr(c11)))), doc(table(tr(c11)))), isTrue);
    });
  });
}

final Node _cw100 = td({
  "colwidth": [100],
}, p("x"));
final Node _cw200 = td({
  "colwidth": [200],
}, p("x"));

Node? _fix(Node node) {
  final isDoc = node.type == node.type.schema.topNodeType;
  final state = EditorState.create(EditorStateConfig(doc: isDoc ? node : doc(node)));
  final transaction = fixTables(state);
  if (transaction == null) {
    return null;
  }
  return isDoc ? transaction.doc : transaction.doc.firstChild;
}
