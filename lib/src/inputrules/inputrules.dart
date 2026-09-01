import 'dart:math';

import 'package:prosemirror/src/state/plugin.dart';
import 'package:prosemirror/src/state/state.dart';
import 'package:prosemirror/src/state/transaction.dart';

/// The function form of an [InputRule] handler. It is called with the match
/// array produced by the rule's regular expression, together with the start
/// and end of the matched range, and returns a [Transaction] that describes
/// the rule's effect, or `null` to indicate the input was not handled.
typedef InputRuleHandler = Transaction? Function(EditorState state, RegExpMatch match, int start, int end);

/// Input rules are regular expressions describing a piece of text that, when
/// typed, causes something to happen. This might be changing two dashes into
/// an emdash, wrapping a paragraph starting with `"> "` into a blockquote, or
/// something entirely different.
class InputRule {
  /// Create an input rule. The rule applies when the user typed something and
  /// the text directly in front of the cursor matches [match], which should
  /// end with `$`.
  ///
  /// The [handler] can be a [String], in which case the matched text, or the
  /// first matched group in the regexp, is replaced by that string. Or it can
  /// be an [InputRuleHandler] function.
  ///
  /// When [undoable] is set to false, [undoInputRule] doesn't work on this
  /// rule. By default, input rules will not apply inside nodes marked as code.
  /// Set [inCode] to true to change that, or to `"only"` to only match in
  /// such nodes. When [inCodeMark] is set to false, this rule will not fire
  /// inside marks marked as code.
  InputRule(this.match, Object handler, {this.undoable = true, this.inCode = false, this.inCodeMark = true})
    : handler = handler is String ? _stringHandler(handler) : handler as InputRuleHandler;

  /// The regular expression this rule matches against.
  final RegExp match;

  /// @internal
  final InputRuleHandler handler;

  /// @internal
  final bool undoable;

  /// Whether the rule fires inside nodes marked as code (`bool` or `"only"`).
  final Object inCode;

  /// Whether the rule fires inside marks marked as code.
  final bool inCodeMark;
}

InputRuleHandler _stringHandler(String string) {
  return (EditorState state, RegExpMatch match, int start, int end) {
    var insert = string;
    final group1 = match.groupCount >= 1 ? match.group(1) : null;
    if (group1 != null && group1.isNotEmpty) {
      final group0 = match.group(0)!;
      final offset = group0.lastIndexOf(group1);
      insert += group0.substring(offset + group1.length);
      start += offset;
      final cutOff = start - end;
      if (cutOff > 0) {
        insert = group0.substring(offset - cutOff, offset) + insert;
        start = end;
      }
    }
    return state.tr.insertText(insert, start, end);
  };
}

const int _maxMatch = 500;

/// Create an input rules plugin. When enabled, it will cause text input that
/// matches any of the given rules to trigger the rule's action.
Plugin inputRules({required List<InputRule> rules}) {
  late final Plugin plugin;
  plugin = Plugin(
    PluginSpec(
      state: StateField(
        init: (config, instance) => null,
        apply: (tr, value, oldState, newState) {
          final stored = tr.getMeta(plugin);
          if (stored != null) {
            return stored;
          }
          return (tr.selectionSet || tr.docChanged) ? null : value;
        },
      ),
      extra: <String, Object?>{"isInputRules": true, "rules": rules},
    ),
  );
  return plugin;
}

class _InputRulesState {
  _InputRulesState({required this.transform, required this.from, required this.to, required this.text});

  final Transaction transform;
  final int from;
  final int to;
  final String text;
}

/// The view-free entry point that applies the given [rules] to the text that
/// was typed at the given range, dispatching the resulting transaction and
/// returning whether a rule fired.
///
/// This is the non-DOM port of `prosemirror-inputrules`' private `run`
/// function, which a future `prosemirror-view` port will call from its
/// `handleTextInput` prop.
bool runInputRules(
  EditorState state,
  int from,
  int to,
  String text,
  List<InputRule> rules,
  Plugin plugin,
  void Function(Transaction tr) dispatch, {
  bool composing = false,
}) {
  if (composing) {
    return false;
  }
  final $from = state.doc.resolve(from);
  final textBefore =
      $from.parent.textBetween(max(0, $from.parentOffset - _maxMatch), $from.parentOffset, null, "￼") + text;
  for (final rule in rules) {
    if (!rule.inCodeMark && $from.marks().any((mark) => mark.type.spec.code)) {
      continue;
    }
    if ($from.parent.type.spec.code) {
      if (rule.inCode == false) {
        continue;
      }
    } else if (rule.inCode == "only") {
      continue;
    }
    final match = rule.match.firstMatch(textBefore);
    if (match == null || match.group(0)!.length < text.length) {
      continue;
    }
    final startPos = from - (match.group(0)!.length - text.length);
    if (!rule.inCodeMark) {
      var hasMark = false;
      state.doc.nodesBetween(startPos, $from.pos, (node, start, parent, index) {
        if (node.isInline && node.marks.any((mark) => mark.type.spec.code)) {
          hasMark = true;
        }
        return null;
      });
      if (hasMark) {
        continue;
      }
    }
    final tr = rule.handler(state, match, startPos, to);
    if (tr == null) {
      continue;
    }
    if (rule.undoable) {
      tr.setMeta(plugin, _InputRulesState(transform: tr, from: from, to: to, text: text));
    }
    dispatch(tr);
    return true;
  }
  return false;
}

/// A command that will undo an input rule, if applying such a rule was the
/// last thing that the user did.
final Command undoInputRule = FunctionCommand((
  EditorState state, [
  void Function(Transaction tr)? dispatch,
  Object? view,
]) {
  for (final plugin in state.plugins) {
    if (plugin.spec.extra["isInputRules"] != true) {
      continue;
    }
    final undoable = plugin.getState(state);
    if (undoable == null) {
      continue;
    }
    if (dispatch != null) {
      final tr = state.tr;
      final toUndo = (undoable as _InputRulesState).transform;
      for (var index = toUndo.steps.length - 1; index >= 0; index--) {
        tr.step(toUndo.steps[index].invert(toUndo.docs[index]));
      }
      if (undoable.text.isNotEmpty) {
        final marks = tr.doc.resolve(undoable.from).marks();
        tr.replaceWith(undoable.from, undoable.to, state.schema.text(undoable.text, marks));
      } else {
        tr.delete(undoable.from, undoable.to);
      }
      dispatch(tr);
    }
    return true;
  }
  return false;
});
