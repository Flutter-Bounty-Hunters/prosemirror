/// Deep structural comparison used to compare node and mark attributes.
///
/// Faithful port of `comparedeep.ts`. Two values are equal when they are
/// identical, or when they are both maps (objects) or both lists (arrays)
/// whose entries compare deeply equal. Any other value is compared with `==`.
bool compareDeep(Object? a, Object? b) {
  if (identical(a, b)) {
    return true;
  }
  if (a is Map && b is Map) {
    for (final key in a.keys) {
      if (!b.containsKey(key) || !compareDeep(a[key], b[key])) {
        return false;
      }
    }
    for (final key in b.keys) {
      if (!a.containsKey(key)) {
        return false;
      }
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) {
      return false;
    }
    for (var index = 0; index < a.length; index++) {
      if (!compareDeep(a[index], b[index])) {
        return false;
      }
    }
    return true;
  }
  return a == b;
}
