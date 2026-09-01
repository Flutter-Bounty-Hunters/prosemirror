import 'package:test/test.dart';
import 'package:prosemirror/prosemirror.dart';
import 'package:prosemirror/test_builder.dart';

// This schema has an "a" mark which doesn't exclude itself
final _nodes = {
  "doc": NodeSpec(content: "block+"),
  "p": NodeSpec(content: "inline*", group: "block"),
  "text": NodeSpec(group: "inline"),
};

final _marks = {
  "a": MarkSpec(
    attrs: {"href": AttributeSpec(validate: "string")},
    excludes: "",
  ),
};

final _schema = Schema(SchemaSpec(nodes: _nodes, marks: _marks));

final _b = builders(_schema);
final NodeBuilder document = _b["doc"] as NodeBuilder;
final NodeBuilder p = _b["p"] as NodeBuilder;
final MarkBuilder a = _b["a"] as MarkBuilder;

void main() {
  group("Multiple marks >", () {
    test("deduplicates identical marks", () {
      final actual = document(p(a({"href": "/foo"}, a({"href": "/foo"}, "click <p>here"))));
      final expected = document(p(a({"href": "/foo"}, "click here")));

      expect(eq(actual, expected), isTrue);
      expect(actual.nodeAt(actual.tag["p"]!)!.marks.length, equals(1));
    });

    test("marks of same type but different attributes are distinct", () {
      final actual = document(p(a({"href": "/foo"}, a({"href": "/bar"}, "click <p>here"))));

      expect(actual.nodeAt(actual.tag["p"]!)!.marks.length, equals(2));
    });
  });
}
