import 'package:prosemirror/src/dependencies/w3c_keyname/platform.dart';

/// A DOM-free stand-in for a browser `KeyboardEvent`, exposing just the
/// fields that [keyName] needs to derive a key name.
abstract interface class KeyEvent {
  /// The value of the pressed key, as reported by the platform.
  String? get key;

  /// The legacy numeric key code of the pressed key.
  int? get keyCode;

  /// Whether the Shift modifier is held.
  bool get shiftKey;

  /// Whether the Control modifier is held.
  bool get ctrlKey;

  /// Whether the Alt modifier is held.
  bool get altKey;

  /// Whether the Meta (Command) modifier is held.
  bool get metaKey;
}

/// Maps numeric key codes to their base (unshifted) key names.
final Map<int, String> base = _buildBase();

/// Maps numeric key codes to their shifted key names.
final Map<int, String> shift = _buildShift();

final bool _mac = isMacPlatform;

/// Returns a normalized name for the key described by [event], based on the
/// strings that can appear in a browser `KeyboardEvent.key`.
String keyName(KeyEvent event) {
  // On macOS, keys held with Shift and Cmd don't reflect the effect of Shift
  // in `.key`. (The IE branch from the original is dropped: there is no IE in
  // the Dart port.)
  final ignoreKey =
      (_mac && event.metaKey && event.shiftKey && !event.ctrlKey && !event.altKey) || event.key == "Unidentified";

  String? name;
  final key = event.key;
  if (!ignoreKey && key != null && key.isNotEmpty) {
    name = key;
  }
  name ??= (event.keyCode != null) ? (event.shiftKey ? shift : base)[event.keyCode!] : null;
  name ??= (key != null && key.isNotEmpty) ? key : null;
  name ??= "Unidentified";

  // Edge sometimes produces wrong names (Issue #3).
  if (name == "Esc") {
    name = "Escape";
  }
  if (name == "Del") {
    name = "Delete";
  }
  if (name == "Left") {
    name = "ArrowLeft";
  }
  if (name == "Up") {
    name = "ArrowUp";
  }
  if (name == "Right") {
    name = "ArrowRight";
  }
  if (name == "Down") {
    name = "ArrowDown";
  }
  return name;
}

Map<int, String> _buildBase() {
  final base = <int, String>{
    8: "Backspace",
    9: "Tab",
    10: "Enter",
    12: "NumLock",
    13: "Enter",
    16: "Shift",
    17: "Control",
    18: "Alt",
    20: "CapsLock",
    27: "Escape",
    32: " ",
    33: "PageUp",
    34: "PageDown",
    35: "End",
    36: "Home",
    37: "ArrowLeft",
    38: "ArrowUp",
    39: "ArrowRight",
    40: "ArrowDown",
    44: "PrintScreen",
    45: "Insert",
    46: "Delete",
    59: ";",
    61: "=",
    91: "Meta",
    92: "Meta",
    106: "*",
    107: "+",
    108: ",",
    109: "-",
    110: ".",
    111: "/",
    144: "NumLock",
    145: "ScrollLock",
    160: "Shift",
    161: "Shift",
    162: "Control",
    163: "Control",
    164: "Alt",
    165: "Alt",
    173: "-",
    186: ";",
    187: "=",
    188: ",",
    189: "-",
    190: ".",
    191: "/",
    192: "`",
    219: "[",
    220: "\\",
    221: "]",
    222: "'",
  };

  // Fill in the digit keys.
  for (var index = 0; index < 10; index++) {
    base[48 + index] = base[96 + index] = "$index";
  }

  // The function keys.
  for (var index = 1; index <= 24; index++) {
    base[index + 111] = "F$index";
  }

  // And the alphabetic keys.
  for (var index = 65; index <= 90; index++) {
    base[index] = String.fromCharCode(index + 32);
  }

  return base;
}

Map<int, String> _buildShift() {
  final shift = <int, String>{
    48: ")",
    49: "!",
    50: "@",
    51: "#",
    52: "\$",
    53: "%",
    54: "^",
    55: "&",
    56: "*",
    57: "(",
    59: ":",
    61: "+",
    173: "_",
    186: ":",
    187: "+",
    188: "<",
    189: "_",
    190: ">",
    191: "?",
    192: "~",
    219: "{",
    220: "|",
    221: "}",
    222: "\"",
  };

  // The alphabetic keys.
  for (var index = 65; index <= 90; index++) {
    shift[index] = String.fromCharCode(index);
  }

  // For each code that doesn't have a shift-equivalent, copy the base name.
  for (final code in base.keys) {
    shift.putIfAbsent(code, () => base[code]!);
  }

  return shift;
}
