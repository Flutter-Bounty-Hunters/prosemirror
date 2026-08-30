import 'package:prosemirror/src/model/model.dart';
import 'package:prosemirror/src/transform/transform_library.dart';

import 'transaction.dart';

/// Registry of selection classes by their JSON ID, used by
/// [Selection.fromJSON] to disambiguate serialized selections.
final Map<String, Selection Function(Node doc, Map<String, Object?> json)>
_classesById = <String, Selection Function(Node, Map<String, Object?>)>{};

/// Superclass for editor selections. Every selection type should extend
/// this. Should not be instantiated directly.
abstract class Selection {
  /// Initialize a selection with the head and anchor and ranges. If no
  /// ranges are given, constructs a single range across [$anchor] and
  /// [$head].
  Selection(this.$anchor, this.$head, [List<SelectionRange>? ranges])
    : ranges =
          ranges ??
          <SelectionRange>[
            SelectionRange($anchor.min($head), $anchor.max($head)),
          ];

  /// The resolved anchor of the selection (the side that stays in place
  /// when the selection is modified).
  final ResolvedPos $anchor;

  /// The resolved head of the selection (the side that moves when the
  /// selection is modified).
  final ResolvedPos $head;

  /// The ranges covered by the selection.
  final List<SelectionRange> ranges;

  /// The selection's anchor, as an unresolved position.
  int get anchor => $anchor.pos;

  /// The selection's head.
  int get head => $head.pos;

  /// The lower bound of the selection's main range.
  int get from => $from.pos;

  /// The upper bound of the selection's main range.
  int get to => $to.pos;

  /// The resolved lower bound of the selection's main range.
  ResolvedPos get $from => ranges[0].$from;

  /// The resolved upper bound of the selection's main range.
  ResolvedPos get $to => ranges[0].$to;

  /// Indicates whether the selection contains any content.
  bool get empty {
    final ranges = this.ranges;
    for (var index = 0; index < ranges.length; index++) {
      if (ranges[index].$from.pos != ranges[index].$to.pos) {
        return false;
      }
    }
    return true;
  }

  /// Test whether the selection is the same as another selection.
  bool eq(Selection selection);

  /// Map this selection through a mappable thing. `doc` should be the new
  /// document to which we are mapping.
  Selection map(Node doc, Mappable mapping);

  /// Get the content of this selection as a slice.
  Slice content() {
    return $from.doc.slice(from, to, true);
  }

  /// Replace the selection with a slice or, if no slice is given, delete
  /// the selection. Will append to the given transaction.
  void replace(Transaction tr, [Slice? content]) {
    content ??= Slice.empty;
    // Put the new selection at the position after the inserted content.
    // When that ended in an inline node, search backwards, to get the
    // position after that node. If not, search forward.
    Node? lastNode = content.content.lastChild;
    Node? lastParent;
    for (var index = 0; index < content.openEnd; index++) {
      lastParent = lastNode;
      lastNode = lastNode!.lastChild;
    }

    final mapFrom = tr.steps.length;
    final ranges = this.ranges;
    for (var index = 0; index < ranges.length; index++) {
      final $from = ranges[index].$from;
      final $to = ranges[index].$to;
      final mapping = tr.mapping.slice(mapFrom);
      tr.replaceRange(
        mapping.map($from.pos),
        mapping.map($to.pos),
        index != 0 ? Slice.empty : content,
      );
      if (index == 0) {
        _selectionToInsertionEnd(
          tr,
          mapFrom,
          (lastNode != null
                  ? lastNode.isInline
                  : lastParent != null && lastParent.isTextblock)
              ? -1
              : 1,
        );
      }
    }
  }

  /// Replace the selection with the given node, appending the changes to
  /// the given transaction.
  void replaceWith(Transaction tr, Node node) {
    final mapFrom = tr.steps.length;
    final ranges = this.ranges;
    for (var index = 0; index < ranges.length; index++) {
      final $from = ranges[index].$from;
      final $to = ranges[index].$to;
      final mapping = tr.mapping.slice(mapFrom);
      final from = mapping.map($from.pos);
      final to = mapping.map($to.pos);
      if (index != 0) {
        tr.deleteRange(from, to);
      } else {
        tr.replaceRangeWith(from, to, node);
        _selectionToInsertionEnd(tr, mapFrom, node.isInline ? -1 : 1);
      }
    }
  }

  /// Convert the selection to a JSON representation. When implementing
  /// this for a custom selection class, make sure to give the object a
  /// `type` property whose value matches the ID under which you
  /// registered your class.
  Object? toJSON();

  /// Find a valid cursor or leaf node selection starting at the given
  /// position and searching back if `dir` is negative, and forward if
  /// positive. When `textOnly` is true, only consider cursor selections.
  /// Will return null when no valid selection position is found.
  static Selection? findFrom(
    ResolvedPos $pos,
    int dir, [
    bool textOnly = false,
  ]) {
    final inner = $pos.parent.inlineContent
        ? TextSelection($pos)
        : _findSelectionIn(
            $pos.node(0),
            $pos.parent,
            $pos.pos,
            $pos.index(),
            dir,
            textOnly,
          );
    if (inner != null) {
      return inner;
    }

    for (var depth = $pos.depth - 1; depth >= 0; depth--) {
      final found = dir < 0
          ? _findSelectionIn(
              $pos.node(0),
              $pos.node(depth),
              $pos.before(depth + 1),
              $pos.index(depth),
              dir,
              textOnly,
            )
          : _findSelectionIn(
              $pos.node(0),
              $pos.node(depth),
              $pos.after(depth + 1),
              $pos.index(depth) + 1,
              dir,
              textOnly,
            );
      if (found != null) {
        return found;
      }
    }
    return null;
  }

  /// Find a valid cursor or leaf node selection near the given position.
  /// Searches forward first by default, but if `bias` is negative, it
  /// will search backwards first.
  static Selection near(ResolvedPos $pos, [int bias = 1]) {
    return findFrom($pos, bias) ??
        findFrom($pos, -bias) ??
        AllSelection($pos.node(0));
  }

  /// Find the cursor or leaf node selection closest to the start of the
  /// given document. Will return an [AllSelection] if no valid position
  /// exists.
  static Selection atStart(Node doc) {
    return _findSelectionIn(doc, doc, 0, 0, 1) ?? AllSelection(doc);
  }

  /// Find the cursor or leaf node selection closest to the end of the
  /// given document.
  static Selection atEnd(Node doc) {
    return _findSelectionIn(doc, doc, doc.content.size, doc.childCount, -1) ??
        AllSelection(doc);
  }

  /// Deserialize the JSON representation of a selection. Must be
  /// implemented for custom classes (as a static class method).
  static Selection fromJSON(Node doc, Map<String, Object?> json) {
    _ensureBuiltInSelectionsRegistered();
    if (json.isEmpty || json["type"] == null) {
      throw RangeError("Invalid input for Selection.fromJSON");
    }
    final cls = _classesById[json["type"]];
    if (cls == null) {
      throw RangeError("No selection type ${json["type"]} defined");
    }
    return cls(doc, json);
  }

  /// To be able to deserialize selections from JSON, custom selection
  /// classes must register themselves with an ID string, so that they can
  /// be disambiguated.
  static void jsonID(
    String id,
    Selection Function(Node doc, Map<String, Object?> json) fromJSON,
  ) {
    if (_classesById.containsKey(id)) {
      throw RangeError("Duplicate use of selection JSON ID $id");
    }
    _classesById[id] = fromJSON;
  }

  /// Get a bookmark for this selection, which is a value that can be
  /// mapped without having access to a current document, and later
  /// resolved to a real selection for a given document again.
  SelectionBookmark getBookmark() {
    return TextSelection.between($anchor, $head).getBookmark();
  }

  /// Controls whether, when a selection of this type is active in the
  /// browser, the selected range should be visible to the user. Defaults
  /// to `true`.
  bool get visible => true;
}

/// A lightweight, document-independent representation of a selection. You
/// can define a custom bookmark type for a custom selection class to make
/// the history handle it well.
abstract class SelectionBookmark {
  /// Map the bookmark through a set of changes.
  SelectionBookmark map(Mappable mapping);

  /// Resolve the bookmark to a real selection again.
  Selection resolve(Node doc);
}

/// Represents a selected range in a document.
class SelectionRange {
  /// Create a range.
  SelectionRange(this.$from, this.$to);

  /// The lower bound of the range.
  final ResolvedPos $from;

  /// The upper bound of the range.
  final ResolvedPos $to;
}

bool _warnedAboutTextSelection = false;
void _checkTextSelection(ResolvedPos $pos) {
  if (!_warnedAboutTextSelection && !$pos.parent.inlineContent) {
    _warnedAboutTextSelection = true;
    // ignore: avoid_print
    print(
      "TextSelection endpoint not pointing into a node with inline content (${$pos.parent.type.name})",
    );
  }
}

/// A text selection represents a classical editor selection, with a head
/// (the moving side) and anchor (immobile side), both of which point into
/// textblock nodes. It can be empty (a regular cursor position).
class TextSelection extends Selection {
  /// Construct a text selection between the given points.
  TextSelection(ResolvedPos $anchor, [ResolvedPos? $head])
    : super($anchor, _checkedHead($anchor, $head));

  static ResolvedPos _checkedHead(ResolvedPos $anchor, ResolvedPos? $head) {
    final resolvedHead = $head ?? $anchor;
    _checkTextSelection($anchor);
    _checkTextSelection(resolvedHead);
    return resolvedHead;
  }

  /// Returns a resolved position if this is a cursor selection (an empty
  /// text selection), and null otherwise.
  ResolvedPos? get $cursor => $anchor.pos == $head.pos ? $head : null;

  @override
  Selection map(Node doc, Mappable mapping) {
    final $head = doc.resolve(mapping.map(head));
    if (!$head.parent.inlineContent) {
      return Selection.near($head);
    }
    final $anchor = doc.resolve(mapping.map(anchor));
    return TextSelection($anchor.parent.inlineContent ? $anchor : $head, $head);
  }

  @override
  void replace(Transaction tr, [Slice? content]) {
    content ??= Slice.empty;
    super.replace(tr, content);
    if (identical(content, Slice.empty)) {
      final marks = $from.marksAcross($to);
      if (marks != null) {
        tr.ensureMarks(marks);
      }
    }
  }

  @override
  bool eq(Selection other) {
    return other is TextSelection &&
        other.anchor == anchor &&
        other.head == head;
  }

  @override
  SelectionBookmark getBookmark() {
    return _TextBookmark(anchor, head);
  }

  @override
  Object toJSON() {
    return <String, Object?>{"type": "text", "anchor": anchor, "head": head};
  }

  /// @internal
  static TextSelection fromJSON(Node doc, Map<String, Object?> json) {
    if (json["anchor"] is! int || json["head"] is! int) {
      throw RangeError("Invalid input for TextSelection.fromJSON");
    }
    return TextSelection(
      doc.resolve(json["anchor"] as int),
      doc.resolve(json["head"] as int),
    );
  }

  /// Create a text selection from non-resolved positions.
  static TextSelection create(Node doc, int anchor, [int? head]) {
    final resolvedHead = head ?? anchor;
    final $anchor = doc.resolve(anchor);
    return TextSelection(
      $anchor,
      resolvedHead == anchor ? $anchor : doc.resolve(resolvedHead),
    );
  }

  /// Return a text selection that spans the given positions or, if they
  /// aren't text positions, find a text selection near them. `bias`
  /// determines whether the method searches forward (default) or
  /// backwards (negative number) first.
  static Selection between(
    ResolvedPos $anchor,
    ResolvedPos $head, [
    int? bias,
  ]) {
    final dPos = $anchor.pos - $head.pos;
    var resolvedBias = bias;
    if (resolvedBias == null || resolvedBias == 0 || dPos != 0) {
      resolvedBias = dPos >= 0 ? 1 : -1;
    }
    if (!$head.parent.inlineContent) {
      final found =
          Selection.findFrom($head, resolvedBias, true) ??
          Selection.findFrom($head, -resolvedBias, true);
      if (found != null) {
        $head = found.$head;
      } else {
        return Selection.near($head, resolvedBias);
      }
    }
    if (!$anchor.parent.inlineContent) {
      if (dPos == 0) {
        $anchor = $head;
      } else {
        $anchor =
            (Selection.findFrom($anchor, -resolvedBias, true) ??
                    Selection.findFrom($anchor, resolvedBias, true))!
                .$anchor;
        if (($anchor.pos < $head.pos) != (dPos < 0)) {
          $anchor = $head;
        }
      }
    }
    return TextSelection($anchor, $head);
  }
}

class _TextBookmark implements SelectionBookmark {
  _TextBookmark(this.anchor, this.head);

  final int anchor;
  final int head;

  @override
  SelectionBookmark map(Mappable mapping) {
    return _TextBookmark(mapping.map(anchor), mapping.map(head));
  }

  @override
  Selection resolve(Node doc) {
    return TextSelection.between(doc.resolve(anchor), doc.resolve(head));
  }
}

/// A node selection is a selection that points at a single node. All nodes
/// marked selectable can be the target of a node selection. In such a
/// selection, `from` and `to` point directly before and after the selected
/// node, `anchor` equals `from`, and `head` equals `to`.
class NodeSelection extends Selection {
  /// Create a node selection. Does not verify the validity of its
  /// argument.
  NodeSelection(ResolvedPos $pos)
    : node = $pos.nodeAfter!,
      super($pos, $pos.node(0).resolve($pos.pos + $pos.nodeAfter!.nodeSize));

  /// The selected node.
  final Node node;

  @override
  Selection map(Node doc, Mappable mapping) {
    final result = mapping.mapResult(anchor);
    final $pos = doc.resolve(result.pos);
    if (result.deleted) {
      return Selection.near($pos);
    }
    return NodeSelection($pos);
  }

  @override
  Slice content() {
    return Slice(Fragment.from(node), 0, 0);
  }

  @override
  bool eq(Selection other) {
    return other is NodeSelection && other.anchor == anchor;
  }

  @override
  Object toJSON() {
    return <String, Object?>{"type": "node", "anchor": anchor};
  }

  @override
  SelectionBookmark getBookmark() => _NodeBookmark(anchor);

  /// @internal
  static NodeSelection fromJSON(Node doc, Map<String, Object?> json) {
    if (json["anchor"] is! int) {
      throw RangeError("Invalid input for NodeSelection.fromJSON");
    }
    return NodeSelection(doc.resolve(json["anchor"] as int));
  }

  /// Create a node selection from non-resolved positions.
  static NodeSelection create(Node doc, int from) {
    return NodeSelection(doc.resolve(from));
  }

  /// Determines whether the given node may be selected as a node
  /// selection.
  static bool isSelectable(Node node) {
    return !node.isText && node.type.spec.selectable != false;
  }

  @override
  bool get visible => false;
}

class _NodeBookmark implements SelectionBookmark {
  _NodeBookmark(this.anchor);

  final int anchor;

  @override
  SelectionBookmark map(Mappable mapping) {
    final result = mapping.mapResult(anchor);
    return result.deleted
        ? _TextBookmark(result.pos, result.pos)
        : _NodeBookmark(result.pos);
  }

  @override
  Selection resolve(Node doc) {
    final $pos = doc.resolve(anchor);
    final node = $pos.nodeAfter;
    if (node != null && NodeSelection.isSelectable(node)) {
      return NodeSelection($pos);
    }
    return Selection.near($pos);
  }
}

/// A selection type that represents selecting the whole document (which
/// can not necessarily be expressed with a text selection, when there are
/// for example leaf block nodes at the start or end of the document).
class AllSelection extends Selection {
  /// Create an all-selection over the given document.
  AllSelection(Node doc) : super(doc.resolve(0), doc.resolve(doc.content.size));

  @override
  void replace(Transaction tr, [Slice? content]) {
    content ??= Slice.empty;
    if (identical(content, Slice.empty)) {
      tr.delete(0, tr.doc.content.size);
      final selection = Selection.atStart(tr.doc);
      if (!selection.eq(tr.selection)) {
        tr.setSelection(selection);
      }
    } else {
      super.replace(tr, content);
    }
  }

  @override
  Object toJSON() => <String, Object?>{"type": "all"};

  /// @internal
  static AllSelection fromJSON(Node doc, Map<String, Object?> json) =>
      AllSelection(doc);

  @override
  Selection map(Node doc, Mappable mapping) => AllSelection(doc);

  @override
  bool eq(Selection other) => other is AllSelection;

  @override
  SelectionBookmark getBookmark() => _allBookmark;
}

class _AllBookmark implements SelectionBookmark {
  const _AllBookmark();

  @override
  SelectionBookmark map(Mappable mapping) => this;

  @override
  Selection resolve(Node doc) => AllSelection(doc);
}

const _AllBookmark _allBookmark = _AllBookmark();

bool _selectionsRegistered = false;
void _ensureBuiltInSelectionsRegistered() {
  if (_selectionsRegistered) {
    return;
  }
  _selectionsRegistered = true;
  Selection.jsonID("text", TextSelection.fromJSON);
  Selection.jsonID("node", NodeSelection.fromJSON);
  Selection.jsonID("all", AllSelection.fromJSON);
}

// FIXME we'll need some awareness of text direction when scanning for
// selections.

// Try to find a selection inside the given node. `pos` points at the
// position where the search starts. When `text` is true, only return text
// selections.
Selection? _findSelectionIn(
  Node doc,
  Node node,
  int pos,
  int index,
  int dir, [
  bool text = false,
]) {
  if (node.inlineContent) {
    return TextSelection.create(doc, pos);
  }
  for (
    var currentIndex = index - (dir > 0 ? 0 : 1);
    dir > 0 ? currentIndex < node.childCount : currentIndex >= 0;
    currentIndex += dir
  ) {
    final child = node.child(currentIndex);
    if (!child.isAtom) {
      final inner = _findSelectionIn(
        doc,
        child,
        pos + dir,
        dir < 0 ? child.childCount : 0,
        dir,
        text,
      );
      if (inner != null) {
        return inner;
      }
    } else if (!text && NodeSelection.isSelectable(child)) {
      return NodeSelection.create(doc, pos - (dir < 0 ? child.nodeSize : 0));
    }
    pos += child.nodeSize * dir;
  }
  return null;
}

void _selectionToInsertionEnd(Transaction tr, int startLen, int bias) {
  final last = tr.steps.length - 1;
  if (last < startLen) {
    return;
  }
  final step = tr.steps[last];
  if (!(step is ReplaceStep || step is ReplaceAroundStep)) {
    return;
  }
  final map = tr.mapping.maps[last];
  int? end;
  map.forEach((fromA, toA, newFrom, newTo) {
    end ??= newTo;
  });
  tr.setSelection(Selection.near(tr.doc.resolve(end!), bias));
}
