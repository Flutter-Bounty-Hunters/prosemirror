import 'package:prosemirror/prosemirror.dart';
import 'package:test/test.dart';

import 'support/builders.dart';

void main() {
  group("Node > resolve >", () {
    test("should reflect the document structure", () {
      final expected = <int, List<Object?>>{
        0: [_document, 0, null, _paragraph1.node],
        1: [_document, _paragraph1, 0, null, "ab"],
        2: [_document, _paragraph1, 1, "a", "b"],
        3: [_document, _paragraph1, 2, "ab", null],
        4: [_document, 4, _paragraph1.node, _blockquote.node],
        5: [_document, _blockquote, 0, null, _paragraph2.node],
        6: [_document, _blockquote, _paragraph2, 0, null, "cd"],
        7: [_document, _blockquote, _paragraph2, 1, "c", "d"],
        8: [_document, _blockquote, _paragraph2, 2, "cd", "ef"],
        9: [_document, _blockquote, _paragraph2, 3, "e", "f"],
        10: [_document, _blockquote, _paragraph2, 4, "ef", null],
        11: [_document, _blockquote, 6, _paragraph2.node, null],
        12: [_document, 12, _blockquote.node, null],
      };

      for (var pos = 0; pos <= _testDoc.content.size; pos++) {
        final resolved = _testDoc.resolve(pos);
        final exp = expected[pos]!;
        expect(resolved.depth, exp.length - 4);

        for (var index = 0; index < exp.length - 3; index++) {
          final info = exp[index] as _NodeInfo;
          expect(resolved.node(index).eq(info.node), isTrue);
          expect(resolved.start(index), info.start);
          expect(resolved.end(index), info.end);
          if (index != 0) {
            expect(resolved.before(index), info.start - 1);
            expect(resolved.after(index), info.end + 1);
          }
        }

        expect(resolved.parentOffset, exp[exp.length - 3]);

        final before = resolved.nodeBefore;
        final expectedBefore = exp[exp.length - 2];
        if (expectedBefore is String) {
          expect(before!.textContent, expectedBefore);
        } else if (expectedBefore is Node) {
          expect(before, same(expectedBefore));
        } else {
          expect(before, isNull);
        }

        final after = resolved.nodeAfter;
        final expectedAfter = exp[exp.length - 1];
        if (expectedAfter is String) {
          expect(after!.textContent, expectedAfter);
        } else if (expectedAfter is Node) {
          expect(after, same(expectedAfter));
        } else {
          expect(after, isNull);
        }
      }
    });

    test("has a working posAtIndex method", () {
      final d = doc(
        blockquote(p("one"), blockquote(p("two ", em("three")), p("four"))),
      );
      final pThree = d.resolve(12); // Start of em("three")
      expect(pThree.posAtIndex(0), 8);
      expect(pThree.posAtIndex(1), 12);
      expect(pThree.posAtIndex(2), 17);
      expect(pThree.posAtIndex(0, 2), 7);
      expect(pThree.posAtIndex(1, 2), 18);
      expect(pThree.posAtIndex(2, 2), 24);
      expect(pThree.posAtIndex(0, 1), 1);
      expect(pThree.posAtIndex(1, 1), 6);
      expect(pThree.posAtIndex(2, 1), 25);
      expect(pThree.posAtIndex(0, 0), 0);
      expect(pThree.posAtIndex(1, 0), 26);
    });
  });
}

final Node _testDoc = doc(p("ab"), blockquote(p(em("cd"), "ef")));
final _NodeInfo _document = _NodeInfo(_testDoc, 0, 12);
final _NodeInfo _paragraph1 = _NodeInfo(_testDoc.child(0), 1, 3);
final _NodeInfo _blockquote = _NodeInfo(_testDoc.child(1), 5, 11);
final _NodeInfo _paragraph2 = _NodeInfo(_blockquote.node.child(0), 6, 10);

class _NodeInfo {
  _NodeInfo(this.node, this.start, this.end);

  final Node node;
  final int start;
  final int end;
}
