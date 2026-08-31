import 'package:prosemirror/prosemirror.dart';
import 'package:test/test.dart';

import '../model/support/builders.dart';

void main() {
  group("keymap >", () {
    test("calls the correct handler", () {
      final a = _Counter();
      final b = _Counter();
      final view = _FakeView();
      final handler = keydownHandler({"KeyA": a, "KeyB": b});
      handler(view, _FakeKeyEvent(key: "KeyA"));
      expect(a.count, 1);
      expect(b.count, 0);
    });

    test("distinguishes between modifiers", () {
      final space = _Counter();
      final controlSpace = _Counter();
      final shiftControlSpace = _Counter();
      final altSpace = _Counter();
      final view = _FakeView();
      final handler = keydownHandler({
        "Space": space,
        "Control-Space": controlSpace,
        "s-c-Space": shiftControlSpace,
        "alt-Space": altSpace,
      });
      handler(view, _FakeKeyEvent(key: " ", ctrlKey: true));
      handler(view, _FakeKeyEvent(key: " ", ctrlKey: true, shiftKey: true));
      expect(space.count, 0);
      expect(controlSpace.count, 1);
      expect(shiftControlSpace.count, 1);
      expect(altSpace.count, 0);
    });

    test("passes the state, dispatch, and view", () {
      final view = _FakeView();
      final command = FunctionCommand((state, [dispatch, commandView]) {
        expect(identical(state, view.state), isTrue);
        expect(identical(dispatch, view.dispatch), isTrue);
        expect(identical(commandView, view), isTrue);
        return true;
      });
      final handler = keydownHandler({"X": command});
      handler(view, _FakeKeyEvent(key: "X"));
    });

    test("tries both shifted key and base with shift modifier", () {
      final percent = _Counter();
      final view = _FakeView();
      final percentHandler = keydownHandler({"Ctrl-%": percent});
      percentHandler(
        view,
        _FakeKeyEvent(key: "%", shiftKey: true, ctrlKey: true, keyCode: 53),
      );
      expect(percent.count, 1);

      final shift5 = _Counter();
      final shift5Handler = keydownHandler({"Ctrl-Shift-5": shift5});
      shift5Handler(
        view,
        _FakeKeyEvent(key: "%", shiftKey: true, ctrlKey: true, keyCode: 53),
      );
      expect(shift5.count, 1);
    });

    test("tries keyCode when modifier active", () {
      final count = _Counter();
      final view = _FakeView();
      final handler = keydownHandler({"Shift-Alt-3": count});
      handler(
        view,
        _FakeKeyEvent(key: "×", shiftKey: true, altKey: true, keyCode: 51),
      );
      expect(count.count, 1);
    });

    test("tries keyCode for non-ASCII characters", () {
      final count = _Counter();
      final view = _FakeView();
      final handler = keydownHandler({"Mod-s": count});
      // "Mod" normalizes to Meta on macOS and Ctrl elsewhere. Send whichever
      // modifier "Mod" actually resolves to on this platform so the test is
      // deterministic everywhere.
      handler(
        view,
        _FakeKeyEvent(
          key: "ы",
          keyCode: 83,
          metaKey: isMacPlatform,
          ctrlKey: !isMacPlatform,
        ),
      );
      expect(count.count, 1);
    });
  });
}

class _FakeView implements KeymapView {
  @override
  final EditorState state = EditorState.create(
    EditorStateConfig(schema: schema),
  );

  @override
  final void Function(Transaction) dispatch = _noopDispatch;
}

void _noopDispatch(Transaction transaction) {}

class _FakeKeyEvent implements KeyEvent {
  _FakeKeyEvent({
    this.key,
    this.keyCode,
    this.shiftKey = false,
    this.ctrlKey = false,
    this.altKey = false,
    this.metaKey = false,
  });

  @override
  final String? key;

  @override
  final int? keyCode;

  @override
  final bool shiftKey;

  @override
  final bool ctrlKey;

  @override
  final bool altKey;

  @override
  final bool metaKey;
}

class _Counter implements Command {
  int count = 0;

  @override
  bool execute(
    EditorState state, [
    void Function(Transaction)? dispatch,
    Object? view,
  ]) {
    count++;
    return true;
  }
}
