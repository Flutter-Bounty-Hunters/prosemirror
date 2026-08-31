import 'dart:math' as math;

import 'package:prosemirror/src/model/content.dart';
import 'package:prosemirror/src/model/fragment.dart';
import 'package:prosemirror/src/model/mark.dart';
import 'package:prosemirror/src/model/replace.dart';
import 'package:prosemirror/src/model/schema.dart';

import 'package:prosemirror/src/transform/step.dart';
import 'package:prosemirror/src/transform/transform.dart';
import 'package:prosemirror/src/transform/mark_step.dart';
import 'package:prosemirror/src/transform/replace_step.dart';

void addMark(Transform tr, int from, int to, Mark mark) {
  final removed = <Step>[];
  final added = <Step>[];
  RemoveMarkStep? removing;
  AddMarkStep? adding;
  tr.doc.nodesBetween(from, to, (node, pos, parent, index) {
    if (!node.isInline) {
      return null;
    }
    final marks = node.marks;
    if (!mark.isInSet(marks) && parent!.type.allowsMarkType(mark.type)) {
      final start = math.max(pos, from);
      final end = math.min(pos + node.nodeSize, to);
      final newSet = mark.addToSet(marks);

      for (var i = 0; i < marks.length; i++) {
        if (!marks[i].isInSet(newSet)) {
          if (removing != null &&
              removing!.to == start &&
              removing!.mark.eq(marks[i])) {
            removing = RemoveMarkStep(removing!.from, end, removing!.mark);
            removed[removed.length - 1] = removing!;
          } else {
            removing = RemoveMarkStep(start, end, marks[i]);
            removed.add(removing!);
          }
        }
      }

      if (adding != null && adding!.to == start) {
        adding = AddMarkStep(adding!.from, end, mark);
        added[added.length - 1] = adding!;
      } else {
        adding = AddMarkStep(start, end, mark);
        added.add(adding!);
      }
    }
    return null;
  });

  for (final step in removed) {
    tr.step(step);
  }
  for (final step in added) {
    tr.step(step);
  }
}

class _Matched {
  _Matched({
    required this.style,
    required this.from,
    required this.to,
    required this.step,
  });

  final Mark style;
  final int from;
  int to;
  int step;
}

void removeMark(Transform tr, int from, int to, [Object? mark]) {
  final matched = <_Matched>[];
  var step = 0;
  tr.doc.nodesBetween(from, to, (node, pos, parent, index) {
    if (!node.isInline) {
      return null;
    }
    step++;
    List<Mark>? toRemove;
    if (mark is MarkType) {
      var set = node.marks;
      Mark? found;
      while ((found = mark.isInSet(set)) != null) {
        (toRemove ??= <Mark>[]).add(found!);
        set = found.removeFromSet(set);
      }
    } else if (mark is Mark) {
      if (mark.isInSet(node.marks)) {
        toRemove = [mark];
      }
    } else {
      toRemove = node.marks;
    }
    if (toRemove != null && toRemove.isNotEmpty) {
      final end = math.min(pos + node.nodeSize, to);
      for (var i = 0; i < toRemove.length; i++) {
        final style = toRemove[i];
        _Matched? found;
        for (var j = 0; j < matched.length; j++) {
          final entry = matched[j];
          if (entry.step == step - 1 && style.eq(entry.style)) {
            found = entry;
          }
        }
        if (found != null) {
          found.to = end;
          found.step = step;
        } else {
          matched.add(
            _Matched(
              style: style,
              from: math.max(pos, from),
              to: end,
              step: step,
            ),
          );
        }
      }
    }
    return null;
  });
  for (final match in matched) {
    tr.step(RemoveMarkStep(match.from, match.to, match.style));
  }
}

void clearIncompatible(
  Transform tr,
  int pos,
  NodeType parentType, [
  ContentMatch? match,
  bool clearNewlines = true,
]) {
  match ??= parentType.contentMatch;
  final node = tr.doc.nodeAt(pos)!;
  final replSteps = <Step>[];
  var current = pos + 1;
  for (var i = 0; i < node.childCount; i++) {
    final child = node.child(i);
    final end = current + child.nodeSize;
    final allowed = match!.matchType(child.type);
    if (allowed == null) {
      replSteps.add(ReplaceStep(current, end, Slice.empty));
    } else {
      match = allowed;
      for (var j = 0; j < child.marks.length; j++) {
        if (!parentType.allowsMarkType(child.marks[j].type)) {
          tr.step(RemoveMarkStep(current, end, child.marks[j]));
        }
      }

      if (clearNewlines && child.isText && parentType.whitespace != "pre") {
        final newline = RegExp(r'\r?\n|\r');
        Slice? slice;
        for (final match in newline.allMatches(child.text!)) {
          slice ??= Slice(
            Fragment.from(
              parentType.schema.text(" ", parentType.allowedMarks(child.marks)),
            ),
            0,
            0,
          );
          replSteps.add(
            ReplaceStep(
              current + match.start,
              current + match.start + match[0]!.length,
              slice,
            ),
          );
        }
      }
    }
    current = end;
  }
  if (!match!.validEnd) {
    final fill = match.fillBefore(Fragment.empty, true);
    tr.replace(current, current, Slice(fill!, 0, 0));
  }
  for (var i = replSteps.length - 1; i >= 0; i--) {
    tr.step(replSteps[i]);
  }
}
