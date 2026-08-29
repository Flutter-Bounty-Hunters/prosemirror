import '../dependencies/orderedmap/ordered_map.dart';
import 'content.dart';
import 'fragment.dart';
import 'mark.dart';
import 'node.dart';

/// An object holding the attributes of a node.
typedef Attrs = Map<String, Object?>;

/// Node types are objects allocated once per [Schema] and used to tag [Node]
/// instances.
class NodeType {
  /// @internal
  NodeType(this.name, this.schema, this.spec) {
    groups = spec.group != null ? spec.group!.split(" ") : const [];
    attrs = _initAttrs(name, spec.attrs);
    defaultAttrs = _defaultAttrs(attrs);
    isBlock = !(spec.inline || name == "text");
    isText = name == "text";
  }

  /// The name the node type has in this schema.
  final String name;

  /// A link back to the [Schema] the node type belongs to.
  final Schema schema;

  /// The spec that this type is based on.
  final NodeSpec spec;

  /// @internal
  late final List<String> groups;

  /// @internal
  late final Map<String, Attribute> attrs;

  /// @internal
  late final Attrs? defaultAttrs;

  /// True if this node type has inline content.
  late bool inlineContent;

  /// True if this is a block type.
  late final bool isBlock;

  /// True if this is the text node type.
  late final bool isText;

  /// The starting match of the node type's content expression.
  late ContentMatch contentMatch;

  /// The set of marks allowed in this node. `null` means all marks are allowed.
  List<MarkType>? markSet;

  /// True if this is an inline type.
  bool get isInline => !isBlock;

  /// True if this is a textblock type, a block that contains inline content.
  bool get isTextblock => isBlock && inlineContent;

  /// True for node types that allow no content.
  bool get isLeaf => identical(contentMatch, ContentMatch.empty);

  /// True when this node is an atom.
  bool get isAtom => isLeaf || spec.atom;

  /// Return true when this node type is part of the given group.
  bool isInGroup(String group) => groups.contains(group);

  /// The node type's whitespace option.
  String get whitespace => spec.whitespace ?? (spec.code ? "pre" : "normal");

  /// Tells you whether this node type has any required attributes.
  bool hasRequiredAttrs() {
    for (final attr in attrs.values) {
      if (attr.isRequired) {
        return true;
      }
    }
    return false;
  }

  /// Indicates whether this node allows some of the same content as the given
  /// node type.
  bool compatibleContent(NodeType other) {
    return identical(this, other) ||
        contentMatch.compatible(other.contentMatch);
  }

  /// @internal
  Attrs computeAttrs(Attrs? attrs) {
    if (attrs == null && defaultAttrs != null) {
      return defaultAttrs!;
    } else {
      return _computeAttrs(this.attrs, attrs);
    }
  }

  /// Create a [Node] of this type. The given attributes are checked and
  /// defaulted. This does NOT validate attribute values.
  Node create([Attrs? attrs, Object? content, List<Mark>? marks]) {
    if (isText) {
      throw StateError("NodeType.create can't construct text nodes");
    }
    return Node(
      this,
      computeAttrs(attrs),
      Fragment.from(content),
      Mark.setFrom(marks),
    );
  }

  /// Like [create], but check the given content against the node type's content
  /// restrictions, and throw an error if it doesn't match.
  Node createChecked([Attrs? attrs, Object? content, List<Mark>? marks]) {
    final fragment = Fragment.from(content);
    checkContent(fragment);
    return Node(this, computeAttrs(attrs), fragment, Mark.setFrom(marks));
  }

  /// Like [create], but see if it is necessary to add nodes to the start or end
  /// of the given fragment to make it fit the node.
  Node? createAndFill([Attrs? attrs, Object? content, List<Mark>? marks]) {
    final computedAttrs = computeAttrs(attrs);
    var fragment = Fragment.from(content);
    if (fragment.size != 0) {
      final before = contentMatch.fillBefore(fragment);
      if (before == null) {
        return null;
      }
      fragment = before.append(fragment);
    }
    final matched = contentMatch.matchFragment(fragment);
    final after = matched?.fillBefore(Fragment.empty, true);
    if (after == null) {
      return null;
    }
    return Node(
      this,
      computedAttrs,
      fragment.append(after),
      Mark.setFrom(marks),
    );
  }

  /// Returns true if the given fragment is valid content for this node type.
  bool validContent(Fragment content) {
    final result = contentMatch.matchFragment(content);
    if (result == null || !result.validEnd) {
      return false;
    }
    for (var index = 0; index < content.childCount; index++) {
      if (!allowsMarks(content.child(index).marks)) {
        return false;
      }
    }
    return true;
  }

  /// Throws a [RangeError] if the given fragment is not valid content.
  /// @internal
  void checkContent(Fragment content) {
    if (!validContent(content)) {
      final rendered = content.toString();
      final truncated = rendered.length > 50
          ? rendered.substring(0, 50)
          : rendered;
      throw RangeError("Invalid content for node $name: $truncated");
    }
  }

  /// @internal
  void checkAttrs(Attrs attrs) {
    _checkAttrs(this.attrs, attrs, "node", name);
  }

  /// Check whether the given mark type is allowed in this node.
  bool allowsMarkType(MarkType markType) {
    return markSet == null || markSet!.contains(markType);
  }

  /// Test whether the given set of marks are allowed in this node.
  bool allowsMarks(List<Mark> marks) {
    if (markSet == null) {
      return true;
    }
    for (var index = 0; index < marks.length; index++) {
      if (!allowsMarkType(marks[index].type)) {
        return false;
      }
    }
    return true;
  }

  /// Removes the marks that are not allowed in this node from the given set.
  List<Mark> allowedMarks(List<Mark> marks) {
    if (markSet == null) {
      return marks;
    }
    List<Mark>? copy;
    for (var index = 0; index < marks.length; index++) {
      if (!allowsMarkType(marks[index].type)) {
        copy ??= marks.sublist(0, index);
      } else if (copy != null) {
        copy.add(marks[index]);
      }
    }
    if (copy == null) {
      return marks;
    }
    return copy.isNotEmpty ? copy : Mark.none;
  }

  /// @internal
  static Map<String, NodeType> compile(
    OrderedMap<NodeSpec> nodes,
    Schema schema,
  ) {
    final result = <String, NodeType>{};
    nodes.forEach((name, spec) => result[name] = NodeType(name, schema, spec));

    final topType = schema.spec.topNode ?? "doc";
    if (!result.containsKey(topType)) {
      throw RangeError("Schema is missing its top node type ('$topType')");
    }
    if (!result.containsKey("text")) {
      throw RangeError("Every schema needs a 'text' type");
    }
    if (result["text"]!.attrs.isNotEmpty) {
      throw RangeError("The text node type should not have attributes");
    }

    return result;
  }
}

void Function(Object?) _validateType(
  String typeName,
  String attrName,
  String type,
) {
  final types = type.split("|");
  return (Object? value) {
    final name = value == null
        ? "null"
        : value is bool
        ? "boolean"
        : value is num
        ? "number"
        : value is String
        ? "string"
        : "object";
    if (!types.contains(name)) {
      throw RangeError(
        "Expected value of type ${types.join(",")} for attribute $attrName on type $typeName, got $name",
      );
    }
  };
}

class Attribute {
  Attribute(String typeName, String attrName, AttributeSpec options) {
    hasDefault = options.hasDefault;
    defaultValue = options.hasDefault ? options.defaultValue : null;
    final validateOption = options.validate;
    validate = validateOption is String
        ? _validateType(typeName, attrName, validateOption)
        : validateOption as void Function(Object?)?;
  }

  late final bool hasDefault;
  late final Object? defaultValue;
  late final void Function(Object?)? validate;

  bool get isRequired => !hasDefault;
}

/// Like nodes, marks are tagged with type objects, which are instantiated once
/// per [Schema].
class MarkType {
  /// @internal
  MarkType(this.name, this.rank, this.schema, this.spec) {
    attrs = _initAttrs(name, spec.attrs);
    final defaults = _defaultAttrs(attrs);
    instance = defaults != null ? Mark(this, defaults) : null;
  }

  /// The name of the mark type.
  final String name;

  /// @internal
  final int rank;

  /// The schema that this mark type instance is part of.
  final Schema schema;

  /// The spec on which the type is based.
  final MarkSpec spec;

  /// @internal
  late final Map<String, Attribute> attrs;

  /// @internal
  late List<MarkType> excluded;

  /// @internal
  late final Mark? instance;

  /// Create a mark of this type.
  Mark create([Attrs? attrs]) {
    if (attrs == null && instance != null) {
      return instance!;
    }
    return Mark(this, _computeAttrs(this.attrs, attrs));
  }

  /// @internal
  static Map<String, MarkType> compile(
    OrderedMap<MarkSpec> marks,
    Schema schema,
  ) {
    final result = <String, MarkType>{};
    var rank = 0;
    marks.forEach((name, spec) {
      result[name] = MarkType(name, rank++, schema, spec);
    });
    return result;
  }

  /// When there is a mark of this type in the given set, a new set without it
  /// is returned.
  List<Mark> removeFromSet(List<Mark> set) {
    for (var index = 0; index < set.length; index++) {
      if (identical(set[index].type, this)) {
        set = [...set.sublist(0, index), ...set.sublist(index + 1)];
        index--;
      }
    }
    return set;
  }

  /// Tests whether there is a mark of this type in the given set.
  Mark? isInSet(List<Mark> set) {
    for (var index = 0; index < set.length; index++) {
      if (identical(set[index].type, this)) {
        return set[index];
      }
    }
    return null;
  }

  /// @internal
  void checkAttrs(Attrs attrs) {
    _checkAttrs(this.attrs, attrs, "mark", name);
  }

  /// Queries whether a given mark type is excluded by this one.
  bool excludes(MarkType other) => excluded.contains(other);
}

/// An object describing a schema, as passed to the [Schema] constructor.
class SchemaSpec {
  SchemaSpec({required this.nodes, this.marks, this.topNode});

  /// The node types in this schema. Accepts a `Map<String, NodeSpec>` or an
  /// `OrderedMap<NodeSpec>`.
  final Object nodes;

  /// The mark types that exist in this schema. Accepts a
  /// `Map<String, MarkSpec>` or an `OrderedMap<MarkSpec>`.
  final Object? marks;

  /// The name of the default top-level node for the schema.
  final String? topNode;
}

/// A description of a node type, used when defining a schema.
class NodeSpec {
  NodeSpec({
    this.content,
    this.marks,
    this.group,
    this.inline = false,
    this.atom = false,
    this.attrs,
    this.selectable,
    this.draggable = false,
    this.code = false,
    this.whitespace,
    this.definingAsContext = false,
    this.definingForContent = false,
    this.defining = false,
    this.isolating = false,
    this.toDebugString,
    this.leafText,
    this.linebreakReplacement = false,
  });

  final String? content;
  final String? marks;
  final String? group;
  final bool inline;
  final bool atom;
  final Map<String, AttributeSpec>? attrs;
  final bool? selectable;
  final bool draggable;
  final bool code;
  final String? whitespace;
  final bool definingAsContext;
  final bool definingForContent;
  final bool defining;
  final bool isolating;
  final String Function(Node)? toDebugString;
  final String Function(Node)? leafText;
  final bool linebreakReplacement;
}

/// Used to define marks when creating a schema.
class MarkSpec {
  MarkSpec({
    this.attrs,
    this.inclusive,
    this.excludes,
    this.group,
    this.spanning,
    this.code = false,
  });

  final Map<String, AttributeSpec>? attrs;
  final bool? inclusive;
  final String? excludes;
  final String? group;
  final bool? spanning;
  final bool code;
}

/// Used to define attributes on nodes or marks.
class AttributeSpec {
  const AttributeSpec({
    Object? defaultValue = _attributeDefaultSentinel,
    this.validate,
    // ignore: prefer_initializing_formals
  }) : _defaultValue = defaultValue;

  final Object? _defaultValue;

  /// A function `void Function(Object?)` or a type-name string used to validate
  /// values of this attribute.
  final Object? validate;

  /// The default value for this attribute, or `null` when [hasDefault] is
  /// false.
  Object? get defaultValue => hasDefault ? _defaultValue : null;

  /// Whether an explicit default value was supplied.
  bool get hasDefault => !identical(_defaultValue, _attributeDefaultSentinel);
}

/// A document schema.
class Schema {
  /// Construct a schema from a schema specification.
  Schema(SchemaSpec spec) {
    this.spec = SchemaSpecInstance(
      OrderedMap<NodeSpec>.from(spec.nodes),
      OrderedMap<MarkSpec>.from(spec.marks ?? <String, MarkSpec>{}),
      spec.topNode,
    );

    nodes = NodeType.compile(this.spec.nodes, this);
    marks = MarkType.compile(this.spec.marks, this);

    final contentExprCache = <String, ContentMatch>{};
    for (final entry in nodes.entries) {
      final prop = entry.key;
      if (marks.containsKey(prop)) {
        throw RangeError("$prop can not be both a node and a mark");
      }
      final type = entry.value;
      final contentExpr = type.spec.content ?? "";
      final markExpr = type.spec.marks;
      type.contentMatch = contentExprCache[contentExpr] ??= ContentMatch.parse(
        contentExpr,
        nodes,
      );
      type.inlineContent = type.contentMatch.inlineContent;
      if (type.spec.linebreakReplacement) {
        if (linebreakReplacement != null) {
          throw RangeError("Multiple linebreak nodes defined");
        }
        if (!type.isInline || !type.isLeaf) {
          throw RangeError(
            "Linebreak replacement nodes must be inline leaf nodes",
          );
        }
        linebreakReplacement = type;
      }
      type.markSet = markExpr == "_"
          ? null
          : (markExpr != null && markExpr.isNotEmpty)
          ? _gatherMarks(this, markExpr.split(" "))
          : (markExpr == "" || !type.inlineContent)
          ? <MarkType>[]
          : null;
    }
    for (final entry in marks.entries) {
      final type = entry.value;
      final excl = type.spec.excludes;
      type.excluded = excl == null
          ? [type]
          : excl.isEmpty
          ? <MarkType>[]
          : _gatherMarks(this, excl.split(" "));
    }

    topNodeType = nodes[this.spec.topNode ?? "doc"]!;
  }

  /// The spec on which the schema is based.
  late final SchemaSpecInstance spec;

  /// An object mapping the schema's node names to node type objects.
  late final Map<String, NodeType> nodes;

  /// A map from mark names to mark type objects.
  late final Map<String, MarkType> marks;

  /// The linebreak replacement node defined in this schema, if any.
  NodeType? linebreakReplacement;

  /// The type of the default top node for this schema.
  late final NodeType topNodeType;

  /// Create a node in this schema.
  Node node(Object type, [Attrs? attrs, Object? content, List<Mark>? marks]) {
    NodeType nodeType;
    if (type is String) {
      nodeType = this.nodeType(type);
    } else if (type is NodeType) {
      if (!identical(type.schema, this)) {
        throw RangeError("Node type from different schema used (${type.name})");
      }
      nodeType = type;
    } else {
      throw RangeError("Invalid node type: $type");
    }
    return nodeType.createChecked(attrs, content, marks);
  }

  /// Create a text node in the schema. Empty text nodes are not allowed.
  Node text(String text, [List<Mark>? marks]) {
    final type = nodes["text"]!;
    return TextNode(
      type,
      type.defaultAttrs ?? const {},
      text,
      Mark.setFrom(marks),
    );
  }

  /// Create a mark with the given type and attributes.
  Mark mark(Object type, [Attrs? attrs]) {
    MarkType markType;
    if (type is String) {
      markType = marks[type]!;
    } else {
      markType = type as MarkType;
    }
    return markType.create(attrs);
  }

  /// Deserialize a node from its JSON representation.
  Node nodeFromJSON(Object? json) => Node.fromJSON(this, json);

  /// Deserialize a mark from its JSON representation.
  Mark markFromJSON(Object? json) => Mark.fromJSON(this, json);

  /// @internal
  NodeType nodeType(String name) {
    final found = nodes[name];
    if (found == null) {
      throw RangeError("Unknown node type: $name");
    }
    return found;
  }
}

class SchemaSpecInstance {
  SchemaSpecInstance(this.nodes, this.marks, this.topNode);

  final OrderedMap<NodeSpec> nodes;
  final OrderedMap<MarkSpec> marks;
  final String? topNode;
}

List<MarkType> _gatherMarks(Schema schema, List<String> marks) {
  final found = <MarkType>[];
  for (var index = 0; index < marks.length; index++) {
    final name = marks[index];
    final mark = schema.marks[name];
    var ok = mark != null;
    if (mark != null) {
      found.add(mark);
    } else {
      for (final entry in schema.marks.entries) {
        final candidate = entry.value;
        if (name == "_" ||
            (candidate.spec.group != null &&
                candidate.spec.group!.split(" ").contains(name))) {
          found.add(candidate);
          ok = true;
        }
      }
    }
    if (!ok) {
      throw FormatException("Unknown mark type: '${marks[index]}'");
    }
  }
  return found;
}

Map<String, Attribute> _initAttrs(
  String typeName,
  Map<String, AttributeSpec>? attrs,
) {
  final result = <String, Attribute>{};
  if (attrs != null) {
    attrs.forEach((name, spec) {
      result[name] = Attribute(typeName, name, spec);
    });
  }
  return result;
}

/// For node types where all attrs have a default value (or which don't have
/// any attributes), build up a single reusable default attribute object.
Attrs? _defaultAttrs(Map<String, Attribute> attrs) {
  final defaults = <String, Object?>{};
  for (final entry in attrs.entries) {
    if (!entry.value.hasDefault) {
      return null;
    }
    defaults[entry.key] = entry.value.defaultValue;
  }
  return defaults;
}

Attrs _computeAttrs(Map<String, Attribute> attrs, Attrs? value) {
  final built = <String, Object?>{};
  for (final entry in attrs.entries) {
    final name = entry.key;
    Object? given = value != null ? value[name] : null;
    if (given == null && (value == null || !value.containsKey(name))) {
      final attr = entry.value;
      if (attr.hasDefault) {
        given = attr.defaultValue;
      } else {
        throw RangeError("No value supplied for attribute $name");
      }
    }
    built[name] = given;
  }
  return built;
}

void _checkAttrs(
  Map<String, Attribute> attrs,
  Attrs values,
  String type,
  String name,
) {
  for (final valueName in values.keys) {
    if (!attrs.containsKey(valueName)) {
      throw RangeError(
        "Unsupported attribute $valueName for $type of type $valueName",
      );
    }
  }
  for (final entry in attrs.entries) {
    final validate = entry.value.validate;
    if (validate != null) {
      validate(values[entry.key]);
    }
  }
}

/// Sentinel used to distinguish "no default" from "default is null" on
/// [AttributeSpec].
const Object _attributeDefaultSentinel = Object();
