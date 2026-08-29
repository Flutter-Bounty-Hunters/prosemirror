import 'package:prosemirror/prosemirror.dart';
import 'package:test/test.dart';

void main() {
  group("OrderedMap >", () {
    group("from >", () {
      test("creates an empty map from null", () {
        final map = OrderedMap<int>.from(null);

        expect(map.size, 0);
        expect(map.toObject(), <String, int>{});
      });

      test("creates a map from a plain map, preserving insertion order", () {
        final map = OrderedMap<int>.from(<String, int>{"a": 1, "b": 2, "c": 3});

        expect(map.size, 3);
        expect(map.get("a"), 1);
        expect(map.get("b"), 2);
        expect(map.get("c"), 3);
        expect(_keysOf(map), ["a", "b", "c"]);
      });

      test("creates an empty map from an empty plain map", () {
        final map = OrderedMap<int>.from(<String, int>{});

        expect(map.size, 0);
      });

      test("returns the same instance when given an ordered map", () {
        final original = OrderedMap<int>.from(<String, int>{"a": 1, "b": 2});
        final result = OrderedMap<int>.from(original);

        expect(identical(result, original), isTrue);
      });
    });

    group("get >", () {
      test("returns the value stored under an existing key", () {
        final map = OrderedMap<int>.from(<String, int>{"a": 1, "b": 2});

        expect(map.get("a"), 1);
        expect(map.get("b"), 2);
      });

      test("returns null when the key is absent", () {
        final map = OrderedMap<int>.from(<String, int>{"a": 1});

        expect(map.get("missing"), isNull);
      });

      test("returns null for any key on an empty map", () {
        final map = OrderedMap<int>.from(null);

        expect(map.get("a"), isNull);
      });
    });

    group("size >", () {
      test("reports zero for an empty map", () {
        expect(OrderedMap<int>.from(null).size, 0);
      });

      test("reports the number of bindings", () {
        final map = OrderedMap<int>.from(<String, int>{"a": 1, "b": 2, "c": 3});

        expect(map.size, 3);
      });
    });

    group("toObject >", () {
      test("turns the ordered map into a plain map", () {
        final map = OrderedMap<int>.from(<String, int>{"a": 1, "b": 2});

        expect(map.toObject(), {"a": 1, "b": 2});
      });

      test("returns an empty plain map for an empty ordered map", () {
        expect(OrderedMap<int>.from(null).toObject(), <String, int>{});
      });
    });

    group("forEach >", () {
      test("invokes the callback for every pair in order", () {
        final map = OrderedMap<int>.from(<String, int>{"a": 1, "b": 2, "c": 3});
        final keys = <String>[];
        final values = <int>[];

        map.forEach((key, value) {
          keys.add(key);
          values.add(value);
        });

        expect(keys, ["a", "b", "c"]);
        expect(values, [1, 2, 3]);
      });

      test("does not invoke the callback for an empty map", () {
        var callCount = 0;

        OrderedMap<int>.from(null).forEach((key, value) {
          callCount += 1;
        });

        expect(callCount, 0);
      });
    });

    group("update >", () {
      test("replaces the value of an existing key in place", () {
        final map = OrderedMap<int>.from(<String, int>{"a": 1, "b": 2});
        final updated = map.update("a", 99);

        expect(updated.get("a"), 99);
        expect(_keysOf(updated), ["a", "b"]);
      });

      test("adds a new binding at the end when the key is absent", () {
        final map = OrderedMap<int>.from(<String, int>{"a": 1});
        final updated = map.update("b", 2);

        expect(updated.get("b"), 2);
        expect(_keysOf(updated), ["a", "b"]);
      });

      test("renames the key when newKey is provided", () {
        final map = OrderedMap<int>.from(<String, int>{"a": 1, "b": 2});
        final updated = map.update("a", 99, "z");

        expect(updated.get("a"), isNull);
        expect(updated.get("z"), 99);
        expect(_keysOf(updated), ["z", "b"]);
      });

      test("removes any existing binding for newKey before renaming", () {
        final map = OrderedMap<int>.from(<String, int>{"a": 1, "b": 2, "c": 3});
        final updated = map.update("a", 99, "b");

        expect(updated.get("b"), 99);
        expect(updated.get("a"), isNull);
        expect(_keysOf(updated), ["b", "c"]);
      });

      test("treats newKey equal to key as a plain in-place update", () {
        final map = OrderedMap<int>.from(<String, int>{"a": 1, "b": 2});
        final updated = map.update("a", 99, "a");

        expect(updated.get("a"), 99);
        expect(_keysOf(updated), ["a", "b"]);
      });

      test("leaves the original map unchanged", () {
        final map = OrderedMap<int>.from(<String, int>{"a": 1});
        map.update("a", 99);

        expect(map.get("a"), 1);
      });
    });

    group("remove >", () {
      test("returns a map with the given key removed", () {
        final map = OrderedMap<int>.from(<String, int>{"a": 1, "b": 2, "c": 3});
        final removed = map.remove("b");

        expect(removed.get("b"), isNull);
        expect(_keysOf(removed), ["a", "c"]);
      });

      test("returns the same instance when the key is absent", () {
        final map = OrderedMap<int>.from(<String, int>{"a": 1});
        final removed = map.remove("missing");

        expect(identical(removed, map), isTrue);
      });

      test("leaves the original map unchanged", () {
        final map = OrderedMap<int>.from(<String, int>{"a": 1, "b": 2});
        map.remove("a");

        expect(map.get("a"), 1);
        expect(map.size, 2);
      });
    });

    group("addToStart >", () {
      test("adds a new key at the start of the map", () {
        final map = OrderedMap<int>.from(<String, int>{"a": 1, "b": 2});
        final result = map.addToStart("z", 26);

        expect(_keysOf(result), ["z", "a", "b"]);
        expect(result.get("z"), 26);
      });

      test("removes an existing binding before adding it to the start", () {
        final map = OrderedMap<int>.from(<String, int>{"a": 1, "b": 2, "c": 3});
        final result = map.addToStart("b", 99);

        expect(_keysOf(result), ["b", "a", "c"]);
        expect(result.get("b"), 99);
      });

      test("leaves the original map unchanged", () {
        final map = OrderedMap<int>.from(<String, int>{"a": 1});
        map.addToStart("z", 26);

        expect(_keysOf(map), ["a"]);
      });
    });

    group("addToEnd >", () {
      test("adds a new key at the end of the map", () {
        final map = OrderedMap<int>.from(<String, int>{"a": 1, "b": 2});
        final result = map.addToEnd("z", 26);

        expect(_keysOf(result), ["a", "b", "z"]);
        expect(result.get("z"), 26);
      });

      test("removes an existing binding before adding it to the end", () {
        final map = OrderedMap<int>.from(<String, int>{"a": 1, "b": 2, "c": 3});
        final result = map.addToEnd("b", 99);

        expect(_keysOf(result), ["a", "c", "b"]);
        expect(result.get("b"), 99);
      });

      test("leaves the original map unchanged", () {
        final map = OrderedMap<int>.from(<String, int>{"a": 1});
        map.addToEnd("z", 26);

        expect(_keysOf(map), ["a"]);
      });
    });

    group("addBefore >", () {
      test("inserts the new key before the given place", () {
        final map = OrderedMap<int>.from(<String, int>{"a": 1, "b": 2, "c": 3});
        final result = map.addBefore("b", "z", 26);

        expect(_keysOf(result), ["a", "z", "b", "c"]);
        expect(result.get("z"), 26);
      });

      test("adds the new key at the end when the place is absent", () {
        final map = OrderedMap<int>.from(<String, int>{"a": 1, "b": 2});
        final result = map.addBefore("missing", "z", 26);

        expect(_keysOf(result), ["a", "b", "z"]);
        expect(result.get("z"), 26);
      });

      test("removes any existing binding for the key before inserting", () {
        final map = OrderedMap<int>.from(<String, int>{"a": 1, "b": 2, "c": 3});
        final result = map.addBefore("c", "a", 99);

        expect(_keysOf(result), ["b", "a", "c"]);
        expect(result.get("a"), 99);
      });

      test("leaves the original map unchanged", () {
        final map = OrderedMap<int>.from(<String, int>{"a": 1, "b": 2});
        map.addBefore("b", "z", 26);

        expect(_keysOf(map), ["a", "b"]);
      });
    });

    group("prepend >", () {
      test("prepends the other map before this map's remaining keys", () {
        final map = OrderedMap<int>.from(<String, int>{"a": 1, "b": 2});
        final result = map.prepend(<String, int>{"x": 10, "y": 11});

        expect(_keysOf(result), ["x", "y", "a", "b"]);
      });

      test("drops this map's keys that also appear in the other map", () {
        final map = OrderedMap<int>.from(<String, int>{"a": 1, "b": 2, "c": 3});
        final result = map.prepend(<String, int>{"b": 20});

        expect(_keysOf(result), ["b", "a", "c"]);
        expect(result.get("b"), 20);
      });

      test("returns this map when the other map is empty", () {
        final map = OrderedMap<int>.from(<String, int>{"a": 1});
        final result = map.prepend(<String, int>{});

        expect(identical(result, map), isTrue);
      });

      test("accepts another ordered map as its argument", () {
        final map = OrderedMap<int>.from(<String, int>{"a": 1});
        final other = OrderedMap<int>.from(<String, int>{"x": 10});
        final result = map.prepend(other);

        expect(_keysOf(result), ["x", "a"]);
      });

      test("leaves the original map unchanged", () {
        final map = OrderedMap<int>.from(<String, int>{"a": 1});
        map.prepend(<String, int>{"x": 10});

        expect(_keysOf(map), ["a"]);
      });
    });

    group("append >", () {
      test("appends the other map after this map's remaining keys", () {
        final map = OrderedMap<int>.from(<String, int>{"a": 1, "b": 2});
        final result = map.append(<String, int>{"x": 10, "y": 11});

        expect(_keysOf(result), ["a", "b", "x", "y"]);
      });

      test("drops this map's keys that also appear in the other map", () {
        final map = OrderedMap<int>.from(<String, int>{"a": 1, "b": 2, "c": 3});
        final result = map.append(<String, int>{"b": 20});

        expect(_keysOf(result), ["a", "c", "b"]);
        expect(result.get("b"), 20);
      });

      test("returns this map when the other map is empty", () {
        final map = OrderedMap<int>.from(<String, int>{"a": 1});
        final result = map.append(<String, int>{});

        expect(identical(result, map), isTrue);
      });

      test("accepts another ordered map as its argument", () {
        final map = OrderedMap<int>.from(<String, int>{"a": 1});
        final other = OrderedMap<int>.from(<String, int>{"x": 10});
        final result = map.append(other);

        expect(_keysOf(result), ["a", "x"]);
      });

      test("leaves the original map unchanged", () {
        final map = OrderedMap<int>.from(<String, int>{"a": 1});
        map.append(<String, int>{"x": 10});

        expect(_keysOf(map), ["a"]);
      });
    });

    group("subtract >", () {
      test("removes all keys that appear in the other map", () {
        final map = OrderedMap<int>.from(<String, int>{"a": 1, "b": 2, "c": 3});
        final result = map.subtract(<String, int>{"a": 10, "c": 30});

        expect(_keysOf(result), ["b"]);
      });

      test("returns an equivalent map when the operands do not overlap", () {
        final map = OrderedMap<int>.from(<String, int>{"a": 1, "b": 2});
        final result = map.subtract(<String, int>{"x": 10});

        expect(_keysOf(result), ["a", "b"]);
      });

      test("returns the same instance when the other map is empty", () {
        final map = OrderedMap<int>.from(<String, int>{"a": 1});
        final result = map.subtract(<String, int>{});

        expect(identical(result, map), isTrue);
      });

      test("accepts another ordered map as its argument", () {
        final map = OrderedMap<int>.from(<String, int>{"a": 1, "b": 2});
        final other = OrderedMap<int>.from(<String, int>{"a": 1});
        final result = map.subtract(other);

        expect(_keysOf(result), ["b"]);
      });

      test("leaves the original map unchanged", () {
        final map = OrderedMap<int>.from(<String, int>{"a": 1, "b": 2});
        map.subtract(<String, int>{"a": 1});

        expect(_keysOf(map), ["a", "b"]);
      });
    });

    group("persistence >", () {
      test("chained operations never mutate the original map", () {
        final original = OrderedMap<int>.from(<String, int>{"a": 1, "b": 2});

        original
            .update("a", 99)
            .remove("b")
            .addToStart("z", 26)
            .addToEnd("y", 25);

        expect(_keysOf(original), ["a", "b"]);
        expect(original.get("a"), 1);
        expect(original.get("b"), 2);
        expect(original.size, 2);
      });
    });
  });
}

List<String> _keysOf(OrderedMap<Object?> map) {
  final keys = <String>[];
  map.forEach((key, value) {
    keys.add(key);
  });
  return keys;
}
