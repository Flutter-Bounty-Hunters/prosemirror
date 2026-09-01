import 'package:prosemirror/prosemirror.dart';

/// Creates a builder function map for nodes and marks in the schema.
Map<String, dynamic> builders(Schema schema, [Map<String, Map<String, dynamic>>? config]) {
  final result = <String, dynamic>{};

  result['schema'] = schema;

  schema.nodes.forEach((name, type) {
    result[name] = NodeBuilder(type, <String, dynamic>{});
  });
  schema.marks.forEach((name, type) {
    result[name] = MarkBuilder(type, <String, dynamic>{});
  });

  if (config != null) {
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
  }

  return result;
}

class NodeBuilder {
  NodeBuilder(this.type, this.baseAttributes) {
    if (type.isLeaf) {
      try {
        flat = [type.create(baseAttributes)];
      } catch (_) {
        // Leaf builders that require attributes cannot be pre-created.
      }
    }
  }

  final NodeType type;
  final Map<String, dynamic> baseAttributes;
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
    if (flattened.tag != null) {
      _nodeTags[node] = flattened.tag!;
    }
    return node;
  }
}

class MarkBuilder {
  MarkBuilder(this.type, this.baseAttributes);

  final MarkType type;
  final Map<String, dynamic> baseAttributes;

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
    final flattened = _flatten(type.schema, arguments, (node) {
      final newMarks = mark.addToSet(node.marks);
      return newMarks.length > node.marks.length ? node.mark(newMarks) : node;
    });
    return FlatContent(flattened.nodes, flattened.tag);
  }
}

class FlatContent {
  FlatContent(this.flat, this.tag);

  final List<Node> flat;
  final Map<String, int>? tag;
}

/// Compares two model values (`Node`, `Fragment`, `Mark`, `Slice`, ...) using
/// their `eq` method. Mirrors test-builder's `eq`.
bool eq(dynamic a, dynamic b) => a.eq(b) as bool;

/// Reads the position tags recorded on a builder-produced [Node].
///
/// Returns an empty map when the node carries no tags.
extension NodeTags on Node {
  Map<String, int> get tag => _nodeTags[this] ?? const <String, int>{};
}

/// Stores position tags per builder-produced node.
final Expando<Map<String, int>> _nodeTags = Expando<Map<String, int>>();

List<Object?> _collectArguments(List<Object?> slots) {
  final result = <Object?>[];
  for (final slot in slots) {
    if (slot != null) {
      result.add(slot);
    }
  }
  return result;
}

Map<String, dynamic> _takeAttributes(Map<String, dynamic> base, List<Object?> arguments) {
  if (arguments.isEmpty) {
    return base;
  }
  final first = arguments[0];
  if (first is! Map) {
    return base;
  }
  arguments.removeAt(0);
  return {...base, ...first.cast<String, dynamic>()};
}

_FlattenResult _flatten(Schema schema, List<Object?> children, Node Function(Node) transform) {
  final result = <Node>[];
  var position = 0;
  Map<String, int>? tag;

  for (final child in children) {
    if (child is String) {
      var consumed = 0;
      final buffer = StringBuffer();
      for (final match in _tagPattern.allMatches(child)) {
        buffer.write(child.substring(consumed, match.start));
        position += match.start - consumed;
        consumed = match.end;
        tag ??= <String, int>{};
        tag[match.group(1)!] = position;
      }
      buffer.write(child.substring(consumed));
      position += child.length - consumed;
      final text = buffer.toString();
      if (text.isNotEmpty) {
        result.add(transform(schema.text(text)));
      }
      continue;
    }

    List<Node>? flatNodes;
    Map<String, int>? childTag;
    var isTextChild = false;

    if (child is FlatContent) {
      flatNodes = child.flat;
      childTag = child.tag;
    } else if (child is NodeBuilder) {
      flatNodes = child.flat;
    } else if (child is Node) {
      childTag = _nodeTags[child];
      isTextChild = child.isText;
    }

    if (childTag != null && childTag.isNotEmpty) {
      tag ??= <String, int>{};
      final offset = (flatNodes != null || isTextChild) ? 0 : 1;
      childTag.forEach((id, value) {
        tag![id] = value + offset + position;
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

  return _FlattenResult(result, tag);
}

class _FlattenResult {
  _FlattenResult(this.nodes, this.tag);

  final List<Node> nodes;
  final Map<String, int>? tag;
}

final RegExp _tagPattern = RegExp(r'<(\w+)>');

Node _identity(Node node) => node;
