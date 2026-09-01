import 'package:prosemirror/prosemirror.dart';
import 'package:test/test.dart';

import 'package:prosemirror/test_builder.dart';

void main() {
  group("Step > merge >", () {
    test("merges typing changes", () {
      _expectMerges(2, 2, "a", 3, 3, "b");
    });

    test("merges inverse typing", () {
      _expectMerges(2, 2, "a", 2, 2, "b");
    });

    test("doesn't merge separated typing", () {
      _expectNoMerge(2, 2, "a", 4, 4, "b");
    });

    test("doesn't merge inverted separated typing", () {
      _expectNoMerge(3, 3, "a", 2, 2, "b");
    });

    test("merges adjacent backspaces", () {
      _expectMerges(3, 4, null, 2, 3, null);
    });

    test("merges adjacent deletes", () {
      _expectMerges(2, 3, null, 2, 3, null);
    });

    test("doesn't merge separate backspaces", () {
      _expectNoMerge(1, 2, null, 2, 3, null);
    });

    test("merges backspace and type", () {
      _expectMerges(2, 3, null, 2, 2, "x");
    });

    test("merges longer adjacent inserts", () {
      _expectMerges(2, 2, "quux", 6, 6, "baz");
    });

    test("merges inverted longer inserts", () {
      _expectMerges(2, 2, "quux", 2, 2, "baz");
    });

    test("merges longer deletes", () {
      _expectMerges(2, 5, null, 2, 4, null);
    });

    test("merges inverted longer deletes", () {
      _expectMerges(4, 6, null, 2, 4, null);
    });

    test("merges overwrites", () {
      _expectMerges(3, 4, "x", 4, 5, "y");
    });

    test("merges adding adjacent styles", () {
      _expectMerges(1, 2, "+em", 2, 4, "+em");
    });

    test("merges adding overlapping styles", () {
      _expectMerges(1, 3, "+em", 2, 4, "+em");
    });

    test("doesn't merge separate styles", () {
      _expectNoMerge(1, 2, "+em", 3, 4, "+em");
    });

    test("merges removing adjacent styles", () {
      _expectMerges(1, 2, "-em", 2, 4, "-em");
    });

    test("merges removing overlapping styles", () {
      _expectMerges(1, 3, "-em", 2, 4, "-em");
    });

    test("doesn't merge removing separate styles", () {
      _expectNoMerge(1, 2, "-em", 3, 4, "-em");
    });
  });
}

void _expectMerges(int from1, int to1, String? value1, int from2, int to2, String? value2) {
  final step1 = _mkStep(from1, to1, value1);
  final step2 = _mkStep(from2, to2, value2);
  final merged = step1.merge(step2);
  expect(merged, isNotNull);
  expect(eq(merged!.apply(_testDoc).doc, step2.apply(step1.apply(_testDoc).doc!).doc), isTrue);
}

void _expectNoMerge(int from1, int to1, String? value1, int from2, int to2, String? value2) {
  final step1 = _mkStep(from1, to1, value1);
  final step2 = _mkStep(from2, to2, value2);
  expect(step1.merge(step2), isNull);
}

Step _mkStep(int from, int to, String? value) {
  if (value == "+em") {
    return AddMarkStep(from, to, schema.marks["em"]!.create());
  } else if (value == "-em") {
    return RemoveMarkStep(from, to, schema.marks["em"]!.create());
  } else {
    return ReplaceStep(from, to, value == null ? Slice.empty : Slice(Fragment.from(schema.text(value)), 0, 0));
  }
}

final Node _testDoc = document(p("foobar"));
