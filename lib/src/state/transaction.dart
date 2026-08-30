import 'package:prosemirror/src/model/model.dart';
import 'package:prosemirror/src/transform/transform_library.dart';

import 'package:prosemirror/src/state/plugin.dart';
import 'package:prosemirror/src/state/selection.dart';
import 'package:prosemirror/src/state/state.dart';

/// Commands are functions that take a state and an optional transaction
/// dispatch function and:
///
///  - determine whether they apply to this state
///  - if not, return false
///  - if `dispatch` was passed, perform their effect, possibly by passing a
///    transaction to `dispatch`
///  - return true
///
/// In some cases, the editor view is passed as a third argument.
typedef Command = bool Function(
  EditorState state, [
  void Function(Transaction tr)? dispatch,
  Object? view,
]);

const int _updatedSel = 1;
const int _updatedMarks = 2;
const int _updatedScroll = 4;

/// An editor state transaction, which can be applied to a state to create
/// an updated state. Use [EditorState.tr] to create an instance.
///
/// Transactions track changes to the document (they are a subclass of
/// [Transform]), but also other state changes, like selection updates and
/// adjustments of the set of stored marks. In addition, you can store
/// metadata properties in a transaction.
class Transaction extends Transform {
  /// @internal
  Transaction(EditorState state)
    : time = DateTime.now().millisecondsSinceEpoch,
      _curSelection = state.selection,
      storedMarks = state.storedMarks,
      super(state.doc);

  /// The timestamp associated with this transaction, in the same format as
  /// `Date.now()`.
  int time;

  Selection _curSelection;

  // The step count for which the current selection is valid.
  int _curSelectionFor = 0;

  // Bitfield to track which aspects of the state were updated by this
  // transaction.
  int _updated = 0;

  // Object used to store metadata properties for the transaction.
  final Map<String, Object?> _meta = <String, Object?>{};

  /// The stored marks set by this transaction, if any.
  List<Mark>? storedMarks;

  /// The transaction's current selection. This defaults to the editor
  /// selection mapped through the steps in the transaction, but can be
  /// overwritten with [setSelection].
  Selection get selection {
    if (_curSelectionFor < steps.length) {
      _curSelection = _curSelection.map(doc, mapping.slice(_curSelectionFor));
      _curSelectionFor = steps.length;
    }
    return _curSelection;
  }

  /// Update the transaction's current selection. Will determine the
  /// selection that the editor gets when the transaction is applied.
  Transaction setSelection(Selection selection) {
    if (selection.$from.doc != doc) {
      throw RangeError(
        "Selection passed to setSelection must point at the current document",
      );
    }
    _curSelection = selection;
    _curSelectionFor = steps.length;
    _updated = (_updated | _updatedSel) & ~_updatedMarks;
    storedMarks = null;
    return this;
  }

  /// Whether the selection was explicitly updated by this transaction.
  bool get selectionSet => (_updated & _updatedSel) > 0;

  /// Set the current stored marks.
  Transaction setStoredMarks(List<Mark>? marks) {
    storedMarks = marks;
    _updated |= _updatedMarks;
    return this;
  }

  /// Make sure the current stored marks or, if that is null, the marks at
  /// the selection, match the given set of marks. Does nothing if this is
  /// already the case.
  Transaction ensureMarks(List<Mark> marks) {
    if (!Mark.sameSet(storedMarks ?? selection.$from.marks(), marks)) {
      setStoredMarks(marks);
    }
    return this;
  }

  /// Add a mark to the set of stored marks.
  Transaction addStoredMark(Mark mark) {
    return ensureMarks(mark.addToSet(storedMarks ?? selection.$head.marks()));
  }

  /// Remove a mark or mark type from the set of stored marks.
  Transaction removeStoredMark(Object mark) {
    final currentMarks = storedMarks ?? selection.$head.marks();
    final List<Mark> result = mark is Mark
        ? mark.removeFromSet(currentMarks)
        : (mark as MarkType).removeFromSet(currentMarks);
    return ensureMarks(result);
  }

  /// Whether the stored marks were explicitly set for this transaction.
  bool get storedMarksSet => (_updated & _updatedMarks) > 0;

  /// @internal
  @override
  void addStep(Step step, Node doc) {
    super.addStep(step, doc);
    _updated = _updated & ~_updatedMarks;
    storedMarks = null;
  }

  /// Update the timestamp for the transaction.
  Transaction setTime(int time) {
    this.time = time;
    return this;
  }

  /// Replace the current selection with the given slice.
  Transaction replaceSelection(Slice slice) {
    selection.replace(this, slice);
    return this;
  }

  /// Replace the selection with the given node. When `inheritMarks` is
  /// true and the content is inline, it inherits the marks from the place
  /// where it is inserted.
  Transaction replaceSelectionWith(Node node, [bool inheritMarks = true]) {
    final selection = this.selection;
    var resultNode = node;
    if (inheritMarks) {
      resultNode = node.mark(
        storedMarks ??
            (selection.empty
                ? selection.$from.marks()
                : (selection.$from.marksAcross(selection.$to) ?? Mark.none)),
      );
    }
    selection.replaceWith(this, resultNode);
    return this;
  }

  /// Delete the selection.
  Transaction deleteSelection() {
    selection.replace(this);
    return this;
  }

  /// Replace the given range, or the selection if no range is given, with a
  /// text node containing the given string.
  Transaction insertText(String text, [int? from, int? to]) {
    final schema = doc.type.schema;
    if (from == null) {
      if (text.isEmpty) {
        return deleteSelection();
      }
      return replaceSelectionWith(schema.text(text), true);
    } else {
      to ??= from;
      if (text.isEmpty) {
        return deleteRange(from, to);
      }
      var marks = storedMarks;
      if (marks == null) {
        final $from = doc.resolve(from);
        marks = to == from ? $from.marks() : $from.marksAcross(doc.resolve(to));
      }
      replaceRangeWith(from, to, schema.text(text, marks));
      if (!selection.empty && selection.to == from + text.length) {
        setSelection(Selection.near(selection.$to));
      }
      return this;
    }
  }

  /// Store a metadata property in this transaction, keyed either by name or
  /// by plugin.
  Transaction setMeta(Object key, Object? value) {
    _meta[_metaKey(key)] = value;
    return this;
  }

  /// Retrieve a metadata property for a given name or plugin.
  Object? getMeta(Object key) {
    return _meta[_metaKey(key)];
  }

  static String _metaKey(Object key) {
    if (key is String) {
      return key;
    }
    if (key is Plugin) {
      return key.key;
    }
    if (key is PluginKey) {
      return key.key;
    }
    throw ArgumentError("Invalid meta key: $key");
  }

  /// Returns true if this transaction doesn't contain any metadata, and can
  /// thus safely be extended.
  bool get isGeneric => _meta.isEmpty;

  /// Indicate that the editor should scroll the selection into view when
  /// updated to the state produced by this transaction.
  Transaction scrollIntoView() {
    _updated |= _updatedScroll;
    return this;
  }

  /// True when this transaction has had [scrollIntoView] called on it.
  bool get scrolledIntoView => (_updated & _updatedScroll) > 0;

  @override
  Transaction deleteRange(int from, int to) {
    super.deleteRange(from, to);
    return this;
  }
}
