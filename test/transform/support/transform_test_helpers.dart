/// Shared assertions for the transform test suite.
///
/// This is a Dart port of prosemirror-transform's `test/trans.ts`. The Node-only
/// `EMIT_JSON` dumping harness from the original is intentionally dropped; only
/// the [testTransform] entry point and its private helpers remain.
library;

import 'package:prosemirror/prosemirror.dart';
import 'package:test/test.dart';

import 'package:prosemirror/test_builder.dart';

/// Verifies that applying [tr] yields [expect], that the transform is
/// invertible, that every step round-trips through JSON, and that each position
/// tag on [expect] maps correctly through [tr]'s mapping.
void testTransform(Transform tr, Node expect) {
  _expectNodeEq(tr.doc, expect);
  _expectNodeEq(_invert(tr).doc, tr.before);

  _testStepJson(tr);

  for (final entry in expect.tag.entries) {
    _testMapping(tr.mapping, tr.before.tag[entry.key]!, entry.value);
  }
}

Transform _invert(Transform transform) {
  final out = Transform(transform.doc);
  for (var index = transform.steps.length - 1; index >= 0; index--) {
    out.step(transform.steps[index].invert(transform.docs[index]));
  }
  return out;
}

void _testMapping(Mapping mapping, int pos, int newPos) {
  final mapped = mapping.map(pos, 1);
  expect(mapped, newPos);

  final remap = Mapping(mapping.maps.map((map) => map.invert()).toList());
  for (var index = mapping.maps.length - 1, mapFrom = mapping.maps.length; index >= 0; index--) {
    remap.appendMap(mapping.maps[index], --mapFrom);
  }
  expect(remap.map(pos, 1), pos);
}

void _testStepJson(Transform tr) {
  final newTransform = Transform(tr.before);
  for (final step in tr.steps) {
    newTransform.step(Step.fromJSON(tr.doc.type.schema, step.toJSON()));
  }
  expect(eq(tr.doc, newTransform.doc), isTrue);
}

void _expectNodeEq(Node actual, Node expected) {
  expect(eq(actual, expected), isTrue);
}
