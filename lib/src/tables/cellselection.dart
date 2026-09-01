// This file defines a ProseMirror selection subclass that models table cell
// selections. The table plugin needs to be active to wire in the user
// interaction part of table selections (so that you actually get such
// selections when you select across cells).

import 'dart:math' as math;

import 'package:prosemirror/prosemirror.dart';

import 'package:prosemirror/src/tables/schema.dart';
import 'package:prosemirror/src/tables/tablemap.dart';
import 'package:prosemirror/src/tables/util.dart';

/// JSON representation of a [CellSelection].
class CellSelectionJSON {
  CellSelectionJSON({required this.type, required this.anchor, required this.head});

  final String type;
  final int anchor;
  final int head;
}

bool _cellSelectionRegistered = false;
void _ensureCellSelectionRegistered() {
  if (_cellSelectionRegistered) {
    return;
  }
  _cellSelectionRegistered = true;
  Selection.jsonID("cell", CellSelection.fromJSON);
}

/// A [Selection] subclass that represents a cell selection spanning part of a
/// table.
class CellSelection extends Selection {
  CellSelection._(this.$anchorCell, this.$headCell, List<SelectionRange> ranges)
    : super(ranges[0].$from, ranges[0].$to, ranges);

  /// A table selection is identified by its anchor and head cells. The
  /// positions given should point _before_ two cells in the same table. They
  /// may be the same, to select a single cell.
  factory CellSelection(ResolvedPos $anchorCell, [ResolvedPos? $headCell]) {
    _ensureCellSelectionRegistered();
    final headCell = $headCell ?? $anchorCell;
    final table = $anchorCell.node(-1);
    final map = TableMap.get(table);
    final tableStart = $anchorCell.start(-1);
    final rect = map.rectBetween($anchorCell.pos - tableStart, headCell.pos - tableStart);

    final document = $anchorCell.node(0);
    final cells = map.cellsInRect(rect).where((p) => p != headCell.pos - tableStart).toList();
    // Make the head cell the first range, so that it counts as the primary
    // part of the selection.
    cells.insert(0, headCell.pos - tableStart);
    final ranges = cells.map((pos) {
      final cell = table.nodeAt(pos);
      if (cell == null) {
        throw RangeError("No cell with offset $pos found");
      }
      final from = tableStart + pos + 1;
      return SelectionRange(document.resolve(from), document.resolve(from + cell.content.size));
    }).toList();
    return CellSelection._($anchorCell, headCell, ranges);
  }

  /// A resolved position pointing _in front of_ the anchor cell (the one that
  /// doesn't move when extending the selection).
  final ResolvedPos $anchorCell;

  /// A resolved position pointing in front of the head cell (the one that
  /// moves when extending the selection).
  final ResolvedPos $headCell;

  @override
  bool get visible => false;

  @override
  Selection map(Node doc, Mappable mapping) {
    final $anchorCell = doc.resolve(mapping.map(this.$anchorCell.pos));
    final $headCell = doc.resolve(mapping.map(this.$headCell.pos));
    if (pointsAtCell($anchorCell) && pointsAtCell($headCell) && inSameTable($anchorCell, $headCell)) {
      final tableChanged = !identical(this.$anchorCell.node(-1), $anchorCell.node(-1));
      if (tableChanged && isRowSelection()) {
        return CellSelection.rowSelection($anchorCell, $headCell);
      } else if (tableChanged && isColSelection()) {
        return CellSelection.colSelection($anchorCell, $headCell);
      } else {
        return CellSelection($anchorCell, $headCell);
      }
    }
    return TextSelection.between($anchorCell, $headCell);
  }

  /// Returns a rectangular slice of table rows containing the selected cells.
  @override
  Slice content() {
    final table = $anchorCell.node(-1);
    final map = TableMap.get(table);
    final tableStart = $anchorCell.start(-1);

    final rect = map.rectBetween($anchorCell.pos - tableStart, $headCell.pos - tableStart);
    final seen = <int>{};
    final rows = <Node>[];
    for (var row = rect.top; row < rect.bottom; row++) {
      final rowContent = <Node>[];
      for (var index = row * map.width + rect.left, col = rect.left; col < rect.right; col++, index++) {
        final pos = map.map[index];
        if (seen.contains(pos)) {
          continue;
        }
        seen.add(pos);

        final cellRect = map.findCell(pos);
        var cell = table.nodeAt(pos);
        if (cell == null) {
          throw RangeError("No cell with offset $pos found");
        }

        final extraLeft = rect.left - cellRect.left;
        final extraRight = cellRect.right - rect.right;

        if (extraLeft > 0 || extraRight > 0) {
          var attrs = cell.attrs;
          if (extraLeft > 0) {
            attrs = removeColSpan(attrs, 0, extraLeft);
          }
          if (extraRight > 0) {
            attrs = removeColSpan(attrs, (attrs["colspan"] as int) - extraRight, extraRight);
          }
          if (cellRect.left < rect.left) {
            final filled = cell.type.createAndFill(attrs);
            if (filled == null) {
              throw RangeError("Could not create cell with attrs $attrs");
            }
            cell = filled;
          } else {
            cell = cell.type.create(attrs, cell.content);
          }
        }
        if (cellRect.top < rect.top || cellRect.bottom > rect.bottom) {
          final attrs = <String, Object?>{
            ...cell.attrs,
            "rowspan": math.min(cellRect.bottom, rect.bottom) - math.max(cellRect.top, rect.top),
          };
          if (cellRect.top < rect.top) {
            cell = cell.type.createAndFill(attrs)!;
          } else {
            cell = cell.type.create(attrs, cell.content);
          }
        }
        rowContent.add(cell);
      }
      rows.add(table.child(row).copy(Fragment.from(rowContent)));
    }

    final Object fragment = isColSelection() && isRowSelection() ? table : rows;
    return Slice(Fragment.from(fragment), 1, 1);
  }

  @override
  void replace(Transaction tr, [Slice? content]) {
    content ??= Slice.empty;
    final mapFrom = tr.steps.length;
    final ranges = this.ranges;
    for (var i = 0; i < ranges.length; i++) {
      final $from = ranges[i].$from;
      final $to = ranges[i].$to;
      final mapping = tr.mapping.slice(mapFrom);
      tr.replace(mapping.map($from.pos), mapping.map($to.pos), i != 0 ? Slice.empty : content);
    }
    final sel = Selection.findFrom(tr.doc.resolve(tr.mapping.slice(mapFrom).map(to)), -1);
    if (sel != null) {
      tr.setSelection(sel);
    }
  }

  @override
  void replaceWith(Transaction tr, Node node) {
    replace(tr, Slice(Fragment.from(node), 0, 0));
  }

  /// Calls [f] for each cell in the selection.
  void forEachCell(void Function(Node node, int pos) f) {
    final table = $anchorCell.node(-1);
    final map = TableMap.get(table);
    final tableStart = $anchorCell.start(-1);

    final cells = map.cellsInRect(map.rectBetween($anchorCell.pos - tableStart, $headCell.pos - tableStart));
    for (var i = 0; i < cells.length; i++) {
      f(table.nodeAt(cells[i])!, tableStart + cells[i]);
    }
  }

  /// True if this selection goes all the way from the top to the bottom of the
  /// table.
  bool isColSelection() {
    final anchorTop = $anchorCell.index(-1);
    final headTop = $headCell.index(-1);
    if (math.min(anchorTop, headTop) > 0) {
      return false;
    }

    final anchorBottom = anchorTop + ($anchorCell.nodeAfter!.attrs["rowspan"] as int);
    final headBottom = headTop + ($headCell.nodeAfter!.attrs["rowspan"] as int);

    return math.max(anchorBottom, headBottom) == $headCell.node(-1).childCount;
  }

  /// Returns the smallest column selection that covers the given anchor and
  /// head cell.
  static CellSelection colSelection(ResolvedPos $anchorCell, [ResolvedPos? $headCell]) {
    var anchorCell = $anchorCell;
    var headCell = $headCell ?? $anchorCell;
    final table = anchorCell.node(-1);
    final map = TableMap.get(table);
    final tableStart = anchorCell.start(-1);

    final anchorRect = map.findCell(anchorCell.pos - tableStart);
    final headRect = map.findCell(headCell.pos - tableStart);
    final document = anchorCell.node(0);

    if (anchorRect.top <= headRect.top) {
      if (anchorRect.top > 0) {
        anchorCell = document.resolve(tableStart + map.map[anchorRect.left]);
      }
      if (headRect.bottom < map.height) {
        headCell = document.resolve(tableStart + map.map[map.width * (map.height - 1) + headRect.right - 1]);
      }
    } else {
      if (headRect.top > 0) {
        headCell = document.resolve(tableStart + map.map[headRect.left]);
      }
      if (anchorRect.bottom < map.height) {
        anchorCell = document.resolve(tableStart + map.map[map.width * (map.height - 1) + anchorRect.right - 1]);
      }
    }
    return CellSelection(anchorCell, headCell);
  }

  /// True if this selection goes all the way from the left to the right of the
  /// table.
  bool isRowSelection() {
    final table = $anchorCell.node(-1);
    final map = TableMap.get(table);
    final tableStart = $anchorCell.start(-1);

    final anchorLeft = map.colCount($anchorCell.pos - tableStart);
    final headLeft = map.colCount($headCell.pos - tableStart);
    if (math.min(anchorLeft, headLeft) > 0) {
      return false;
    }

    final anchorRight = anchorLeft + ($anchorCell.nodeAfter!.attrs["colspan"] as int);
    final headRight = headLeft + ($headCell.nodeAfter!.attrs["colspan"] as int);
    return math.max(anchorRight, headRight) == map.width;
  }

  @override
  bool eq(Selection other) {
    return other is CellSelection && other.$anchorCell.pos == $anchorCell.pos && other.$headCell.pos == $headCell.pos;
  }

  /// Returns the smallest row selection that covers the given anchor and head
  /// cell.
  static CellSelection rowSelection(ResolvedPos $anchorCell, [ResolvedPos? $headCell]) {
    var anchorCell = $anchorCell;
    var headCell = $headCell ?? $anchorCell;
    final table = anchorCell.node(-1);
    final map = TableMap.get(table);
    final tableStart = anchorCell.start(-1);

    final anchorRect = map.findCell(anchorCell.pos - tableStart);
    final headRect = map.findCell(headCell.pos - tableStart);
    final document = anchorCell.node(0);

    if (anchorRect.left <= headRect.left) {
      if (anchorRect.left > 0) {
        anchorCell = document.resolve(tableStart + map.map[anchorRect.top * map.width]);
      }
      if (headRect.right < map.width) {
        headCell = document.resolve(tableStart + map.map[map.width * (headRect.top + 1) - 1]);
      }
    } else {
      if (headRect.left > 0) {
        headCell = document.resolve(tableStart + map.map[headRect.top * map.width]);
      }
      if (anchorRect.right < map.width) {
        anchorCell = document.resolve(tableStart + map.map[map.width * (anchorRect.top + 1) - 1]);
      }
    }
    return CellSelection(anchorCell, headCell);
  }

  @override
  Map<String, Object?> toJSON() {
    return <String, Object?>{"type": "cell", "anchor": $anchorCell.pos, "head": $headCell.pos};
  }

  /// Deserialize a [CellSelection] from JSON.
  static CellSelection fromJSON(Node doc, Map<String, Object?> json) {
    return CellSelection(doc.resolve(json["anchor"] as int), doc.resolve(json["head"] as int));
  }

  /// Create a [CellSelection] from unresolved positions.
  static CellSelection create(Node doc, int anchorCell, [int? headCell]) {
    return CellSelection(doc.resolve(anchorCell), doc.resolve(headCell ?? anchorCell));
  }

  @override
  CellBookmark getBookmark() {
    return CellBookmark($anchorCell.pos, $headCell.pos);
  }
}

/// A document-independent representation of a [CellSelection].
class CellBookmark implements SelectionBookmark {
  CellBookmark(this.anchor, this.head);

  final int anchor;
  final int head;

  @override
  CellBookmark map(Mappable mapping) {
    return CellBookmark(mapping.map(anchor), mapping.map(head));
  }

  @override
  Selection resolve(Node doc) {
    final $anchorCell = doc.resolve(anchor);
    final $headCell = doc.resolve(head);
    if (tableRoleOf($anchorCell.parent.type) == TableRole.row &&
        tableRoleOf($headCell.parent.type) == TableRole.row &&
        $anchorCell.index() < $anchorCell.parent.childCount &&
        $headCell.index() < $headCell.parent.childCount &&
        inSameTable($anchorCell, $headCell)) {
      return CellSelection($anchorCell, $headCell);
    } else {
      return Selection.near($headCell, 1);
    }
  }
}
