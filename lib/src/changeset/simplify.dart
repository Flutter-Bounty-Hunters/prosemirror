import 'dart:math' as math;

import 'package:prosemirror/src/changeset/change.dart';
import 'package:prosemirror/src/model/fragment.dart';
import 'package:prosemirror/src/model/node.dart';

// If the runtime supports unicode properties in regexps, that's a good
// source of info on whether something is a letter. Dart supports unicode
// property escapes, so this is always available.
final RegExp _letter = RegExp(r"[\p{Alphabetic}_]", unicode: true);

// Otherwise, we see if the character changes when upper/lowercased,
// or if it is part of these common single-case scripts.
final RegExp _nonASCIISingleCaseWordChar = RegExp(
  "[ßև֐-״؀-ۿ぀-ゟ゠-ヿ"
  "㐀-䶵一-鿌가-힯]",
);

bool _isLetter(int code) {
  if (code < 128) {
    return code >= 48 && code <= 57 ||
        code >= 65 && code <= 90 ||
        code >= 97 && code <= 122;
  }
  final character = String.fromCharCode(code);
  if (_letter.hasMatch(character)) {
    return true;
  }
  return character.toUpperCase() != character.toLowerCase() ||
      _nonASCIISingleCaseWordChar.hasMatch(character);
}

// Convert a range of document into a string, so that we can easily
// access characters at a given position. Treat non-text tokens as
// spaces so that they aren't considered part of a word.
String _getText(Fragment fragment, int start, int end) {
  final buffer = StringBuffer();
  _convertText(fragment, start, end, buffer);
  return buffer.toString();
}

void _convertText(Fragment fragment, int start, int end, StringBuffer out) {
  var offset = 0;
  for (var index = 0; index < fragment.childCount; index++) {
    final child = fragment.child(index);
    final endOffset = offset + child.nodeSize;
    final from = math.max(offset, start);
    final to = math.min(endOffset, end);
    if (from < to) {
      if (child.isText) {
        out.write(
          child.text!.substring(
            math.max(0, start - offset),
            math.min(child.text!.length, end - offset),
          ),
        );
      } else if (child.isLeaf) {
        out.write(" ");
      } else {
        if (from == offset) {
          out.write(" ");
        }
        _convertText(
          child.content,
          math.max(0, from - offset - 1),
          math.min(child.content.size, end - offset),
          out,
        );
        if (to == endOffset) {
          out.write(" ");
        }
      }
    }
    offset = endOffset;
  }
}

// The distance changes have to be apart for us to not consider them
// candidates for merging.
const int _maxSimplifyDistance = 30;

/// Simplifies a set of changes for presentation. This makes the
/// assumption that having both insertions and deletions within a word
/// is confusing, and, when such changes occur without a word boundary
/// between them, they should be expanded to cover the entire set of
/// words (in the new document) they touch. An exception is made for
/// single-character replacements.
List<Change<Data>> simplifyChanges<Data>(List<Change<Data>> changes, Node doc) {
  final result = <Change<Data>>[];
  for (var index = 0; index < changes.length; index++) {
    var end = changes[index].toB;
    final start = index;
    while (index < changes.length - 1 &&
        changes[index + 1].fromB <= end + _maxSimplifyDistance) {
      end = changes[++index].toB;
    }
    _simplifyAdjacentChanges(changes, start, index + 1, doc, result);
  }
  return result;
}

void _simplifyAdjacentChanges<Data>(
  List<Change<Data>> changes,
  int from,
  int to,
  Node doc,
  List<Change<Data>> target,
) {
  final start = math.max(0, changes[from].fromB - _maxSimplifyDistance);
  final end = math.min(
    doc.content.size,
    changes[to - 1].toB + _maxSimplifyDistance,
  );
  final text = _getText(doc.content, start, end);

  for (var index = from; index < to; index++) {
    final startIndex = index;
    var last = changes[index];
    var deleted = last.lenA;
    var inserted = last.lenB;
    while (index < to - 1) {
      final next = changes[index + 1];
      var boundary = false;
      var prevLetter = last.toB == end
          ? false
          : _isLetter(text.codeUnitAt(last.toB - 1 - start));
      for (
        var position = last.toB;
        !boundary && position < next.fromB;
        position++
      ) {
        final nextLetter = position == end
            ? false
            : _isLetter(text.codeUnitAt(position - start));
        if ((!prevLetter || !nextLetter) &&
            position != changes[startIndex].fromB) {
          boundary = true;
        }
        prevLetter = nextLetter;
      }
      if (boundary) {
        break;
      }
      deleted += next.lenA;
      inserted += next.lenB;
      last = next;
      index++;
    }

    if (inserted > 0 && deleted > 0 && !(inserted == 1 && deleted == 1)) {
      var fromB = changes[startIndex].fromB;
      var toB = changes[index].toB;
      if (fromB < end && _isLetter(text.codeUnitAt(fromB - start))) {
        while (fromB > start && _isLetter(text.codeUnitAt(fromB - 1 - start))) {
          fromB--;
        }
      }
      if (toB > start && _isLetter(text.codeUnitAt(toB - 1 - start))) {
        while (toB < end && _isLetter(text.codeUnitAt(toB - start))) {
          toB++;
        }
      }
      final joined = _fillChange(
        changes.sublist(startIndex, index + 1),
        fromB,
        toB,
      );
      final lastTarget = target.isNotEmpty ? target[target.length - 1] : null;
      if (lastTarget != null && lastTarget.toA == joined.fromA) {
        target[target.length - 1] = Change<Data>(
          lastTarget.fromA,
          joined.toA,
          lastTarget.fromB,
          joined.toB,
          [...lastTarget.deleted, ...joined.deleted],
          [...lastTarget.inserted, ...joined.inserted],
        );
      } else {
        target.add(joined);
      }
    } else {
      for (var innerIndex = startIndex; innerIndex <= index; innerIndex++) {
        target.add(changes[innerIndex]);
      }
    }
  }
}

Data? _combine<Data>(Data a, Data b) {
  return identical(a, b) || a == b ? a : null;
}

Change<Data> _fillChange<Data>(List<Change<Data>> changes, int fromB, int toB) {
  final fromA = changes[0].fromA - (changes[0].fromB - fromB);
  final last = changes[changes.length - 1];
  final toA = last.toA + (toB - last.toB);
  var deleted = Span.none<Data>();
  var inserted = Span.none<Data>();
  var deletedData =
      (changes[0].deleted.isNotEmpty
              ? changes[0].deleted
              : changes[0].inserted)[0]
          .data;
  var insertedData =
      (changes[0].inserted.isNotEmpty
              ? changes[0].inserted
              : changes[0].deleted)[0]
          .data;
  var posA = fromA;
  var posB = fromB;
  for (var index = 0; ; index++) {
    final next = index == changes.length ? null : changes[index];
    final endA = next != null ? next.fromA : toA;
    final endB = next != null ? next.fromB : toB;
    if (endA > posA) {
      deleted = Span.join(deleted, [
        Span<Data>(endA - posA, deletedData),
      ], _combine);
    }
    if (endB > posB) {
      inserted = Span.join(inserted, [
        Span<Data>(endB - posB, insertedData),
      ], _combine);
    }
    if (next == null) {
      break;
    }
    deleted = Span.join(deleted, next.deleted, _combine);
    inserted = Span.join(inserted, next.inserted, _combine);
    if (deleted.isNotEmpty) {
      deletedData = deleted[deleted.length - 1].data;
    }
    if (inserted.isNotEmpty) {
      insertedData = inserted[inserted.length - 1].data;
    }
    posA = next.toA;
    posB = next.toB;
  }
  return Change<Data>(fromA, toA, fromB, toB, deleted, inserted);
}
