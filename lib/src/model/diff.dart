import 'package:prosemirror/src/model/fragment.dart';

/// Find the first position at which fragments [a] and [b] differ, or `null`
/// if they are the same. Faithful port of `diff.ts`.
int? findDiffStart(Fragment a, Fragment b, int pos) {
  for (var index = 0; ; index++) {
    if (index == a.childCount || index == b.childCount) {
      return a.childCount == b.childCount ? null : pos;
    }

    final childA = a.child(index);
    final childB = b.child(index);
    if (identical(childA, childB)) {
      pos += childA.nodeSize;
      continue;
    }

    if (!childA.sameMarkup(childB)) {
      return pos;
    }

    if (childA.isText && childA.text != childB.text) {
      final textA = childA.text!;
      final textB = childB.text!;
      var offset = 0;
      while (offset < textA.length && offset < textB.length && textA[offset] == textB[offset]) {
        offset++;
        pos++;
      }
      return pos;
    }
    if (childA.content.size != 0 || childB.content.size != 0) {
      final inner = findDiffStart(childA.content, childB.content, pos + 1);
      if (inner != null) {
        return inner;
      }
    }
    pos += childA.nodeSize;
  }
}

/// Find the first position, searching from the end, at which fragments [a] and
/// [b] differ. Returns two separate positions (one for each fragment), or
/// `null` when they are the same. Faithful port of `diff.ts`.
({int a, int b})? findDiffEnd(Fragment a, Fragment b, int posA, int posB) {
  var indexA = a.childCount;
  var indexB = b.childCount;
  for (;;) {
    if (indexA == 0 || indexB == 0) {
      return indexA == indexB ? null : (a: posA, b: posB);
    }

    final childA = a.child(--indexA);
    final childB = b.child(--indexB);
    final size = childA.nodeSize;
    if (identical(childA, childB)) {
      posA -= size;
      posB -= size;
      continue;
    }

    if (!childA.sameMarkup(childB)) {
      return (a: posA, b: posB);
    }

    if (childA.isText && childA.text != childB.text) {
      final textA = childA.text!;
      final textB = childB.text!;
      var same = 0;
      final minSize = textA.length < textB.length ? textA.length : textB.length;
      while (same < minSize && textA[textA.length - same - 1] == textB[textB.length - same - 1]) {
        same++;
        posA--;
        posB--;
      }
      return (a: posA, b: posB);
    }
    if (childA.content.size != 0 || childB.content.size != 0) {
      final inner = findDiffEnd(childA.content, childB.content, posA - 1, posB - 1);
      if (inner != null) {
        return inner;
      }
    }
    posA -= size;
    posB -= size;
  }
}
