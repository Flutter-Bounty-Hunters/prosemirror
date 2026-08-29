/// Persistent (immutable) map data structure that remembers the order in
/// which its keys were inserted.
///
/// This is a Dart port of the JavaScript `orderedmap` package. Every mutating
/// operation returns a new [OrderedMap] and leaves the original untouched.
///
/// Bindings are stored in a single flat list of alternating keys and values.
/// Even indices hold [String] keys and odd indices hold the associated values.
class OrderedMap<T> {
  /// Creates an [OrderedMap] from the given [value].
  ///
  /// - If [value] is already an [OrderedMap], the same instance is returned.
  /// - If [value] is `null`, an empty map is returned.
  /// - If [value] is a [Map], its entries are copied in iteration order.
  factory OrderedMap.from(dynamic value) {
    if (value is OrderedMap<T>) {
      return value;
    }

    final content = <Object?>[];
    if (value is Map) {
      value.forEach((key, mapValue) {
        content.add(key);
        content.add(mapValue);
      });
    }

    return OrderedMap<T>._(content);
  }

  OrderedMap._(this._content);

  final List<Object?> _content;

  /// The number of bindings held by this map.
  int get size => _content.length >> 1;

  /// Returns the value stored under [key], or `null` when [key] is absent.
  T? get(String key) {
    final found = _find(key);
    if (found == -1) {
      return null;
    }
    return _content[found + 1] as T;
  }

  /// Creates a new map with the binding for [key] set to [value].
  ///
  /// When [newKey] is provided and differs from [key], any existing binding
  /// for [newKey] is first removed, and the updated binding is renamed to
  /// [newKey]. When [key] is absent, a new binding is appended at the end.
  OrderedMap<T> update(String key, T value, [String? newKey]) {
    final self = newKey != null && newKey != key ? remove(newKey) : this;
    final found = self._find(key);
    final content = List<Object?>.of(self._content);

    if (found == -1) {
      content.add(newKey ?? key);
      content.add(value);
    } else {
      content[found + 1] = value;
      if (newKey != null) {
        content[found] = newKey;
      }
    }

    return OrderedMap<T>._(content);
  }

  /// Creates a new map with the binding for [key] removed.
  ///
  /// Returns this same instance when [key] is absent.
  OrderedMap<T> remove(String key) {
    final found = _find(key);
    if (found == -1) {
      return this;
    }
    final content = List<Object?>.of(_content);
    content.removeRange(found, found + 2);
    return OrderedMap<T>._(content);
  }

  /// Creates a new map with [key] bound to [value] at the start.
  ///
  /// Any existing binding for [key] is removed first.
  OrderedMap<T> addToStart(String key, T value) {
    final content = <Object?>[key, value, ...remove(key)._content];
    return OrderedMap<T>._(content);
  }

  /// Creates a new map with [key] bound to [value] at the end.
  ///
  /// Any existing binding for [key] is removed first.
  OrderedMap<T> addToEnd(String key, T value) {
    final content = List<Object?>.of(remove(key)._content);
    content.add(key);
    content.add(value);
    return OrderedMap<T>._(content);
  }

  /// Creates a new map with [key] bound to [value] inserted before [place].
  ///
  /// Any existing binding for [key] is removed first. When [place] is absent,
  /// the new binding is appended at the end.
  OrderedMap<T> addBefore(String place, String key, T value) {
    final without = remove(key);
    final content = List<Object?>.of(without._content);
    final found = without._find(place);
    content.insertAll(found == -1 ? content.length : found, [key, value]);
    return OrderedMap<T>._(content);
  }

  /// Invokes [callback] for every binding, in order.
  void forEach(void Function(String key, T value) callback) {
    for (var index = 0; index < _content.length; index += 2) {
      callback(_content[index] as String, _content[index + 1] as T);
    }
  }

  /// Creates a new map with the bindings of [map] placed before this map's
  /// remaining bindings.
  ///
  /// Keys shared with [map] are dropped from this map, so the values from
  /// [map] win. Returns this same instance when [map] is empty.
  OrderedMap<T> prepend(dynamic map) {
    final other = OrderedMap<T>.from(map);
    if (other.size == 0) {
      return this;
    }
    final content = <Object?>[...other._content, ...subtract(other)._content];
    return OrderedMap<T>._(content);
  }

  /// Creates a new map with the bindings of [map] placed after this map's
  /// remaining bindings.
  ///
  /// Keys shared with [map] are dropped from this map, so the values from
  /// [map] win. Returns this same instance when [map] is empty.
  OrderedMap<T> append(dynamic map) {
    final other = OrderedMap<T>.from(map);
    if (other.size == 0) {
      return this;
    }
    final content = <Object?>[...subtract(other)._content, ...other._content];
    return OrderedMap<T>._(content);
  }

  /// Creates a new map with every key that appears in [map] removed.
  ///
  /// Returns this same instance when [map] shares no keys with this map.
  OrderedMap<T> subtract(dynamic map) {
    var result = this;
    final other = OrderedMap<T>.from(map);
    for (var index = 0; index < other._content.length; index += 2) {
      result = result.remove(other._content[index] as String);
    }
    return result;
  }

  /// Turns this ordered map into a plain [Map] that preserves order.
  Map<String, T> toObject() {
    final result = <String, T>{};
    forEach((key, value) {
      result[key] = value;
    });
    return result;
  }

  /// Returns the content index of [key], or `-1` when it is absent.
  int _find(String key) {
    for (var index = 0; index < _content.length; index += 2) {
      if (_content[index] == key) {
        return index;
      }
    }
    return -1;
  }
}
