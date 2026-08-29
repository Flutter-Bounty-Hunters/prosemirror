import 'package:prosemirror/prosemirror.dart';
import 'package:test/test.dart';

import 'support/builders.dart';

void main() {
  group("ContentMatch > matchType >", () {
    test("accepts empty content for the empty expr", () => _valid("", ""));
    test(
      "doesn't accept content in the empty expr",
      () => _invalid("", "image"),
    );

    test("matches nothing to an asterisk", () => _valid("image*", ""));
    test("matches one element to an asterisk", () => _valid("image*", "image"));
    test(
      "matches multiple elements to an asterisk",
      () => _valid("image*", "image image image image"),
    );
    test(
      "only matches appropriate elements to an asterisk",
      () => _invalid("image*", "image text"),
    );

    test(
      "matches group members to a group",
      () => _valid("inline*", "image text"),
    );
    test(
      "doesn't match non-members to a group",
      () => _invalid("inline*", "paragraph"),
    );
    test(
      "matches an element to a choice expression",
      () => _valid("(paragraph | heading)", "paragraph"),
    );
    test(
      "doesn't match unmentioned elements to a choice expr",
      () => _invalid("(paragraph | heading)", "image"),
    );

    test(
      "matches a simple sequence",
      () => _valid(
        "paragraph horizontal_rule paragraph",
        "paragraph horizontal_rule paragraph",
      ),
    );
    test(
      "fails when a sequence is too long",
      () => _invalid(
        "paragraph horizontal_rule",
        "paragraph horizontal_rule paragraph",
      ),
    );
    test(
      "fails when a sequence is too short",
      () => _invalid(
        "paragraph horizontal_rule paragraph",
        "paragraph horizontal_rule",
      ),
    );
    test(
      "fails when a sequence starts incorrectly",
      () => _invalid(
        "paragraph horizontal_rule",
        "horizontal_rule paragraph horizontal_rule",
      ),
    );

    test(
      "accepts a sequence asterisk matching zero elements",
      () => _valid("heading paragraph*", "heading"),
    );
    test(
      "accepts a sequence asterisk matching multiple elements",
      () => _valid("heading paragraph*", "heading paragraph paragraph"),
    );
    test(
      "accepts a sequence plus matching one element",
      () => _valid("heading paragraph+", "heading paragraph"),
    );
    test(
      "accepts a sequence plus matching multiple elements",
      () => _valid("heading paragraph+", "heading paragraph paragraph"),
    );
    test(
      "fails when a sequence plus has no elements",
      () => _invalid("heading paragraph+", "heading"),
    );
    test(
      "fails when a sequence plus misses its start",
      () => _invalid("heading paragraph+", "paragraph paragraph"),
    );

    test(
      "accepts an optional element being present",
      () => _valid("image?", "image"),
    );
    test(
      "accepts an optional element being missing",
      () => _valid("image?", ""),
    );
    test(
      "fails when an optional element is present twice",
      () => _invalid("image?", "image image"),
    );

    test(
      "accepts a nested repeat",
      () => _valid(
        "(heading paragraph+)+",
        "heading paragraph heading paragraph paragraph",
      ),
    );
    test(
      "fails on extra input after a nested repeat",
      () => _invalid(
        "(heading paragraph+)+",
        "heading paragraph heading paragraph paragraph horizontal_rule",
      ),
    );

    test(
      "accepts a matching count",
      () => _valid("hard_break{2}", "hard_break hard_break"),
    );
    test(
      "rejects a count that comes up short",
      () => _invalid("hard_break{2}", "hard_break"),
    );
    test(
      "rejects a count that has too many elements",
      () => _invalid("hard_break{2}", "hard_break hard_break hard_break"),
    );
    test(
      "accepts a count on the lower bound",
      () => _valid("hard_break{2, 4}", "hard_break hard_break"),
    );
    test(
      "accepts a count on the upper bound",
      () => _valid(
        "hard_break{2, 4}",
        "hard_break hard_break hard_break hard_break",
      ),
    );
    test(
      "accepts a count between the bounds",
      () => _valid("hard_break{2, 4}", "hard_break hard_break hard_break"),
    );
    test(
      "rejects a sequence with too few elements",
      () => _invalid("hard_break{2, 4}", "hard_break"),
    );
    test(
      "rejects a sequence with too many elements",
      () => _invalid(
        "hard_break{2, 4}",
        "hard_break hard_break hard_break hard_break hard_break",
      ),
    );
    test(
      "rejects a sequence with a bad element after it",
      () => _invalid("hard_break{2, 4} text*", "hard_break hard_break image"),
    );
    test(
      "accepts a sequence with a matching element after it",
      () => _valid("hard_break{2, 4} image?", "hard_break hard_break image"),
    );
    test(
      "accepts an open range",
      () => _valid("hard_break{2,}", "hard_break hard_break"),
    );
    test(
      "accepts an open range matching many",
      () => _valid(
        "hard_break{2,}",
        "hard_break hard_break hard_break hard_break",
      ),
    );
    test(
      "rejects an open range with too few elements",
      () => _invalid("hard_break{2,}", "hard_break"),
    );
  });

  group("ContentMatch > fillBefore >", () {
    test("returns the empty fragment when things match", () {
      _fill(
        "paragraph horizontal_rule paragraph",
        doc(p(), hr()),
        doc(p()),
        doc(),
      );
    });

    test("adds a node when necessary", () {
      _fill(
        "paragraph horizontal_rule paragraph",
        doc(p()),
        doc(p()),
        doc(hr()),
      );
    });

    test(
      "accepts an asterisk across the bound",
      () => _fill("hard_break*", p(br()), p(br()), p()),
    );

    test(
      "accepts an asterisk only on the left",
      () => _fill("hard_break*", p(br()), p(), p()),
    );

    test(
      "accepts an asterisk only on the right",
      () => _fill("hard_break*", p(), p(br()), p()),
    );

    test(
      "accepts an asterisk with no elements",
      () => _fill("hard_break*", p(), p(), p()),
    );

    test(
      "accepts a plus across the bound",
      () => _fill("hard_break+", p(br()), p(br()), p()),
    );

    test(
      "adds an element for a content-less plus",
      () => _fill("hard_break+", p(), p(), p(br())),
    );

    test(
      "fails for a mismatched plus",
      () => _fill("hard_break+", p(), p(img()), null),
    );

    test(
      "accepts asterisk with content on both sides",
      () => _fill("heading* paragraph*", doc(h1()), doc(p()), doc()),
    );

    test(
      "accepts asterisk with no content after",
      () => _fill("heading* paragraph*", doc(h1()), doc(), doc()),
    );

    test(
      "accepts plus with content on both sides",
      () => _fill("heading+ paragraph+", doc(h1()), doc(p()), doc()),
    );

    test(
      "accepts plus with no content after",
      () => _fill("heading+ paragraph+", doc(h1()), doc(), doc(p())),
    );

    test(
      "adds elements to match a count",
      () => _fill("hard_break{3}", p(br()), p(br()), p(br())),
    );

    test(
      "fails when there are too many elements",
      () => _fill("hard_break{3}", p(br(), br()), p(br(), br()), null),
    );

    test(
      "adds elements for two counted groups",
      () => _fill(
        "code_block{2} paragraph{2}",
        doc(pre()),
        doc(p()),
        doc(pre(), p()),
      ),
    );

    test(
      "doesn't include optional elements",
      () => _fill(
        "heading paragraph? horizontal_rule",
        doc(h1()),
        doc(),
        doc(hr()),
      ),
    );

    test("completes a sequence", () {
      _fill3(
        "paragraph horizontal_rule paragraph horizontal_rule paragraph",
        doc(p()),
        doc(p()),
        doc(p()),
        doc(hr()),
        doc(hr()),
      );
    });

    test("accepts plus across two bounds", () {
      _fill3(
        "code_block+ paragraph+",
        doc(pre()),
        doc(pre()),
        doc(p()),
        doc(),
        doc(),
      );
    });

    test("fills a plus from empty input", () {
      _fill3(
        "code_block+ paragraph+",
        doc(),
        doc(),
        doc(),
        doc(),
        doc(pre(), p()),
      );
    });

    test("completes a count", () {
      _fill3(
        "code_block{3} paragraph{3}",
        doc(pre()),
        doc(p()),
        doc(),
        doc(pre(), pre()),
        doc(p(), p()),
      );
    });

    test("fails on non-matching elements", () {
      _fill3("paragraph*", doc(p()), doc(pre()), doc(p()), null);
    });

    test("completes a plus across two bounds", () {
      _fill3("paragraph{4}", doc(p()), doc(p()), doc(p()), doc(), doc(p()));
    });

    test("refuses to complete an overflown count across two bounds", () {
      _fill3("paragraph{2}", doc(p()), doc(p()), doc(p()), null);
    });
  });
}

void _valid(String expression, String types) =>
    expect(_match(expression, types), isTrue);

void _invalid(String expression, String types) =>
    expect(_match(expression, types), isFalse);

void _fill(String expression, Node before, Node after, Node? result) {
  final filled = _get(expression)
      .matchFragment(before.content)!
      .fillBefore(after.content, true);
  if (result != null) {
    expect(filled!.eq(result.content), isTrue);
  } else {
    expect(filled, isNull);
  }
}

void _fill3(
  String expression,
  Node before,
  Node mid,
  Node after,
  Node? left, [
  Node? right,
]) {
  final content = _get(expression);
  final a = content.matchFragment(before.content)!.fillBefore(mid.content);
  final b = a != null
      ? content
            .matchFragment(before.content.append(a).append(mid.content))!
            .fillBefore(after.content, true)
      : null;
  if (left != null) {
    expect(a!.eq(left.content), isTrue);
    expect(b!.eq(right!.content), isTrue);
  } else {
    expect(b, isNull);
  }
}

bool _match(String expression, String types) {
  ContentMatch? current = _get(expression);
  final typeList = types.isNotEmpty
      ? types.split(" ").map((name) => schema.nodes[name]!).toList()
      : <NodeType>[];
  for (var index = 0; current != null && index < typeList.length; index++) {
    current = current.matchType(typeList[index]);
  }
  return current != null && current.validEnd;
}

ContentMatch _get(String expression) =>
    ContentMatch.parse(expression, schema.nodes);
