/// The test-builder DSL used by the ported prosemirror-model tests.
///
/// This is a faithful Dart port of `prosemirror-test-builder`'s `build.ts` +
/// `index.ts`. It exposes concise node/mark builders (`doc`, `p`, `em`, ...),
/// an [eq] comparator, and a position-`tag` mechanism.
///
/// Position tags are written inside text as `<a>`, `<b>`, ... markers, e.g.
/// `doc(p("foo<a>bar<b>baz"))`. Because Dart cannot monkey-patch `Node`, the
/// positions are stored in a library-private [Expando] and exposed through the
/// [NodeTags] extension, so tests read them as `node.tag["a"]`.
library;

import 'package:prosemirror/prosemirror.dart';

import 'test_schema.dart';

export 'test_schema.dart' show schema, addListNodes;

/// Compares two model values (`Node`, `Fragment`, `Mark`, `Slice`, ...) using
/// their `eq` method. Mirrors test-builder's `eq`.
bool eq(dynamic a, dynamic b) => a.eq(b) as bool;

/// Reads the position tags recorded on a builder-produced [Node].
///
/// Returns an empty map when the node carries no tags.
extension NodeTags on Node {
  Map<String, int> get tag => _nodeTags[this] ?? const <String, int>{};
}

// The builders, keyed by name, exactly as configured in test-builder's
// `index.ts`.

/// Configuration for the renamed/typed builders (test-builder `index.ts`).
///
/// Each entry's `nodeType`/`markType` selects the schema type; any remaining
/// keys become the builder's base attributes (extra keys like `nodeType` are
/// ignored by the type when creating nodes).
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

final Map<String, Object> _builders = _makeBuilders(schema, _builderConfig);

final NodeBuilder doc = _builders["doc"] as NodeBuilder;
final NodeBuilder p = _builders["p"] as NodeBuilder;
final NodeBuilder pre = _builders["pre"] as NodeBuilder;
// ignore: non_constant_identifier_names
final NodeBuilder code_block = _builders["code_block"] as NodeBuilder;
final NodeBuilder h1 = _builders["h1"] as NodeBuilder;
final NodeBuilder h2 = _builders["h2"] as NodeBuilder;
final NodeBuilder h3 = _builders["h3"] as NodeBuilder;
final NodeBuilder li = _builders["li"] as NodeBuilder;
final NodeBuilder ul = _builders["ul"] as NodeBuilder;
final NodeBuilder ol = _builders["ol"] as NodeBuilder;
final NodeBuilder br = _builders["br"] as NodeBuilder;
final NodeBuilder img = _builders["img"] as NodeBuilder;
final NodeBuilder hr = _builders["hr"] as NodeBuilder;
final NodeBuilder blockquote = _builders["blockquote"] as NodeBuilder;
final MarkBuilder a = _builders["a"] as MarkBuilder;
final MarkBuilder em = _builders["em"] as MarkBuilder;
final MarkBuilder strong = _builders["strong"] as MarkBuilder;
final MarkBuilder code = _builders["code"] as MarkBuilder;

/// Builds a node with content. Mirrors test-builder's `block`.
///
/// When invoked, an optional leading attributes [Map] is merged over the
/// builder's base attributes; the remaining arguments become the node's
/// children (see [_flatten]).
class NodeBuilder {
  NodeBuilder(this.type, this.baseAttributes) {
    if (type.isLeaf) {
      try {
        flat = [type.create(baseAttributes)];
      } catch (_) {
        // Leaf builders that require attributes cannot be pre-created; they
        // are simply never usable as an uncalled child.
      }
    }
  }

  final NodeType type;
  final Attrs baseAttributes;

  /// The pre-built leaf node, when this builder is a leaf. Lets an uncalled
  /// leaf builder (e.g. `p(br, "x")`) act as a child.
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

/// Builds mark-wrapped inline content. Mirrors test-builder's `mark`.
///
/// Returns a [FlatContent] whose nodes carry the added mark. When nested
/// inside a node builder it contributes those flat nodes.
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
    final flattened = _flatten(type.schema, arguments, (node) {
      final newMarks = mark.addToSet(node.marks);
      return newMarks.length > node.marks.length ? node.mark(newMarks) : node;
    });
    return FlatContent(flattened.nodes, flattened.tag);
  }
}

/// A flat list of nodes (with position tags) produced by a [MarkBuilder].
///
/// Mirrors test-builder's `{flat, tag}` child spec.
class FlatContent {
  FlatContent(this.flat, this.tag);

  final List<Node> flat;
  final Map<String, int>? tag;
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

/// Turns a builder's raw argument slots into the list of supplied arguments.
///
/// Trailing unsupplied slots arrive as `null`; children are never null, so
/// dropping nulls recovers exactly the arguments the caller passed.
List<Object?> _collectArguments(List<Object?> slots) {
  final result = <Object?>[];
  for (final slot in slots) {
    if (slot != null) {
      result.add(slot);
    }
  }
  return result;
}

/// Peels an optional leading attributes [Map] off [arguments], merging it over
/// [base]. Mirrors test-builder's `takeAttrs`.
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

/// Flattens builder children into nodes while computing position tags.
///
/// Mirrors test-builder's `flatten`:
///  - text `<x>` markers record the running position;
///  - entering a non-flat, non-text child adds +1 for its open token;
///  - flat/text children add their `nodeSize` with no +1.
_FlattenResult _flatten(
  Schema schema,
  List<Object?> children,
  Node Function(Node) transform,
) {
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

Node _identity(Node node) => node;

final RegExp _tagPattern = RegExp(r'<(\w+)>');

/// Stores position tags per builder-produced node (test-builder monkey-patches
/// `.tag` onto `Node`; Dart uses this side table instead).
final Expando<Map<String, int>> _nodeTags = Expando<Map<String, int>>();
