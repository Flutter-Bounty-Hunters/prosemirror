import 'package:prosemirror/src/model/compare_deep.dart';
import 'package:prosemirror/src/model/schema.dart';

/// A mark is a piece of information that can be attached to a node, such as it
/// being emphasized, in code font, or a link. It has a type and optionally a
/// set of attributes that provide further information (such as the target of
/// the link). Marks are created through a [Schema], which controls which types
/// exist and which attributes they have.
class Mark {
  /// @internal
  Mark(this.type, this.attrs);

  /// The type of this mark.
  final MarkType type;

  /// The attributes associated with this mark.
  final Attrs attrs;

  /// Given a set of marks, create a new set which contains this one as well,
  /// in the right position. If this mark is already in the set, the set itself
  /// is returned. If any marks that are set to be exclusive with this mark are
  /// present, those are replaced by this one.
  List<Mark> addToSet(List<Mark> set) {
    List<Mark>? copy;
    var placed = false;
    for (var index = 0; index < set.length; index++) {
      final other = set[index];
      if (eq(other)) {
        return set;
      }
      if (type.excludes(other.type)) {
        copy ??= set.sublist(0, index);
      } else if (other.type.excludes(type)) {
        return set;
      } else {
        if (!placed && other.type.rank > type.rank) {
          copy ??= set.sublist(0, index);
          copy.add(this);
          placed = true;
        }
        if (copy != null) {
          copy.add(other);
        }
      }
    }
    copy ??= set.sublist(0);
    if (!placed) {
      copy.add(this);
    }
    return copy;
  }

  /// Remove this mark from the given set, returning a new set. If this mark is
  /// not in the set, the set itself is returned.
  List<Mark> removeFromSet(List<Mark> set) {
    for (var index = 0; index < set.length; index++) {
      if (eq(set[index])) {
        return [...set.sublist(0, index), ...set.sublist(index + 1)];
      }
    }
    return set;
  }

  /// Test whether this mark is in the given set of marks.
  bool isInSet(List<Mark> set) {
    for (var index = 0; index < set.length; index++) {
      if (eq(set[index])) {
        return true;
      }
    }
    return false;
  }

  /// Test whether this mark has the same type and attributes as another mark.
  bool eq(Mark other) {
    return identical(this, other) || (identical(type, other.type) && compareDeep(attrs, other.attrs));
  }

  /// Convert this mark to a JSON-serializeable representation.
  Object? toJSON() {
    final result = <String, Object?>{"type": type.name};
    if (attrs.isNotEmpty) {
      result["attrs"] = attrs;
    }
    return result;
  }

  /// Deserialize a mark from JSON.
  static Mark fromJSON(Schema schema, Object? json) {
    if (json == null) {
      throw RangeError("Invalid input for Mark.fromJSON");
    }
    final map = json as Map<String, Object?>;
    final type = schema.marks[map["type"]];
    if (type == null) {
      throw RangeError("There is no mark type ${map["type"]} in this schema");
    }
    final mark = type.create(map["attrs"] as Attrs?);
    type.checkAttrs(mark.attrs);
    return mark;
  }

  /// Test whether two sets of marks are identical.
  static bool sameSet(List<Mark> a, List<Mark> b) {
    if (identical(a, b)) {
      return true;
    }
    if (a.length != b.length) {
      return false;
    }
    for (var index = 0; index < a.length; index++) {
      if (!a[index].eq(b[index])) {
        return false;
      }
    }
    return true;
  }

  /// Create a properly sorted mark set from null, a single mark, or an
  /// unsorted list of marks.
  static List<Mark> setFrom(Object? marks) {
    if (marks == null || (marks is List && marks.isEmpty)) {
      return none;
    }
    if (marks is Mark) {
      return [marks];
    }
    final copy = List<Mark>.of(marks as List<Mark>);
    copy.sort((a, b) => a.type.rank - b.type.rank);
    return copy;
  }

  /// The empty set of marks.
  static const List<Mark> none = <Mark>[];
}
