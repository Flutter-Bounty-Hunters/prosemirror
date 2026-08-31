import 'package:prosemirror/src/dependencies/w3c_keyname/platform.dart';
import 'package:prosemirror/src/dependencies/w3c_keyname/w3c_keyname.dart';
import 'package:prosemirror/src/state/plugin.dart';
import 'package:prosemirror/src/state/state.dart';
import 'package:prosemirror/src/state/transaction.dart';

final bool _mac = isMacPlatform;
final bool _windows = isWindowsPlatform;

/// A DOM-free stand-in for the editor view, exposing just the state and
/// dispatch that keymap commands need.
abstract interface class KeymapView {
  /// The current editor state.
  EditorState get state;

  /// The function used to dispatch transactions.
  void Function(Transaction) get dispatch;
}

/// A keydown handler that returns true when it has handled the event.
typedef KeydownHandler = bool Function(KeymapView view, KeyEvent event);

/// Create a keymap plugin for the given set of bindings.
///
/// Bindings should map key names to command-style functions, which will be
/// called with `(EditorState, dispatch, view)` arguments, and should return
/// true when they've handled the key.
///
/// Key names may be strings like `"Shift-Ctrl-Enter"` — a key identifier
/// prefixed with zero or more modifiers. Use `"Space"` as an alias for the
/// `" "` name. Modifiers `Shift-` (or `s-`), `Alt-` (or `a-`), `Ctrl-` (or
/// `c-` or `Control-`) and `Cmd-` (or `m-` or `Meta-`) are recognized. Use
/// `Mod-` as a shorthand for `Cmd-` on Mac and `Ctrl-` on other platforms.
//
// NOTE: The state `Plugin._bindProps` wraps every function-valued prop into
// `() => fn(plugin)`, which mangles the two-argument `handleKeyDown` when it is
// read back from `plugin.props`. Constructing the plugin here is fine (the
// wrapped closure is inert unless called), but callers that need to run the
// handler should invoke `keydownHandler(bindings)` directly. A proper
// `_bindProps` fix is deferred to the prosemirror-view port.
Plugin keymap(Map<String, Command> bindings) {
  return Plugin(PluginSpec(props: {"handleKeyDown": keydownHandler(bindings)}));
}

/// Given a set of bindings (using the same format as [keymap]), return a
/// keydown handler that handles them.
KeydownHandler keydownHandler(Map<String, Command> bindings) {
  final map = _normalize(bindings);
  return (view, event) {
    final name = keyName(event);
    final direct = map[_modifiers(name, event)];
    if (direct != null && direct.execute(view.state, view.dispatch, view)) {
      return true;
    }
    // A character key.
    if (name.length == 1 && name != " ") {
      if (event.shiftKey) {
        // In case the name was already modified by shift, try looking it up
        // without its shift modifier.
        final noShift = map[_modifiers(name, event, false)];
        if (noShift != null &&
            noShift.execute(view.state, view.dispatch, view)) {
          return true;
        }
      }
      if ((event.altKey || event.metaKey || event.ctrlKey) &&
          // Ctrl-Alt may be used for AltGr on Windows.
          !(_windows && event.ctrlKey && event.altKey) &&
          event.keyCode != null) {
        // Try falling back to the keyCode when there's a modifier active and
        // our table produces a different name from the keyCode.
        final baseName = base[event.keyCode!];
        if (baseName != null && baseName != name) {
          final fromCode = map[_modifiers(baseName, event)];
          if (fromCode != null &&
              fromCode.execute(view.state, view.dispatch, view)) {
            return true;
          }
        }
      }
    }
    return false;
  };
}

String _normalizeKeyName(String name) {
  final parts = name.split(RegExp(r'-(?!$)'));
  var result = parts[parts.length - 1];
  if (result == "Space") {
    result = " ";
  }
  var alt = false;
  var ctrl = false;
  var shiftMod = false;
  var meta = false;
  for (var index = 0; index < parts.length - 1; index++) {
    final modifier = parts[index];
    if (RegExp(r'^(cmd|meta|m)$', caseSensitive: false).hasMatch(modifier)) {
      meta = true;
    } else if (RegExp(r'^a(lt)?$', caseSensitive: false).hasMatch(modifier)) {
      alt = true;
    } else if (RegExp(
      r'^(c|ctrl|control)$',
      caseSensitive: false,
    ).hasMatch(modifier)) {
      ctrl = true;
    } else if (RegExp(r'^s(hift)?$', caseSensitive: false).hasMatch(modifier)) {
      shiftMod = true;
    } else if (RegExp(r'^mod$', caseSensitive: false).hasMatch(modifier)) {
      if (_mac) {
        meta = true;
      } else {
        ctrl = true;
      }
    } else {
      throw ArgumentError("Unrecognized modifier name: $modifier");
    }
  }
  if (alt) {
    result = "Alt-$result";
  }
  if (ctrl) {
    result = "Ctrl-$result";
  }
  if (meta) {
    result = "Meta-$result";
  }
  if (shiftMod) {
    result = "Shift-$result";
  }
  return result;
}

Map<String, Command> _normalize(Map<String, Command> map) {
  final copy = <String, Command>{};
  map.forEach((prop, command) {
    final normalized = _normalizeKeyName(prop);
    if (copy.containsKey(normalized)) {
      throw ArgumentError(
        "Multiple bindings for key $normalized in a single keymap",
      );
    }
    copy[normalized] = command;
  });
  return copy;
}

String _modifiers(String name, KeyEvent event, [bool shift = true]) {
  if (event.altKey) {
    name = "Alt-$name";
  }
  if (event.ctrlKey) {
    name = "Ctrl-$name";
  }
  if (event.metaKey) {
    name = "Meta-$name";
  }
  if (shift && event.shiftKey) {
    name = "Shift-$name";
  }
  return name;
}
