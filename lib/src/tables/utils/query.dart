import 'package:prosemirror/prosemirror.dart';

import 'package:prosemirror/src/tables/cellselection.dart';
import 'package:prosemirror/src/tables/schema.dart';
import 'package:prosemirror/src/tables/util.dart';

/// Result of finding a parent node.
class FindNodeResult {
  FindNodeResult({required this.node, required this.pos, required this.start, required this.depth});

  /// The closest parent node that satisfies the predicate.
  final Node node;

  /// The position directly before the node.
  final int pos;

  /// The position at the start of the node.
  final int start;

  /// The depth of the node.
  final int depth;
}

/// Find the closest table node for a given position.
FindNodeResult? findTable(ResolvedPos $pos) {
  return _findParentNode((node) => tableRoleOf(node.type) == TableRole.table, $pos);
}

/// Try to find the anchor and head cell in the same table by using the given
/// anchor and head as hit points, or fallback to the selection's anchor and
/// head.
List<ResolvedPos>? findCellRange(Selection selection, [int? anchorHit, int? headHit]) {
  if (anchorHit == null && headHit == null && selection is CellSelection) {
    return [selection.$anchorCell, selection.$headCell];
  }

  final anchor = anchorHit ?? headHit ?? selection.anchor;
  final head = headHit ?? anchorHit ?? selection.head;

  final document = selection.$head.doc;

  final $anchorCell = findCellPos(document, anchor);
  final $headCell = findCellPos(document, head);

  if ($anchorCell != null && $headCell != null && inSameTable($anchorCell, $headCell)) {
    return [$anchorCell, $headCell];
  }
  return null;
}

/// Try to find a resolved position of a cell by using the given [pos] as a hit
/// point.
ResolvedPos? findCellPos(Node document, int pos) {
  final $pos = document.resolve(pos);
  return cellAround($pos) ?? cellNear($pos);
}

FindNodeResult? _findParentNode(bool Function(Node node) predicate, ResolvedPos $pos) {
  for (var depth = $pos.depth; depth >= 0; depth -= 1) {
    final node = $pos.node(depth);

    if (predicate(node)) {
      final pos = depth == 0 ? 0 : $pos.before(depth);
      final start = $pos.start(depth);
      return FindNodeResult(node: node, pos: pos, start: start, depth: depth);
    }
  }

  return null;
}
