import 'package:prosemirror/src/inputrules/inputrules.dart';

/// Converts double dashes to an emdash.
final InputRule emDash = InputRule(RegExp(r'--$'), "—", inCodeMark: false);

/// Converts three dots to an ellipsis character.
final InputRule ellipsis = InputRule(
  RegExp(r'\.\.\.$'),
  "…",
  inCodeMark: false,
);

/// "Smart" opening double quotes.
final InputRule openDoubleQuote = InputRule(
  RegExp("(?:^|[\\s\\{\\[\\(\\<'\"\\u2018\\u201C])(\")\$"),
  "“",
  inCodeMark: false,
);

/// "Smart" closing double quotes.
final InputRule closeDoubleQuote = InputRule(
  RegExp(r'"$'),
  "”",
  inCodeMark: false,
);

/// "Smart" opening single quotes.
final InputRule openSingleQuote = InputRule(
  RegExp("(?:^|[\\s\\{\\[\\(\\<'\"\\u2018\\u201C])(')\$"),
  "‘",
  inCodeMark: false,
);

/// "Smart" closing single quotes.
final InputRule closeSingleQuote = InputRule(
  RegExp(r"'$"),
  "’",
  inCodeMark: false,
);

/// Smart-quote related input rules.
final List<InputRule> smartQuotes = <InputRule>[
  openDoubleQuote,
  closeDoubleQuote,
  openSingleQuote,
  closeSingleQuote,
];
