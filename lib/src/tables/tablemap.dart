// Because working with row and column-spanning cells is not quite trivial,
// this code builds up a descriptive structure for a given table node. The
// structures are cached with the (persistent) table nodes as key, so that they
// only have to be recomputed when the content of the table changes.
//
// This does mean that they have to store table-relative, not document-relative
// positions. So code that uses them will typically compute the start position
// of the table and offset positions passed to or gotten from this structure by
// that amount.

import 'dart:math' as math;

import 'package:prosemirror/prosemirror.dart';

import 'package:prosemirror/src/tables/schema.dart';

/// A list of column widths.
typedef ColWidths = List<int>;

/// A problem detected in a table's shape, used by the table normalizer.
sealed class Problem {}

/// A cell whose stored column widths disagree with the computed ones.
class ColwidthMismatchProblem extends Problem {
  ColwidthMismatchProblem(this.pos, this.colwidth);

  final int pos;
  final ColWidths colwidth;
}

/// Two cells overlap in the table grid.
class CollisionProblem extends Problem {
  CollisionProblem(this.pos, this.row, this.n);

  final int pos;
  final int row;
  final int n;
}

/// A row is missing cells.
class MissingProblem extends Problem {
  MissingProblem(this.row, this.n);

  final int row;
  final int n;
}

/// A cell's rowspan sticks out of the bottom of the table.
class OverlongRowspanProblem extends Problem {
  OverlongRowspanProblem(this.pos, this.n);

  final int pos;
  final int n;
}

/// The table has no cells at all.
class ZeroSizedProblem extends Problem {
  ZeroSizedProblem();
}

/// Cache of table maps keyed by their (persistent) table node.
final Expando<TableMap> _tableMapCache = Expando<TableMap>("tableMap");

/// A rectangle of cells in a table map.
class Rect {
  Rect({required this.left, required this.top, required this.right, required this.bottom});

  int left;
  int top;
  int right;
  int bottom;
}

/// A table map describes the structure of a given table. To avoid recomputing
/// them all the time, they are cached per table node. To be able to do that,
/// positions saved in the map are relative to the start of the table, rather
/// than the start of the document.
class TableMap {
  TableMap(this.width, this.height, this.map, this.problems);

  /// The number of columns.
  final int width;

  /// The number of rows.
  final int height;

  /// A width * height array with the start position of the cell covering that
  /// part of the table in each slot.
  final List<int> map;

  /// An optional array of problems (cell overlap or non-rectangular shape) for
  /// the table, used by the table normalizer.
  List<Problem>? problems;

  /// Find the dimensions of the cell at the given position.
  Rect findCell(int pos) {
    for (var i = 0; i < map.length; i++) {
      final curPos = map[i];
      if (curPos != pos) {
        continue;
      }

      final left = i % width;
      final top = i ~/ width;
      var right = left + 1;
      var bottom = top + 1;

      for (var j = 1; right < width && map[i + j] == curPos; j++) {
        right++;
      }
      for (var j = 1; bottom < height && map[i + width * j] == curPos; j++) {
        bottom++;
      }

      return Rect(left: left, top: top, right: right, bottom: bottom);
    }
    throw RangeError("No cell with offset $pos found");
  }

  /// Find the left side of the cell at the given position.
  int colCount(int pos) {
    for (var i = 0; i < map.length; i++) {
      if (map[i] == pos) {
        return i % width;
      }
    }
    throw RangeError("No cell with offset $pos found");
  }

  /// Find the next cell in the given direction, starting from the cell at
  /// [pos], if any.
  int? nextCell(int pos, String axis, int dir) {
    final rect = findCell(pos);
    if (axis == "horiz") {
      if (dir < 0 ? rect.left == 0 : rect.right == width) {
        return null;
      }
      return map[rect.top * width + (dir < 0 ? rect.left - 1 : rect.right)];
    } else {
      if (dir < 0 ? rect.top == 0 : rect.bottom == height) {
        return null;
      }
      return map[rect.left + width * (dir < 0 ? rect.top - 1 : rect.bottom)];
    }
  }

  /// Get the rectangle spanning the two given cells.
  Rect rectBetween(int a, int b) {
    final rectA = findCell(a);
    final rectB = findCell(b);
    return Rect(
      left: math.min(rectA.left, rectB.left),
      top: math.min(rectA.top, rectB.top),
      right: math.max(rectA.right, rectB.right),
      bottom: math.max(rectA.bottom, rectB.bottom),
    );
  }

  /// Return the position of all cells that have the top left corner in the
  /// given rectangle.
  List<int> cellsInRect(Rect rect) {
    final result = <int>[];
    final seen = <int>{};
    for (var row = rect.top; row < rect.bottom; row++) {
      for (var col = rect.left; col < rect.right; col++) {
        final index = row * width + col;
        final pos = map[index];

        if (seen.contains(pos)) {
          continue;
        }
        seen.add(pos);

        if ((col == rect.left && col != 0 && map[index - 1] == pos) ||
            (row == rect.top && row != 0 && map[index - width] == pos)) {
          continue;
        }
        result.add(pos);
      }
    }
    return result;
  }

  /// Return the position at which the cell at the given row and column starts,
  /// or would start, if a cell started there.
  int positionAt(int row, int col, Node table) {
    for (var i = 0, rowStart = 0; ; i++) {
      final rowEnd = rowStart + table.child(i).nodeSize;
      if (i == row) {
        var index = col + row * width;
        final rowEndIndex = (row + 1) * width;
        // Skip past cells from previous rows (via rowspan).
        while (index < rowEndIndex && map[index] < rowStart) {
          index++;
        }
        return index == rowEndIndex ? rowEnd - 1 : map[index];
      }
      rowStart = rowEnd;
    }
  }

  /// Find the table map for the given table node.
  static TableMap get(Node table) {
    return _tableMapCache[table] ??= _computeMap(table);
  }
}

// Compute a table map.
TableMap _computeMap(Node table) {
  if (tableRoleOf(table.type) != TableRole.table) {
    throw RangeError("Not a table node: ${table.type.name}");
  }
  final width = _findWidth(table);
  final height = table.childCount;
  final map = <int>[];
  var mapPos = 0;
  List<Problem>? problems;
  final colWidths = List<int?>.filled(width * 2, null, growable: true);
  for (var i = 0, e = width * height; i < e; i++) {
    map.add(0);
  }

  for (var row = 0, pos = 0; row < height; row++) {
    final rowNode = table.child(row);
    pos++;
    for (var i = 0; ; i++) {
      while (mapPos < map.length && map[mapPos] != 0) {
        mapPos++;
      }
      if (i == rowNode.childCount) {
        break;
      }
      final cellNode = rowNode.child(i);
      final colspan = cellNode.attrs["colspan"] as int;
      final rowspan = cellNode.attrs["rowspan"] as int;
      final colwidth = cellNode.attrs["colwidth"] as List?;
      for (var h = 0; h < rowspan; h++) {
        if (h + row >= height) {
          (problems ??= <Problem>[]).add(OverlongRowspanProblem(pos, rowspan - h));
          break;
        }
        final start = mapPos + h * width;
        for (var w = 0; w < colspan; w++) {
          if (map[start + w] == 0) {
            map[start + w] = pos;
          } else {
            (problems ??= <Problem>[]).add(CollisionProblem(pos, row, colspan - w));
          }
          final colW = (colwidth != null && w < colwidth.length) ? colwidth[w] as int : null;
          if (colW != null && colW != 0) {
            final widthIndex = ((start + w) % width) * 2;
            final prev = colWidths[widthIndex];
            if (prev == null || (prev != colW && colWidths[widthIndex + 1] == 1)) {
              colWidths[widthIndex] = colW;
              colWidths[widthIndex + 1] = 1;
            } else if (prev == colW) {
              colWidths[widthIndex + 1] = colWidths[widthIndex + 1]! + 1;
            }
          }
        }
      }
      mapPos += colspan;
      pos += cellNode.nodeSize;
    }
    final expectedPos = (row + 1) * width;
    var missing = 0;
    while (mapPos < expectedPos) {
      if (map[mapPos++] == 0) {
        missing++;
      }
    }
    if (missing != 0) {
      (problems ??= <Problem>[]).add(MissingProblem(row, missing));
    }
    pos++;
  }

  if (width == 0 || height == 0) {
    (problems ??= <Problem>[]).add(ZeroSizedProblem());
  }

  final tableMap = TableMap(width, height, map, problems);
  var badWidths = false;

  // For columns that have defined widths, but whose widths disagree between
  // rows, fix up the cells whose width doesn't match the computed one.
  for (var i = 0; !badWidths && i < colWidths.length; i += 2) {
    if (colWidths[i] != null && colWidths[i + 1]! < height) {
      badWidths = true;
    }
  }
  if (badWidths) {
    _findBadColWidths(tableMap, colWidths, table);
  }

  return tableMap;
}

int _findWidth(Node table) {
  var width = -1;
  var hasRowSpan = false;
  for (var row = 0; row < table.childCount; row++) {
    final rowNode = table.child(row);
    var rowWidth = 0;
    if (hasRowSpan) {
      for (var j = 0; j < row; j++) {
        final prevRow = table.child(j);
        for (var i = 0; i < prevRow.childCount; i++) {
          final cell = prevRow.child(i);
          if (j + (cell.attrs["rowspan"] as int) > row) {
            rowWidth += cell.attrs["colspan"] as int;
          }
        }
      }
    }
    for (var i = 0; i < rowNode.childCount; i++) {
      final cell = rowNode.child(i);
      rowWidth += cell.attrs["colspan"] as int;
      if ((cell.attrs["rowspan"] as int) > 1) {
        hasRowSpan = true;
      }
    }
    if (width == -1) {
      width = rowWidth;
    } else if (width != rowWidth) {
      width = math.max(width, rowWidth);
    }
  }
  return width;
}

void _findBadColWidths(TableMap map, List<int?> colWidths, Node table) {
  map.problems ??= <Problem>[];
  final seen = <int>{};
  for (var i = 0; i < map.map.length; i++) {
    final pos = map.map[i];
    if (seen.contains(pos)) {
      continue;
    }
    seen.add(pos);
    final node = table.nodeAt(pos);
    if (node == null) {
      throw RangeError("No cell with offset $pos found");
    }

    List<int>? updated;
    final attrs = node.attrs;
    final colspan = attrs["colspan"] as int;
    final attrsColwidth = attrs["colwidth"] as List?;
    for (var j = 0; j < colspan; j++) {
      final col = (i + j) % map.width;
      final colWidth = colWidths[col * 2];
      if (colWidth != null && (attrsColwidth == null || attrsColwidth[j] != colWidth)) {
        (updated ??= _freshColWidth(attrs))[j] = colWidth;
      }
    }
    if (updated != null) {
      map.problems!.insert(0, ColwidthMismatchProblem(pos, updated));
    }
  }
}

ColWidths _freshColWidth(Attrs attrs) {
  final colwidth = attrs["colwidth"] as List?;
  if (colwidth != null) {
    return List<int>.from(colwidth);
  }
  final result = <int>[];
  final colspan = attrs["colspan"] as int;
  for (var i = 0; i < colspan; i++) {
    result.add(0);
  }
  return result;
}
