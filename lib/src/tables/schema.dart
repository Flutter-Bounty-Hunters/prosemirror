// Helper for creating a schema that supports tables.

import 'package:prosemirror/prosemirror.dart';

/// The role a node type plays in a table.
///
/// The string [value] matches the value ProseMirror uses on the node spec's
/// `tableRole` property upstream.
enum TableRole {
  table("table"),
  row("row"),
  cell("cell"),
  headerCell("header_cell");

  const TableRole(this.value);

  /// The string value used by upstream ProseMirror for this role.
  final String value;
}

/// Associates a [TableRole] with a [NodeSpec] instance.
///
/// Upstream stores the role directly on the node spec via a `tableRole`
/// property. Our [NodeSpec] has no such slot, so we key an [Expando] by the
/// spec instance instead. The same spec instance flows to [NodeType.spec], so
/// [tableRoleOf] can resolve the role from a node type.
final Expando<TableRole> _tableRole = Expando<TableRole>("tableRole");

/// Returns the [TableRole] associated with the given node [type], if any.
TableRole? tableRoleOf(NodeType type) => _tableRole[type.spec];

/// Additional attributes to add to table cells.
class CellAttributes {
  CellAttributes({this.defaultValue, this.validate});

  /// The attribute's default value.
  final Object? defaultValue;

  /// A function or type name used to validate values of this attribute.
  final Object? validate;
}

/// Options for [tableNodes].
class TableNodesOptions {
  TableNodesOptions({this.tableGroup, required this.cellContent, required this.cellAttributes});

  /// A group name (something like `"block"`) to add to the table node type.
  final String? tableGroup;

  /// The content expression for table cells.
  final String cellContent;

  /// Additional attributes to add to cells.
  final Map<String, CellAttributes> cellAttributes;
}

void _validateColwidth(Object? value) {
  if (value == null) {
    return;
  }
  if (value is! List) {
    throw ArgumentError("colwidth must be null or an array");
  }
  for (final item in value) {
    if (item is! num) {
      throw ArgumentError("colwidth must be null or an array of numbers");
    }
  }
}

/// Creates a set of node specs for `table`, `table_row`, `table_cell`, and
/// `table_header` node types as used by this module. The result can then be
/// added to the set of nodes when creating a schema.
Map<String, NodeSpec> tableNodes(TableNodesOptions options) {
  final extraAttrs = options.cellAttributes;
  final cellAttrs = <String, AttributeSpec>{
    "colspan": const AttributeSpec(defaultValue: 1, validate: "number"),
    "rowspan": const AttributeSpec(defaultValue: 1, validate: "number"),
    "colwidth": const AttributeSpec(defaultValue: null, validate: _validateColwidth),
  };
  extraAttrs.forEach((prop, attribute) {
    cellAttrs[prop] = AttributeSpec(defaultValue: attribute.defaultValue, validate: attribute.validate);
  });

  final table = NodeSpec(content: "table_row+", isolating: true, group: options.tableGroup);
  final tableRow = NodeSpec(content: "(table_cell | table_header)*");
  final tableCell = NodeSpec(content: options.cellContent, attrs: cellAttrs, isolating: true);
  final tableHeader = NodeSpec(content: options.cellContent, attrs: cellAttrs, isolating: true);

  _tableRole[table] = TableRole.table;
  _tableRole[tableRow] = TableRole.row;
  _tableRole[tableCell] = TableRole.cell;
  _tableRole[tableHeader] = TableRole.headerCell;

  return <String, NodeSpec>{
    "table": table,
    "table_row": tableRow,
    "table_cell": tableCell,
    "table_header": tableHeader,
  };
}

/// Cache of table node types per schema, mirroring the upstream
/// `schema.cached.tableNodeTypes` mechanism.
final Expando<Map<TableRole, NodeType>> _tableNodeTypesCache = Expando<Map<TableRole, NodeType>>();

/// Returns a map from [TableRole] to the [NodeType] in [schema] that plays
/// that role.
Map<TableRole, NodeType> tableNodeTypes(Schema schema) {
  var result = _tableNodeTypesCache[schema];
  if (result == null) {
    result = <TableRole, NodeType>{};
    schema.nodes.forEach((name, type) {
      final role = tableRoleOf(type);
      if (role != null) {
        result![role] = type;
      }
    });
    _tableNodeTypesCache[schema] = result;
  }
  return result;
}
