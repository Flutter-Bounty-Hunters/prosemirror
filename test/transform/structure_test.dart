import 'package:prosemirror/prosemirror.dart';
import 'package:test/test.dart';

import '../model/support/builders.dart' as builders;

void main() {
  group("canSplit >", () {
    test("can't at start", () {
      _canSplitNo(0);
    });

    test("can't in head", () {
      _canSplitNo(3);
    });

    test("can by making head a para", () {
      _canSplitYes(3, 1, "para");
    });

    test("can't on top level", () {
      _canSplitNo(6);
    });

    test("can in regular para", () {
      _canSplitYes(8);
    });

    test("can't at start of section", () {
      _canSplitNo(14);
    });

    test("can't in section head", () {
      _canSplitNo(17);
    });

    test("can if also splitting the section", () {
      _canSplitYes(17, 2);
    });

    test("can if making the remaining head a para", () {
      _canSplitYes(18, 1, "para");
    });

    test("can't after the section head", () {
      _canSplitNo(46);
    });

    test("can in the first section para", () {
      _canSplitYes(48);
    });

    test("can't in the figure caption", () {
      _canSplitNo(60);
    });

    test("can't if it also splits the figure", () {
      _canSplitNo(62, 2);
    });

    test("can't after the figure caption", () {
      _canSplitNo(72);
    });

    test("can in the first para in a quote", () {
      _canSplitYes(76);
    });

    test("can if it also splits the quote", () {
      _canSplitYes(77, 2);
    });

    test("can't at the end of the document", () {
      _canSplitNo(97);
    });

    test("doesn't return true when the split-off content doesn't fit in the given node type", () {
      final s = Schema(
        SchemaSpec(
          nodes: _structureSchema.spec.nodes
              .addBefore("heading", "title", NodeSpec(content: "text*"))
              .addToEnd("chapter", NodeSpec(content: "title scene+"))
              .addToEnd("scene", NodeSpec(content: "para+"))
              .update("doc", NodeSpec(content: "chapter+")),
        ),
      );
      expect(
        canSplit(
          s.node(
            "doc",
            null,
            s.node("chapter", null, [
              s.node("title", null, s.text("title")),
              s.node("scene", null, s.node("para", null, s.text("scene"))),
            ]),
          ),
          4,
          1,
          [(type: s.nodes["scene"]!, attrs: null)],
        ),
        isFalse,
      );
    });
  });

  group("liftTarget >", () {
    test("can't at the start of the doc", () {
      _liftTargetNo(0);
    });

    test("can't in the heading", () {
      _liftTargetNo(3);
    });

    test("can't in a subsection para", () {
      _liftTargetNo(52);
    });

    test("can't in a figure caption", () {
      _liftTargetNo(70);
    });

    test("can from a quote", () {
      _liftTargetYes(76);
    });

    test("can't in a section head", () {
      _liftTargetNo(86);
    });

    test("notices unliftable content after or before", () {
      final s = Schema(
        SchemaSpec(
          nodes: <String, NodeSpec>{
            "doc": NodeSpec(content: "section+"),
            "section": NodeSpec(content: "heading? p+"),
            "heading": NodeSpec(content: "p+"),
            "p": NodeSpec(content: "text*"),
            "text": NodeSpec(inline: true),
          },
        ),
      );
      final p = s.node("p", null, [s.text("A")]);
      final d = s.node("doc", null, [
        s.node("section", null, [
          s.node("heading", null, [p, p, p]),
          p,
        ]),
      ]);
      expect(liftTarget(d.resolve(3).blockRange()!), isNull);
      expect(liftTarget(d.resolve(6).blockRange()!), isNull);
      expect(liftTarget(d.resolve(3).blockRange(d.resolve(6))!), isNull);
      expect(liftTarget(d.resolve(9).blockRange()!), 1);
    });
  });

  group("findWrapping >", () {
    test("can wrap the whole doc in a section", () {
      _findWrappingYes(0, 92, "sect");
    });

    test("can't wrap a head before a para in a section", () {
      _findWrappingNo(4, 4, "sect");
    });

    test("can wrap a top paragraph in a quote", () {
      _findWrappingYes(8, 8, "quote");
    });

    test("can't wrap a section head in a quote", () {
      _findWrappingNo(18, 18, "quote");
    });

    test("can wrap a figure in a quote", () {
      _findWrappingYes(55, 74, "quote");
    });

    test("can't wrap a head in a figure", () {
      _findWrappingNo(90, 90, "figure");
    });
  });

  group("Transform > replace >", () {
    test("automatically adds a heading to a section", () {
      _repl(
        _n("doc", [
          _n("sect", [
            _n("head", [_t("foo")]),
            _n("para", [_t("bar")]),
          ]),
        ]),
        6,
        6,
        _n("doc", [_n("sect"), _n("sect")]),
        1,
        1,
        _n("doc", [
          _n("sect", [
            _n("head", [_t("foo")]),
          ]),
          _n("sect", [
            _n("head"),
            _n("para", [_t("bar")]),
          ]),
        ]),
      );
    });

    test("suppresses impossible inputs", () {
      _repl(
        _n("doc", [
          _n("para", [_t("a")]),
          _n("para", [_t("b")]),
        ]),
        3,
        3,
        _n("doc", [
          _n("closing", [_t(".")]),
        ]),
        0,
        0,
        _n("doc", [
          _n("para", [_t("a")]),
          _n("para", [_t("b")]),
        ]),
      );
    });

    test("adds necessary nodes to the left", () {
      _repl(
        _n("doc", [
          _n("sect", [
            _n("head", [_t("foo")]),
            _n("para", [_t("bar")]),
          ]),
        ]),
        1,
        3,
        _n("doc", [
          _n("sect"),
          _n("sect", [
            _n("head", [_t("hi")]),
          ]),
        ]),
        1,
        2,
        _n("doc", [
          _n("sect", [_n("head")]),
          _n("sect", [
            _n("head", [_t("hioo")]),
            _n("para", [_t("bar")]),
          ]),
        ]),
      );
    });

    test("adds a caption to a figure", () {
      _repl(
        _n("doc"),
        0,
        0,
        _n("doc", [
          _n("figure", [_n("figureimage")]),
        ]),
        1,
        0,
        _n("doc", [
          _n("figure", [_n("caption"), _n("figureimage")]),
        ]),
      );
    });

    test("adds an image to a figure", () {
      _repl(
        _n("doc"),
        0,
        0,
        _n("doc", [
          _n("figure", [_n("caption")]),
        ]),
        0,
        1,
        _n("doc", [
          _n("figure", [_n("caption"), _n("figureimage")]),
        ]),
      );
    });

    test("can join figures", () {
      _repl(
        _n("doc", [
          _n("figure", [_n("caption"), _n("figureimage")]),
          _n("figure", [_n("caption"), _n("figureimage")]),
        ]),
        3,
        8,
        null,
        0,
        0,
        _n("doc", [
          _n("figure", [_n("caption"), _n("figureimage")]),
        ]),
      );
    });

    test("adds necessary nodes to a parent node", () {
      _repl(
        _n("doc", [
          _n("sect", [
            _n("head"),
            _n("figure", [_n("caption"), _n("figureimage")]),
          ]),
        ]),
        7,
        9,
        _n("doc", [
          _n("para", [_t("hi")]),
        ]),
        0,
        0,
        _n("doc", [
          _n("sect", [
            _n("head"),
            _n("figure", [_n("caption"), _n("figureimage")]),
            _n("para", [_t("hi")]),
          ]),
        ]),
      );
    });
  });
}

void _canSplitYes(int pos, [int? depth, String? after]) {
  expect(_canSplitAt(pos, depth, after), isTrue);
}

void _canSplitNo(int pos, [int? depth, String? after]) {
  expect(_canSplitAt(pos, depth, after), isFalse);
}

bool _canSplitAt(int pos, int? depth, String? after) {
  final typesAfter = after == null
      ? null
      : [(type: _structureSchema.nodes[after]!, attrs: null)];
  return canSplit(_structureDoc, pos, depth ?? 1, typesAfter);
}

void _liftTargetYes(int pos) {
  final range = _range(pos);
  final target = range == null ? null : liftTarget(range);
  expect(target != null && target != 0, isTrue);
}

void _liftTargetNo(int pos) {
  final range = _range(pos);
  final target = range == null ? null : liftTarget(range);
  expect(target == null || target == 0, isTrue);
}

void _findWrappingYes(int pos, int end, String type) {
  final range = _range(pos, end);
  expect(
    range != null && findWrapping(range, _structureSchema.nodes[type]!) != null,
    isTrue,
  );
}

void _findWrappingNo(int pos, int end, String type) {
  final range = _range(pos, end);
  expect(
    range == null || findWrapping(range, _structureSchema.nodes[type]!) == null,
    isTrue,
  );
}

void _repl(
  Node document,
  int from,
  int to,
  Node? content,
  int openStart,
  int openEnd,
  Node result,
) {
  final slice = content != null
      ? Slice(content.content, openStart, openEnd)
      : Slice.empty;
  final tr = Transform(document).replace(from, to, slice);
  expect(builders.eq(tr.doc, result), isTrue);
}

NodeRange? _range(int pos, [int? end]) {
  return _structureDoc
      .resolve(pos)
      .blockRange(end == null ? null : _structureDoc.resolve(end));
}

Node _n(String name, [List<Node> content = const []]) {
  return _structureSchema.nodes[name]!.create(null, content);
}

Node _t(String string, [bool em = false]) {
  return _structureSchema.text(
    string,
    em ? [_structureSchema.mark("em")] : null,
  );
}

final Node _structureDoc = _n("doc", [
  _n("head", [_t("Head")]),
  _n("para", [_t("Intro")]),
  _n("sect", [
    _n("head", [_t("Section head")]),
    _n("sect", [
      _n("head", [_t("Subsection head")]),
      _n("para", [_t("Subtext")]),
      _n("figure", [
        _n("caption", [_t("Figure caption")]),
        _n("figureimage"),
      ]),
      _n("quote", [
        _n("para", [_t("!")]),
      ]),
    ]),
  ]),
  _n("sect", [
    _n("head", [_t("S2")]),
    _n("para", [_t("Yes")]),
  ]),
  _n("closing", [_t("fin")]),
]);

final Schema _structureSchema = Schema(
  SchemaSpec(
    nodes: <String, NodeSpec>{
      "doc": NodeSpec(content: "head? block* sect* closing?"),
      "para": NodeSpec(content: "text*", group: "block"),
      "head": NodeSpec(content: "text*", marks: ""),
      "figure": NodeSpec(content: "caption figureimage", group: "block"),
      "quote": NodeSpec(content: "block+", group: "block"),
      "figureimage": NodeSpec(),
      "caption": NodeSpec(content: "text*", marks: ""),
      "sect": NodeSpec(content: "head block* sect*"),
      "closing": NodeSpec(content: "text*"),
      "text": builders.schema.spec.nodes.get("text")!,
      "fixed": NodeSpec(content: "head para closing", group: "block"),
    },
    marks: <String, MarkSpec>{"em": MarkSpec()},
  ),
);
