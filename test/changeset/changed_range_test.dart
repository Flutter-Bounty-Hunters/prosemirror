import 'package:prosemirror/prosemirror.dart';
import 'package:test/test.dart';

import '../model/support/builders.dart';

void main() {
  group("ChangeSet > changedRange >", () {
    test("returns null for identical sets", () {
      final made = _make(
        doc(p("foo")),
        (tr) => tr
            .replaceWith(2, 3, schema.text("aaaa"))
            .replaceWith(1, 1, schema.text("xx"))
            .delete(5, 7),
      );
      final set = made.set;
      expect(set.changedRange(set), isNull);
      expect(
        set.changedRange(
          ChangeSet.create(made.document0).addSteps(
            made.transform.doc,
            made.transform.mapping.maps,
            made.data,
          ),
        ),
        isNull,
      );
    });

    test("returns only the changed range in simple cases", () {
      final made = _make(
        doc(p("abcd")),
        (tr) => tr.replaceWith(2, 4, schema.text("u")),
      );
      _same(
        made.set0.changedRange(made.set, made.transform.mapping.maps),
        2,
        3,
      );
    });

    test("expands to cover updated spans", () {
      final made = _make(
        doc(p("abcd")),
        (tr) => tr.replaceWith(2, 2, schema.text("c")).delete(3, 5),
      );
      final set1 = ChangeSet.create(made.document0).addSteps(
        made.transform.docs[1],
        [made.transform.mapping.maps[0]],
        ["a"],
      );
      _same(
        made.set0.changedRange(set1, [made.transform.mapping.maps[0]]),
        2,
        3,
      );
      _same(
        set1.changedRange(made.set, [made.transform.mapping.maps[1]]),
        2,
        3,
      );
    });

    test("detects changes in deletions", () {
      final made = _make(doc(p("abc")), (tr) => tr.delete(2, 3));
      _same(made.set.changedRange(made.set.map((span) => "b")), 2, 2);
    });
  });
}

void _same(({int from, int to})? actual, int from, int to) {
  expect(actual, isNotNull);
  expect(actual!.from, from);
  expect(actual.to, to);
}

({
  Node document0,
  Transform transform,
  List<Object?> data,
  ChangeSet set0,
  ChangeSet set,
})
_make(Node document, Transform Function(Transform) change) {
  final transform = change(Transform(document));
  final data = List<Object?>.filled(transform.steps.length, "a");
  final set0 = ChangeSet.create(document);
  return (
    document0: document,
    transform: transform,
    data: data,
    set0: set0,
    set: set0.addSteps(transform.doc, transform.mapping.maps, data),
  );
}
