import 'package:prosemirror/prosemirror.dart';
import 'package:test/test.dart';

import 'package:prosemirror/test_builder.dart';

void main() {
  group("Mark > sameSet >", () {
    test("returns true for two empty sets", () {
      expect(Mark.sameSet(<Mark>[], <Mark>[]), isTrue);
    });

    test("returns true for simple identical sets", () {
      expect(Mark.sameSet([_em, _strong], [_em, _strong]), isTrue);
    });

    test("returns false for different sets", () {
      expect(Mark.sameSet([_em, _strong], [_em, _code]), isFalse);
    });

    test("returns false when set size differs", () {
      expect(Mark.sameSet([_em, _strong], [_em, _strong, _code]), isFalse);
    });

    test("recognizes identical links in set", () {
      expect(Mark.sameSet([_link("http://foo"), _code], [_link("http://foo"), _code]), isTrue);
    });

    test("recognizes different links in set", () {
      expect(Mark.sameSet([_link("http://foo"), _code], [_link("http://bar"), _code]), isFalse);
    });
  });

  group("Mark > eq >", () {
    test("considers identical links to be the same", () {
      expect(_link("http://foo").eq(_link("http://foo")), isTrue);
    });

    test("considers different links to differ", () {
      expect(_link("http://foo").eq(_link("http://bar")), isFalse);
    });

    test("considers links with different titles to differ", () {
      expect(_link("http://foo", "A").eq(_link("http://foo", "B")), isFalse);
    });
  });

  group("Mark > addToSet >", () {
    test("can add to the empty set", () {
      expect(Mark.sameSet(_em.addToSet(<Mark>[]), [_em]), isTrue);
    });

    test("is a no-op when the added thing is in set", () {
      expect(Mark.sameSet(_em.addToSet([_em]), [_em]), isTrue);
    });

    test("adds marks with lower rank before others", () {
      expect(Mark.sameSet(_em.addToSet([_strong]), [_em, _strong]), isTrue);
    });

    test("adds marks with higher rank after others", () {
      expect(Mark.sameSet(_strong.addToSet([_em]), [_em, _strong]), isTrue);
    });

    test("replaces different marks with new attributes", () {
      expect(
        Mark.sameSet(_link("http://bar").addToSet([_link("http://foo"), _em]), [_link("http://bar"), _em]),
        isTrue,
      );
    });

    test("does nothing when adding an existing link", () {
      expect(
        Mark.sameSet(_link("http://foo").addToSet([_em, _link("http://foo")]), [_em, _link("http://foo")]),
        isTrue,
      );
    });

    test("puts code marks at the end", () {
      expect(
        Mark.sameSet(_code.addToSet([_em, _strong, _link("http://foo")]), [_em, _strong, _link("http://foo"), _code]),
        isTrue,
      );
    });

    test("puts marks with middle rank in the middle", () {
      expect(Mark.sameSet(_strong.addToSet([_em, _code]), [_em, _strong, _code]), isTrue);
    });

    test("allows nonexclusive instances of marks with the same type", () {
      expect(Mark.sameSet(_remark2.addToSet([_remark1]), [_remark1, _remark2]), isTrue);
    });

    test("doesn't duplicate identical instances of nonexclusive marks", () {
      expect(Mark.sameSet(_remark1.addToSet([_remark1]), [_remark1]), isTrue);
    });

    test("clears all others when adding a globally-excluding mark", () {
      expect(Mark.sameSet(_user1.addToSet([_remark1, _customEm]), [_user1]), isTrue);
    });

    test("does not allow adding another mark to a globally-excluding mark", () {
      expect(Mark.sameSet(_customEm.addToSet([_user1]), [_user1]), isTrue);
    });

    test("does overwrite a globally-excluding mark when adding another instance", () {
      expect(Mark.sameSet(_user2.addToSet([_user1]), [_user2]), isTrue);
    });

    test("doesn't add anything when another mark excludes the added mark", () {
      expect(Mark.sameSet(_customEm.addToSet([_remark1, _customStrong]), [_remark1, _customStrong]), isTrue);
    });

    test("removes excluded marks when adding a mark", () {
      expect(Mark.sameSet(_customStrong.addToSet([_remark1, _customEm]), [_remark1, _customStrong]), isTrue);
    });
  });

  group("Mark > removeFromSet >", () {
    test("is a no-op for the empty set", () {
      expect(Mark.sameSet(_em.removeFromSet(<Mark>[]), <Mark>[]), isTrue);
    });

    test("can remove the last mark from a set", () {
      expect(Mark.sameSet(_em.removeFromSet([_em]), <Mark>[]), isTrue);
    });

    test("is a no-op when the mark isn't in the set", () {
      expect(Mark.sameSet(_strong.removeFromSet([_em]), [_em]), isTrue);
    });

    test("can remove a mark with attributes", () {
      expect(Mark.sameSet(_link("http://foo").removeFromSet([_link("http://foo")]), <Mark>[]), isTrue);
    });

    test("doesn't remove a mark when its attrs differ", () {
      expect(
        Mark.sameSet(_link("http://foo", "title").removeFromSet([_link("http://foo")]), [_link("http://foo")]),
        isTrue,
      );
    });
  });

  group("Mark > resolved position marks >", () {
    test("recognizes a mark exists inside marked text", () {
      _isAt(document(p(em("fo<a>o"))), _em, true);
    });

    test("recognizes a mark doesn't exist in non-marked text", () {
      _isAt(document(p(em("fo<a>o"))), _strong, false);
    });

    test("considers a mark active after the mark", () {
      _isAt(document(p(em("hi"), "<a> there")), _em, true);
    });

    test("considers a mark inactive before the mark", () {
      _isAt(document(p("one <a>", em("two"))), _em, false);
    });

    test("considers a mark active at the start of the textblock", () {
      _isAt(document(p(em("<a>one"))), _em, true);
    });

    test("notices that attributes differ", () {
      _isAt(document(p(a("li<a>nk"))), _link("http://baz"), false);
    });

    test("omits non-inclusive marks at end of mark", () {
      expect(Mark.sameSet(_customDoc.resolve(4).marks(), [_customStrong]), isTrue);
    });

    test("includes non-inclusive marks inside a text node", () {
      expect(Mark.sameSet(_customDoc.resolve(3).marks(), [_remark1, _customStrong]), isTrue);
    });

    test("omits non-inclusive marks at the end of a line", () {
      expect(Mark.sameSet(_customDoc.resolve(20).marks(), <Mark>[]), isTrue);
    });

    test("includes non-inclusive marks between two marked nodes", () {
      expect(Mark.sameSet(_customDoc.resolve(15).marks(), [_remark1]), isTrue);
    });

    test("excludes non-inclusive marks at a point where mark attrs change", () {
      expect(Mark.sameSet(_customDoc.resolve(25).marks(), <Mark>[]), isTrue);
    });
  });
}

void _isAt(Node document, Mark mark, bool result) {
  expect(mark.isInSet(document.resolve(document.tag["a"]!).marks()), result);
}

final Mark _em = schema.mark("em");
final Mark _strong = schema.mark("strong");
final Mark _code = schema.mark("code");

Mark _link(String href, [String? title]) {
  return schema.mark("link", title == null ? {"href": href} : {"href": href, "title": title});
}

final Schema _customSchema = Schema(
  SchemaSpec(
    nodes: {
      "doc": NodeSpec(content: "paragraph+"),
      "paragraph": NodeSpec(content: "text*"),
      "text": NodeSpec(),
    },
    marks: {
      "remark": MarkSpec(attrs: {"id": const AttributeSpec()}, excludes: "", inclusive: false),
      "user": MarkSpec(attrs: {"id": const AttributeSpec()}, excludes: "_"),
      "strong": MarkSpec(excludes: "em-group"),
      "em": MarkSpec(group: "em-group"),
    },
  ),
);

final Map<String, MarkType> _custom = _customSchema.marks;
final Mark _remark1 = _custom["remark"]!.create({"id": 1});
final Mark _remark2 = _custom["remark"]!.create({"id": 2});
final Mark _user1 = _custom["user"]!.create({"id": 1});
final Mark _user2 = _custom["user"]!.create({"id": 2});
final Mark _customEm = _custom["em"]!.create();
final Mark _customStrong = _custom["strong"]!.create();

final Node _customDoc = _customSchema.node("doc", null, [
  _customSchema.node("paragraph", null, [
    // pos 1
    _customSchema.text("one", [_remark1, _customStrong]),
    _customSchema.text("two"),
  ]),
  _customSchema.node("paragraph", null, [
    // pos 9
    _customSchema.text("one"),
    _customSchema.text("two", [_remark1]),
    _customSchema.text("three", [_remark1]),
  ]),
  // pos 22
  _customSchema.node("paragraph", null, [
    _customSchema.text("one", [_remark2]),
    _customSchema.text("two", [_remark1]),
  ]),
]);
