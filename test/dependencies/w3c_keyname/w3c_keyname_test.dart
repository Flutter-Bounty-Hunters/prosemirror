import 'package:prosemirror/prosemirror.dart';
import 'package:test/test.dart';

void main() {
  group("w3c-keyname > base map >", () {
    test("maps 53 to \"5\"", () {
      expect(base[53], "5");
    });

    test("maps 83 to \"s\"", () {
      expect(base[83], "s");
    });

    test("maps 13 to \"Enter\"", () {
      expect(base[13], "Enter");
    });

    test("maps 112 to \"F1\"", () {
      expect(base[112], "F1");
    });

    test("maps 65 to \"a\"", () {
      expect(base[65], "a");
    });
  });

  group("w3c-keyname > keyName >", () {
    test("returns the key when it is present", () {
      expect(keyName(_KeyEvent(key: "a")), "a");
    });

    test("passes named keys through unchanged", () {
      expect(keyName(_KeyEvent(key: "Enter")), "Enter");
    });

    test("falls back to the base map when the key is null", () {
      expect(keyName(_KeyEvent(keyCode: 83)), "s");
    });

    test("uses the shift map when shift is held and the key is null", () {
      expect(keyName(_KeyEvent(keyCode: 83, shiftKey: true)), "S");
    });

    test("fixes up the Edge \"Esc\" name to \"Escape\"", () {
      expect(keyName(_KeyEvent(key: "Esc")), "Escape");
    });

    test("fixes up the Edge \"Left\" name to \"ArrowLeft\"", () {
      expect(keyName(_KeyEvent(key: "Left")), "ArrowLeft");
    });
  });
}

class _KeyEvent implements KeyEvent {
  _KeyEvent({this.key, this.keyCode, this.shiftKey = false});

  @override
  final String? key;

  @override
  final int? keyCode;

  @override
  final bool shiftKey;

  @override
  final bool ctrlKey = false;

  @override
  final bool altKey = false;

  @override
  final bool metaKey = false;
}
