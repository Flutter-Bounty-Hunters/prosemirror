import 'package:prosemirror/prosemirror.dart';
import 'package:test/test.dart';

import '../model/support/builders.dart';

void main() {
  group("Rebasing collaborative steps >", () {
    test("supports concurrent typing", () {
      _rebaseAllOrders(doc(p("h<1>ell<2>o")), [
        (transform) => _type(transform, 2, "X"),
        (transform) => _type(transform, 5, "Y"),
      ], doc(p("hX<1>ellY<2>o")));
    });

    test("supports multiple concurrently typed characters", () {
      _rebaseAllOrders(doc(p("h<1>ell<2>o")), [
        (transform) => _type(_type(_type(transform, 2, "X"), 3, "Y"), 4, "Z"),
        (transform) => _type(_type(transform, 5, "U"), 6, "V"),
      ], doc(p("hXYZ<1>ellUV<2>o")));
    });

    test("supports three concurrent typers", () {
      _rebaseAllOrders(doc(p("h<1>ell<2>o th<3>ere")), [
        (transform) => _type(transform, 2, "X"),
        (transform) => _type(transform, 5, "Y"),
        (transform) => _type(transform, 9, "Z"),
      ], doc(p("hX<1>ellY<2>o thZ<3>ere")));
    });

    test("handles wrapping of changed blocks", () {
      _rebaseAllOrders(doc(p("<1>hell<2>o<3>")), [
        (transform) => _type(transform, 5, "X"),
        (transform) => _wrap(transform, 1, "blockquote"),
      ], doc(blockquote(p("<1>hellX<2>o<3>"))));
    });

    test("handles insertions in deleted content", () {
      _rebaseAllOrders(doc(p("hello<1> wo<2>rld<3>!")), [
        (transform) => transform.delete(6, 12),
        (transform) => _type(transform, 9, "X"),
      ], doc(p("hello<3>!")));
    });

    test("allows deleting the same content twice", () {
      _rebaseInOrder(doc(p("hello<1> wo<2>rld<3>!")), [
        (transform) => transform.delete(6, 12),
        (transform) => transform.delete(6, 12),
      ], doc(p("hello<3>!")));
    });

    test("isn't confused by joining a block that's being edited", () {
      _rebaseAllOrders(doc(ul(li(p("one")), "<1>", li(p("tw<2>o")))), [
        (transform) => _type(transform, 12, "A"),
        (transform) => transform.join(8),
      ], doc(ul(li(p("one"), p("twA<2>o")))));
    });

    test("supports typing concurrently with marking", () {
      _rebaseInOrder(doc(p("hello <1>wo<2>rld<3>")), [
        (transform) => transform.addMark(7, 12, schema.mark("em")),
        (transform) => _type(transform, 9, "_"),
      ], doc(p("hello <1>", em("wo"), "_<2>", em("rld<3>"))));
    });

    test("doesn't unmark marks added concurrently", () {
      _rebaseInOrder(doc(p(em("<1>hello"), " world<2>")), [
        (transform) => transform.addMark(1, 12, schema.mark("em")),
        (transform) => transform.removeMark(1, 12, schema.mark("em")),
      ], doc(p("<1>hello", em(" world<2>"))));
    });

    test("doesn't mark concurrently unmarked text", () {
      _rebaseInOrder(doc(p("<1>hello ", em("world<2>"))), [
        (transform) => transform.removeMark(1, 12, schema.mark("em")),
        (transform) => transform.addMark(1, 12, schema.mark("em")),
      ], doc(p(em("<1>hello "), "world<2>")));
    });

    test("deletes inserts in replaced context", () {
      _rebaseInOrder(
        doc(
          p("b<before>efore"),
          blockquote(ul(li(p("o<1>ne")), li(p("t<2>wo")), li(p("thr<3>ee")))),
          p("a<after>fter"),
        ),
        [
          (transform) {
            return transform.replace(
              transform.doc.tag["1"]!,
              transform.doc.tag["3"]!,
              doc(p("a"), blockquote(p("b")), p("c")).slice(2, 9),
            );
          },
          (transform) => _type(transform, transform.doc.tag["2"]!, "ayay"),
        ],
        doc(
          p("b<before>efore"),
          blockquote(ul(li(p("o"), blockquote(p("b")), p("<3>ee")))),
          p("a<after>fter"),
        ),
      );
    });

    test("maps through inserts", () {
      _rebaseAllOrders(doc(p("X<1>X<2>X")), [
        (transform) => _type(transform, 2, "hello"),
        (transform) => _type(transform, 3, "goodbye").delete(4, 7),
      ], doc(p("Xhello<1>Xgbye<2>X")));
    });

    test("handles concurrent removal of blocks", () {
      _rebaseInOrder(doc(p("a"), "<1>", p("b"), "<2>", p("c")), [
        (transform) =>
            transform.delete(transform.doc.tag["1"]!, transform.doc.tag["2"]!),
        (transform) =>
            transform.delete(transform.doc.tag["1"]!, transform.doc.tag["2"]!),
      ], doc(p("a"), "<2>", p("c")));
    });

    test("discards edits in removed blocks", () {
      _rebaseAllOrders(doc(p("a"), "<1>", p("b<2>"), "<3>", p("c")), [
        (transform) =>
            transform.delete(transform.doc.tag["1"]!, transform.doc.tag["3"]!),
        (transform) => _type(transform, transform.doc.tag["2"]!, "ay"),
      ], doc(p("a"), "<3>", p("c")));
    });

    test("preserves double block inserts", () {
      _rebaseInOrder(doc(p("a"), "<1>", p("b")), [
        (transform) => transform.replaceWith(3, 3, schema.node("paragraph")),
        (transform) => transform.replaceWith(3, 3, schema.node("paragraph")),
      ], doc(p("a"), p(), p(), "<1>", p("b")));
    });
  });
}

typedef _TransformAction = Transform Function(Transform transform);
typedef _RebaseableStep = ({Step inverted, Transform origin, Step step});

void _rebaseInOrder(
  Node document,
  List<_TransformAction> clients,
  Node expected,
) {
  _runRebase(
    clients.map((client) => client(Transform(document))).toList(),
    expected,
  );
}

void _rebaseAllOrders(
  Node document,
  List<_TransformAction> clients,
  Node expected,
) {
  final transforms = clients
      .map((client) => client(Transform(document)))
      .toList();
  for (final permutation in _permute(transforms)) {
    _runRebase(permutation, expected);
  }
}

void _runRebase(List<Transform> transforms, Node expected) {
  final startDocument = transforms.first.before;
  final fullTransform = Transform(startDocument);

  for (final transform in transforms) {
    final rebased = Transform(transform.doc);
    final firstRebasedStep =
        transform.steps.length + fullTransform.steps.length;
    rebaseSteps(_rebaseableSteps(transform), fullTransform.steps, rebased);
    for (
      var stepIndex = firstRebasedStep;
      stepIndex < rebased.steps.length;
      stepIndex++
    ) {
      fullTransform.step(rebased.steps[stepIndex]);
    }
  }

  expect(fullTransform.doc.eq(expected), isTrue);
  _expectTagsMapped(startDocument, fullTransform, expected);
}

List<_RebaseableStep> _rebaseableSteps(Transform transform) {
  return [
    for (var stepIndex = 0; stepIndex < transform.steps.length; stepIndex++)
      (
        step: transform.steps[stepIndex],
        inverted: transform.steps[stepIndex].invert(transform.docs[stepIndex]),
        origin: transform,
      ),
  ];
}

void _expectTagsMapped(
  Node startDocument,
  Transform fullTransform,
  Node expected,
) {
  for (final entry in startDocument.tag.entries) {
    final mapped = fullTransform.mapping.mapResult(entry.value);
    final expectedPosition = expected.tag[entry.key];
    if (mapped.deleted) {
      if (expectedPosition != null) {
        fail("Tag ${entry.key} was unexpectedly deleted");
      }
    } else {
      if (expectedPosition == null) {
        fail("Tag ${entry.key} is not actually deleted");
      }
      expect(mapped.pos, expectedPosition);
    }
  }
}

List<List<T>> _permute<T>(List<T> values) {
  if (values.length < 2) {
    return [values];
  }

  final result = <List<T>>[];
  for (var index = 0; index < values.length; index++) {
    final rest = [...values.sublist(0, index), ...values.sublist(index + 1)];
    for (final permutation in _permute(rest)) {
      result.add([values[index], ...permutation]);
    }
  }
  return result;
}

Transform _type(Transform transform, int position, String text) {
  return transform.replaceWith(position, position, schema.text(text));
}

Transform _wrap(Transform transform, int position, String typeName) {
  final resolvedPosition = transform.doc.resolve(position);
  return transform.wrap(resolvedPosition.blockRange()!, [
    (type: schema.nodes[typeName]!, attrs: null),
  ]);
}
