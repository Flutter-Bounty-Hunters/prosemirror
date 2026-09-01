import 'package:prosemirror/prosemirror.dart';
import 'package:test/test.dart';

import 'package:prosemirror/test_builder.dart';

void main() {
  group("ReplaceAroundStep map >", () {
    test("doesn't break wrap steps on insertions", () {
      _test(
        document(p("a")),
        (tr) => tr.wrap(tr.doc.resolve(1).blockRange()!, [(type: schema.nodes["blockquote"]!, attrs: null)]),
        (tr) => tr.insert(0, p("b")),
        document(p("b"), blockquote(p("a"))),
      );
    });

    test("doesn't overwrite content inserted at start of unwrap step", () {
      _test(
        document(blockquote(p("a"))),
        (tr) => tr.lift(tr.doc.resolve(2).blockRange()!, 0),
        (tr) => tr.insert(2, schema.text("x")),
        document(p("xa")),
      );
    });
  });
}

void _test(Node document, void Function(Transform tr) change, void Function(Transform tr) otherChange, Node expected) {
  final trA = Transform(document);
  final trB = Transform(document);
  change(trA);
  otherChange(trB);
  final result = Transform(trB.doc).step(trA.steps[0].map(trB.mapping)!).doc;
  expect(eq(result, expected), isTrue);
}
