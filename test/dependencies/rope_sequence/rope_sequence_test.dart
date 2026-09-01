import 'dart:math';

import 'package:prosemirror/prosemirror.dart';
import 'package:test/test.dart';

void main() {
  group("RopeSequence > append >", () {
    test("an appended rope of 10000 elements passes all checks", () {
      _check(_appendBuild(_size), _size, "appended");
    });

    test("a deque-built rope of 10000 elements passes all checks", () {
      _check(_dequeBuild(_size), _size, "dequed");
    });

    test("preserves the elements of a loosely typed list instead of dropping them", () {
      // A list whose static element type is not the rope's element type (here a
      // `List<dynamic>` rather than a `List<int>`) must still be appended in
      // full, rather than being silently discarded.
      final rope = RopeSequence.from(<int>[1, 2]).append(<dynamic>[3, 4]);

      expect(rope.length, 4);
      expect(rope.map((element, index) => element), [1, 2, 3, 4]);
    });
  });

  group("RopeSequence > slice >", () {
    test("a flat-built rope of 10000 elements passes all checks including sub-range slices", () {
      _check(_flatBuild(_size), _size, "flat");
    });
  });

  group("RopeSequence > forEach >", () {
    test("returning false from the callback aborts iteration", () {
      final small = RopeSequence.from([1, 2, 4]);
      var sum = 0;
      small.forEach((element, index) {
        if (element == 2) {
          return false;
        }
        sum += element;
        return null;
      });
      expect(sum, 1);
    });
  });

  group("RopeSequence > map >", () {
    test("maps every element to a new list", () {
      final small = RopeSequence.from([1, 2, 4]);
      final result = small.map((element, index) => element + 1);
      expect(result, equals([2, 3, 5]));
    });
  });

  group("RopeSequence > identity >", () {
    test("appending an empty rope returns the same instance", () {
      final small = RopeSequence.from([1, 2, 4]);
      final empty = RopeSequence.empty;
      expect(identical(small.append(empty), small), isTrue);
    });

    test("prepending an empty rope returns the same instance", () {
      final small = RopeSequence.from([1, 2, 4]);
      final empty = RopeSequence.empty;
      expect(identical(small.prepend(empty), small), isTrue);
    });

    test("appending empty to empty returns the shared empty instance", () {
      final empty = RopeSequence.empty;
      expect(identical(empty.append(empty), empty), isTrue);
    });

    test("slicing an empty range returns the shared empty instance", () {
      final small = RopeSequence.from([1, 2, 4]);
      final empty = RopeSequence.empty;
      expect(identical(small.slice(0, 0), empty), isTrue);
    });
  });
}

const _size = 10000;

RopeSequence<int> _appendBuild(int count) {
  RopeSequence<int> rope = RopeSequence.from(<int>[]);
  for (var index = 0; index < count; index++) {
    rope = rope.append([index]);
  }
  return rope;
}

RopeSequence<int> _dequeBuild(int count) {
  final middle = count >> 1;
  RopeSequence<int> rope = RopeSequence.from(<int>[]);
  for (var from = middle - 1, to = middle; to < count; from--, to++) {
    rope = rope.append([to]);
    if (from >= 0) {
      rope = RopeSequence.from([from]).append(rope);
    }
  }
  return rope;
}

RopeSequence<int> _flatBuild(int count) {
  final array = <int>[];
  for (var index = 0; index < count; index++) {
    array.add(index);
  }
  return RopeSequence.from(array);
}

void _check(RopeSequence<int> rope, int size, String name, [int offset = 0]) {
  expect(rope.length, size);
  for (var index = 0; index < rope.length; index++) {
    expect(rope.get(index), offset + index);
  }
  _checkForEach(rope, name, 0, rope.length, offset);

  final examples = min(10, (size / 100).floor());
  for (var example = 0; example < examples; example++) {
    final start = (_random.nextDouble() * size).floor();
    final end = start + (_random.nextDouble() * (size - start)).ceil();
    _checkForEach(rope, "$name-$start-$end", start, end, offset);
    _check(rope.slice(start, end), end - start, "$name-sliced-$start-$end", offset + start);
  }
}

void _checkForEach(RopeSequence<int> rope, String name, int start, int end, int offset) {
  var current = start;
  rope.forEach(
    (element, index) {
      expect(element, current + offset);
      expect(current, index);
      current++;
      return null;
    },
    start,
    end,
  );
  expect(current, end);

  rope.forEach(
    (element, index) {
      current--;
      expect(element, current + offset);
      expect(current, index);
      return null;
    },
    end,
    start,
  );
  expect(current, start);
}

final _random = Random(1234);
