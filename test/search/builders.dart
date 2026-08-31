library;

import 'package:prosemirror/prosemirror.dart';

import '../model/support/test_schema.dart';

export '../model/support/test_schema.dart' show schema, addListNodes;

bool eq(dynamic first, dynamic second) => first.eq(second) as bool;

extension SearchNodeTags on Node {
  Map<String, int> get tag => _searchNodeTags[this] ?? const <String, int>{};
}

final Map<String, Attrs> _builderConfig = {
  "p": {"nodeType": "paragraph"},
  "pre": {"nodeType": "code_block"},
  "h1": {"nodeType": "heading", "level": 1},
  "h2": {"nodeType": "heading", "level": 2},
  "h3": {"nodeType": "heading", "level": 3},
  "li": {"nodeType": "list_item"},
  "ul": {"nodeType": "bullet_list"},
  "ol": {"nodeType": "ordered_list"},
  "br": {"nodeType": "hard_break"},
  "img": {"nodeType": "image", "src": "img.png"},
  "hr": {"nodeType": "horizontal_rule"},
  "a": {"markType": "link", "href": "foo"},
};

final SearchBuilders builders = SearchBuilders(schema, _builderConfig);

final SearchNodeBuilder doc = builders.node("doc");
final SearchNodeBuilder p = builders.node("p");
final SearchNodeBuilder pre = builders.node("pre");
final SearchNodeBuilder h1 = builders.node("h1");
final SearchNodeBuilder h2 = builders.node("h2");
final SearchNodeBuilder h3 = builders.node("h3");
final SearchNodeBuilder li = builders.node("li");
final SearchNodeBuilder ul = builders.node("ul");
final SearchNodeBuilder ol = builders.node("ol");
final SearchNodeBuilder br = builders.node("br");
final SearchNodeBuilder img = builders.node("img");
final SearchNodeBuilder hr = builders.node("hr");
final SearchNodeBuilder blockquote = builders.node("blockquote");
final SearchMarkBuilder a = builders.mark("a");
final SearchMarkBuilder em = builders.mark("em");
final SearchMarkBuilder strong = builders.mark("strong");
final SearchMarkBuilder code = builders.mark("code");

class SearchBuilders {
  SearchBuilders(this.schema, Map<String, Attrs> config) {
    schema.nodes.forEach((name, type) {
      _builders[name] = SearchNodeBuilder(type, <String, Object?>{});
    });
    schema.marks.forEach((name, type) {
      _builders[name] = SearchMarkBuilder(type, <String, Object?>{});
    });

    config.forEach((name, value) {
      final typeName =
          (value["nodeType"] ?? value["markType"] ?? name) as String;
      final nodeType = schema.nodes[typeName];
      if (nodeType != null) {
        _builders[name] = SearchNodeBuilder(nodeType, value);
        return;
      }
      final markType = schema.marks[typeName];
      if (markType != null) {
        _builders[name] = SearchMarkBuilder(markType, value);
      }
    });
  }

  final Schema schema;
  final Map<String, Object> _builders = <String, Object>{};

  SearchNodeBuilder node(String name) => _builders[name]! as SearchNodeBuilder;

  SearchMarkBuilder mark(String name) => _builders[name]! as SearchMarkBuilder;
}

class SearchNodeBuilder {
  SearchNodeBuilder(this.type, this.baseAttributes) {
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
    final flattened = _flatten(type.schema, arguments, _identity);
    final node = type.create(attributes, flattened.nodes);
    if (flattened.tags != null) {
      _searchNodeTags[node] = flattened.tags!;
    }
    return node;
  }
}

class SearchMarkBuilder {
  SearchMarkBuilder(this.type, this.baseAttributes);

  final MarkType type;
  final Attrs baseAttributes;

  SearchFlatContent call([
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
    final flattened = _flatten(type.schema, arguments, (node) {
      final newMarks = mark.addToSet(node.marks);
      return newMarks.length > node.marks.length ? node.mark(newMarks) : node;
    });
    return SearchFlatContent(flattened.nodes, flattened.tags);
  }
}

class SearchFlatContent {
  SearchFlatContent(this.nodes, this.tags);

  final List<Node> nodes;
  final Map<String, int>? tags;
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

_FlattenResult _flatten(
  Schema schema,
  List<Object?> children,
  Node Function(Node) transform,
) {
  final result = <Node>[];
  var position = 0;
  Map<String, int>? tags;

  for (final child in children) {
    if (child is String) {
      var consumed = 0;
      final text = StringBuffer();
      for (final match in _tagPattern.allMatches(child)) {
        text.write(child.substring(consumed, match.start));
        position += match.start - consumed;
        consumed = match.end;
        tags ??= <String, int>{};
        tags[match.group(1)!] = position;
      }
      text.write(child.substring(consumed));
      position += child.length - consumed;
      final value = text.toString();
      if (value.isNotEmpty) {
        result.add(transform(schema.text(value)));
      }
      continue;
    }

    List<Node>? flatNodes;
    Map<String, int>? childTags;
    var isTextChild = false;
    if (child is SearchFlatContent) {
      flatNodes = child.nodes;
      childTags = child.tags;
    } else if (child is SearchNodeBuilder) {
      flatNodes = child.flat;
    } else if (child is Node) {
      childTags = child.tag;
      isTextChild = child.isText;
    }

    if (childTags != null && childTags.isNotEmpty) {
      tags ??= <String, int>{};
      final offset = (flatNodes != null || isTextChild) ? 0 : 1;
      childTags.forEach((id, value) {
        tags![id] = value + offset + position;
      });
    }

    if (flatNodes != null) {
      for (final original in flatNodes) {
        final node = transform(original);
        position += node.nodeSize;
        result.add(node);
      }
    } else {
      final node = transform(child as Node);
      position += node.nodeSize;
      result.add(node);
    }
  }

  return _FlattenResult(result, tags);
}

class _FlattenResult {
  _FlattenResult(this.nodes, this.tags);

  final List<Node> nodes;
  final Map<String, int>? tags;
}

Node _identity(Node node) => node;

final RegExp _tagPattern = RegExp(r'<(\w+)>');
final Expando<Map<String, int>> _searchNodeTags = Expando<Map<String, int>>();
