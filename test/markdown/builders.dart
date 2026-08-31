library;

import 'package:prosemirror/prosemirror.dart';

bool eq(dynamic first, dynamic second) => first.eq(second) as bool;

final Map<String, Attrs> _builderConfig = {
  "p": {"nodeType": "paragraph"},
  "h1": {"nodeType": "heading", "level": 1},
  "h2": {"nodeType": "heading", "level": 2},
  "hr": {"nodeType": "horizontal_rule"},
  "li": {"nodeType": "list_item"},
  "ol": {"nodeType": "ordered_list"},
  "ol3": {"nodeType": "ordered_list", "order": 3},
  "ul": {"nodeType": "bullet_list"},
  "pre": {"nodeType": "code_block"},
  "a": {"markType": "link", "href": "foo"},
  "br": {"nodeType": "hard_break"},
  "img": {"nodeType": "image", "src": "img.png", "alt": "x"},
};

final Map<String, Object> _builders = _makeBuilders(
  markdownSchema,
  _builderConfig,
);

final NodeBuilder doc = _builders["doc"] as NodeBuilder;
final NodeBuilder p = _builders["p"] as NodeBuilder;
final NodeBuilder h1 = _builders["h1"] as NodeBuilder;
final NodeBuilder h2 = _builders["h2"] as NodeBuilder;
final NodeBuilder hr = _builders["hr"] as NodeBuilder;
final NodeBuilder li = _builders["li"] as NodeBuilder;
final NodeBuilder ol = _builders["ol"] as NodeBuilder;
final NodeBuilder ol3 = _builders["ol3"] as NodeBuilder;
final NodeBuilder ul = _builders["ul"] as NodeBuilder;
final NodeBuilder pre = _builders["pre"] as NodeBuilder;
final NodeBuilder blockquote = _builders["blockquote"] as NodeBuilder;
final NodeBuilder br = _builders["br"] as NodeBuilder;
final NodeBuilder img = _builders["img"] as NodeBuilder;
final MarkBuilder a = _builders["a"] as MarkBuilder;
final MarkBuilder link = _builders["link"] as MarkBuilder;
final MarkBuilder em = _builders["em"] as MarkBuilder;
final MarkBuilder strong = _builders["strong"] as MarkBuilder;
final MarkBuilder code = _builders["code"] as MarkBuilder;

class NodeBuilder {
  NodeBuilder(this.type, this.baseAttributes) {
    if (type.isLeaf) {
      try {
        flat = [type.create(baseAttributes)];
      } catch (_) {
        // Leaf builders with required attrs are only usable when called.
      }
    }
  }

  final NodeType type;
  final Attrs baseAttributes;
  List<Node>? flat;

  Node call([
    Object? child0,
    Object? child1,
    Object? child2,
    Object? child3,
    Object? child4,
    Object? child5,
    Object? child6,
    Object? child7,
    Object? child8,
    Object? child9,
  ]) {
    final arguments = _collectArguments([
      child0,
      child1,
      child2,
      child3,
      child4,
      child5,
      child6,
      child7,
      child8,
      child9,
    ]);
    final attributes = _takeAttributes(baseAttributes, arguments);
    return type.create(attributes, _flatten(type.schema, arguments, _identity));
  }
}

class MarkBuilder {
  MarkBuilder(this.type, this.baseAttributes);

  final MarkType type;
  final Attrs baseAttributes;

  FlatContent call([
    Object? child0,
    Object? child1,
    Object? child2,
    Object? child3,
    Object? child4,
    Object? child5,
    Object? child6,
    Object? child7,
    Object? child8,
    Object? child9,
  ]) {
    final arguments = _collectArguments([
      child0,
      child1,
      child2,
      child3,
      child4,
      child5,
      child6,
      child7,
      child8,
      child9,
    ]);
    final mark = type.create(_takeAttributes(baseAttributes, arguments));
    return FlatContent(
      _flatten(type.schema, arguments, (node) {
        final newMarks = mark.addToSet(node.marks);
        return newMarks.length > node.marks.length ? node.mark(newMarks) : node;
      }),
    );
  }
}

class FlatContent {
  FlatContent(this.flat);

  final List<Node> flat;
}

Map<String, Object> _makeBuilders(Schema schema, Map<String, Attrs> config) {
  final result = <String, Object>{};
  schema.nodes.forEach((name, type) {
    result[name] = NodeBuilder(type, <String, Object?>{});
  });
  schema.marks.forEach((name, type) {
    result[name] = MarkBuilder(type, <String, Object?>{});
  });

  config.forEach((name, value) {
    final typeName = (value["nodeType"] ?? value["markType"] ?? name) as String;
    final nodeType = schema.nodes[typeName];
    if (nodeType != null) {
      result[name] = NodeBuilder(nodeType, value);
      return;
    }
    final markType = schema.marks[typeName];
    if (markType != null) {
      result[name] = MarkBuilder(markType, value);
    }
  });

  return result;
}

List<Object?> _collectArguments(List<Object?> slots) {
  final result = <Object?>[];
  for (final slot in slots) {
    if (slot != null) {
      result.add(slot);
    }
  }
  return result;
}

Attrs _takeAttributes(Attrs base, List<Object?> arguments) {
  if (arguments.isEmpty) {
    return base;
  }
  final first = arguments[0];
  if (first is! Map) {
    return base;
  }
  arguments.removeAt(0);
  return {...base, ...first.cast<String, Object?>()};
}

List<Node> _flatten(
  Schema schema,
  List<Object?> children,
  Node Function(Node) transform,
) {
  final result = <Node>[];
  for (final child in children) {
    if (child is String) {
      result.add(transform(schema.text(child)));
      continue;
    }
    if (child is FlatContent) {
      for (final node in child.flat) {
        result.add(transform(node));
      }
      continue;
    }
    if (child is NodeBuilder && child.flat != null) {
      for (final node in child.flat!) {
        result.add(transform(node));
      }
      continue;
    }
    result.add(transform(child as Node));
  }
  return result;
}

Node _identity(Node node) => node;
