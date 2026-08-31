library;

import 'package:prosemirror/src/model/fragment.dart';
import 'package:prosemirror/src/model/node.dart';
import 'package:prosemirror/src/model/replace.dart';
import 'package:prosemirror/src/state/plugin.dart';
import 'package:prosemirror/src/state/selection.dart';
import 'package:prosemirror/src/state/state.dart';
import 'package:prosemirror/src/state/transaction.dart';

/// A predicate that can ignore individual search results.
typedef SearchResultFilter = bool Function(
  EditorState state,
  SearchResult result,
);

/// The range searched by the search plugin and commands.
class SearchRange {
  /// Creates a search range.
  const SearchRange({required this.from, required this.to});

  /// The start of the searched range.
  final int from;

  /// The end of the searched range.
  final int to;
}

/// A matched instance of a search query.
class SearchResult {
  /// Creates a search result.
  SearchResult({
    required this.from,
    required this.to,
    required this.match,
    required this.matchStart,
  });

  /// The match start in the document.
  final int from;

  /// The match end in the document.
  final int to;

  /// The regular expression match, or null for string queries.
  final RegExpMatch? match;

  /// The start position of the textblock that produced [match].
  final int matchStart;
}

/// A search query over ProseMirror documents.
class SearchQuery {
  /// Creates a search query.
  SearchQuery({
    required this.search,
    this.caseSensitive = false,
    this.literal = false,
    this.regexp = false,
    this.replace = "",
    this.wholeWord = false,
    this.filter,
  }) : valid = search.isNotEmpty && (!regexp || _validRegExp(search)),
       _implementation = search.isNotEmpty && (!regexp || _validRegExp(search))
           ? regexp
                 ? _RegExpQuery(search, caseSensitive)
                 : _StringQuery(_unquote(search, literal), caseSensitive)
           : _NullQuery();

  /// The search string, or regular expression source.
  final String search;

  /// Whether this query is case-sensitive.
  final bool caseSensitive;

  /// Whether string escape unquoting is disabled.
  final bool literal;

  /// Whether [search] is interpreted as a regular expression.
  final bool regexp;

  /// The replacement text.
  final String replace;

  /// Whether this query is non-empty and, for regular expressions, valid.
  final bool valid;

  /// Whether to only match at word boundaries.
  final bool wholeWord;

  /// Optional filter used to ignore matches.
  final SearchResultFilter? filter;

  final _QueryImplementation _implementation;

  /// Compare this query to another query.
  bool eq(SearchQuery other) {
    return search == other.search &&
        replace == other.replace &&
        caseSensitive == other.caseSensitive &&
        regexp == other.regexp &&
        wholeWord == other.wholeWord;
  }

  /// Find the next occurrence of this query in the given range.
  SearchResult? findNext(EditorState state, [int from = 0, int? to]) {
    final end = to ?? state.doc.content.size;
    var start = from;
    for (;;) {
      if (start >= end) {
        return null;
      }
      final result = _implementation.findNext(state, start, end);
      if (result == null || _checkResult(state, result)) {
        return result;
      }
      start = _max(start, result.from) + 1;
    }
  }

  /// Find the previous occurrence of this query in the given range.
  SearchResult? findPrev(EditorState state, [int? from, int to = 0]) {
    var start = from ?? state.doc.content.size;
    for (;;) {
      if (start <= to) {
        return null;
      }
      final result = _implementation.findPrev(state, start, to);
      if (result == null || _checkResult(state, result)) {
        return result;
      }
      start = _min(start, result.to) - 1;
    }
  }

  /// Get the document replacements for [result].
  List<SearchReplacement> getReplacements(
    EditorState state,
    SearchResult result,
  ) {
    final $from = state.doc.resolve(result.from);
    final marks =
        $from.marksAcross(state.doc.resolve(result.to)) ?? $from.marks();
    final ranges = <SearchReplacement>[];
    var fragment = Fragment.empty;
    var position = result.from;
    final groups = result.match != null
        ? _getGroupIndices(result.match!)
        : <SearchGroupSpan?>[(from: 0, to: result.to - result.from)];
    final replacementParts = _parseReplacement(_unquote(replace, literal));

    for (final part in replacementParts) {
      if (part is _ReplacementText) {
        if (part.text.isNotEmpty) {
          fragment = fragment.addToEnd(state.schema.text(part.text, marks));
        }
      } else if (part is _ReplacementGroup) {
        final groupSpan = part.group < groups.length
            ? groups[part.group]
            : null;
        if (groupSpan == null) {
          continue;
        }
        final from = result.matchStart + groupSpan.from;
        final to = result.matchStart + groupSpan.to;
        if (part.copy) {
          fragment = fragment.append(state.doc.slice(from, to).content);
        } else {
          if (!identical(fragment, Fragment.empty) || from > position) {
            ranges.add(
              SearchReplacement(
                from: position,
                to: from,
                insert: Slice(fragment, 0, 0),
              ),
            );
            fragment = Fragment.empty;
          }
          position = to;
        }
      }
    }

    if (!identical(fragment, Fragment.empty) || position < result.to) {
      ranges.add(
        SearchReplacement(
          from: position,
          to: result.to,
          insert: Slice(fragment, 0, 0),
        ),
      );
    }
    return ranges;
  }

  bool _checkResult(EditorState state, SearchResult result) {
    return (!wholeWord ||
            (_checkWordBoundary(state, result.from) &&
                _checkWordBoundary(state, result.to))) &&
        (filter == null || filter!(state, result));
  }
}

/// A single replacement range for a search result.
class SearchReplacement {
  /// Creates a search replacement.
  SearchReplacement({
    required this.from,
    required this.to,
    required this.insert,
  });

  /// The replaced range start.
  final int from;

  /// The replaced range end.
  final int to;

  /// The content to insert.
  final Slice insert;
}

/// The public search plugin state.
class SearchState {
  /// Creates search plugin state.
  SearchState({
    required this.query,
    required this.range,
    required this.highlights,
  });

  /// The active search query.
  final SearchQuery query;

  /// The active search range, if limited.
  final SearchRange? range;

  /// The current match highlights.
  final SearchHighlights highlights;
}

/// A collection of search highlight ranges.
class SearchHighlights {
  /// Creates a set of search highlights.
  const SearchHighlights(this.matches);

  /// Highlighted ranges.
  final List<SearchHighlight> matches;

  /// Whether there are no highlights.
  bool get isEmpty => matches.isEmpty;

  /// An empty highlight set.
  static const empty = SearchHighlights(<SearchHighlight>[]);
}

/// A highlighted search result range.
class SearchHighlight {
  /// Creates a search highlight.
  const SearchHighlight({
    required this.from,
    required this.to,
    required this.active,
  });

  /// The highlight start.
  final int from;

  /// The highlight end.
  final int to;

  /// Whether this highlight is the current selection.
  final bool active;

  /// The class name used by upstream styling.
  String get className =>
      active ? "ProseMirror-active-search-match" : "ProseMirror-search-match";
}

/// Returns a plugin that stores the current search query and range.
Plugin search({SearchQuery? initialQuery, SearchRange? initialRange}) {
  return Plugin(
    PluginSpec(
      key: _searchKey,
      state: StateField(init: _initSearchState, apply: _applySearchState),
      extra: <String, Object?>{
        "initialQuery": initialQuery,
        "initialRange": initialRange,
      },
    ),
  );
}

/// Get the current active search query and searched range.
SearchState? getSearchState(EditorState state) {
  final searchState = _searchKey.getState(state);
  return searchState is SearchState ? searchState : null;
}

/// Access the current search match highlights.
SearchHighlights getMatchHighlights(EditorState state) {
  return getSearchState(state)?.highlights ?? SearchHighlights.empty;
}

/// Add metadata to [transaction] that updates active search state.
Transaction setSearchState(
  Transaction transaction,
  SearchQuery query, [
  SearchRange? range,
]) {
  return transaction.setMeta(
    _searchKey,
    _SearchStateMeta(query: query, range: range),
  );
}

/// Find the next instance of the search query.
final Command findNext = _FindCommand(
  wrap: true,
  direction: _SearchDirection.next,
);

/// Find the next instance without wrapping.
final Command findNextNoWrap = _FindCommand(
  wrap: false,
  direction: _SearchDirection.next,
);

/// Find the previous instance of the search query.
final Command findPrev = _FindCommand(
  wrap: true,
  direction: _SearchDirection.previous,
);

/// Find the previous instance without wrapping.
final Command findPrevNoWrap = _FindCommand(
  wrap: false,
  direction: _SearchDirection.previous,
);

/// Replace the selected instance, or select the next one.
final Command replaceNext = _ReplaceCommand(wrap: true, moveForward: true);

/// Replace the next instance without wrapping.
final Command replaceNextNoWrap = _ReplaceCommand(
  wrap: false,
  moveForward: true,
);

/// Replace the selected instance and keep the replacement selected.
final Command replaceCurrent = _ReplaceCommand(wrap: false, moveForward: false);

/// Replace all instances of the active search query.
final Command replaceAll = FunctionCommand(_replaceAll);

final PluginKey _searchKey = PluginKey("search");

Object? _initSearchState(EditorStateConfig config, EditorState instance) {
  final plugin = _searchKey.get(instance);
  final initialQuery = plugin?.spec.extra["initialQuery"] as SearchQuery?;
  final initialRange = plugin?.spec.extra["initialRange"] as SearchRange?;
  final query = initialQuery ?? SearchQuery(search: "");
  return SearchState(
    query: query,
    range: initialRange,
    highlights: _buildMatchHighlights(instance, query, initialRange),
  );
}

Object? _applySearchState(
  Transaction transaction,
  Object? value,
  EditorState oldState,
  EditorState newState,
) {
  final meta = transaction.getMeta(_searchKey);
  if (meta is _SearchStateMeta) {
    return SearchState(
      query: meta.query,
      range: meta.range,
      highlights: _buildMatchHighlights(newState, meta.query, meta.range),
    );
  }

  var searchState = value as SearchState;
  if (transaction.docChanged || transaction.selectionSet) {
    final range = _mapSearchRange(searchState.range, transaction);
    searchState = SearchState(
      query: searchState.query,
      range: range,
      highlights: _buildMatchHighlights(newState, searchState.query, range),
    );
  }
  return searchState;
}

SearchHighlights _buildMatchHighlights(
  EditorState state,
  SearchQuery query,
  SearchRange? range,
) {
  if (!query.valid) {
    return SearchHighlights.empty;
  }

  final highlights = <SearchHighlight>[];
  final selection = state.selection;
  final start = range?.from ?? 0;
  final end = range?.to ?? state.doc.content.size;
  for (var position = start; ;) {
    final next = query.findNext(state, position, end);
    if (next == null) {
      break;
    }
    highlights.add(
      SearchHighlight(
        from: next.from,
        to: next.to,
        active: next.from == selection.from && next.to == selection.to,
      ),
    );
    position = _max(next.to, position + 1);
  }
  return SearchHighlights(List<SearchHighlight>.unmodifiable(highlights));
}

SearchRange? _mapSearchRange(SearchRange? range, Transaction transaction) {
  if (range == null) {
    return null;
  }
  final from = transaction.mapping.map(range.from, 1);
  final to = transaction.mapping.map(range.to, -1);
  return from < to ? SearchRange(from: from, to: to) : null;
}

SearchResult? _nextMatch(
  SearchState searchState,
  EditorState state,
  bool wrap,
  int currentFrom,
  int currentTo,
) {
  final range =
      searchState.range ?? SearchRange(from: 0, to: state.doc.content.size);
  var next = searchState.query.findNext(
    state,
    _max(currentTo, range.from),
    range.to,
  );
  if (next == null && wrap) {
    next = searchState.query.findNext(
      state,
      range.from,
      _min(currentFrom, range.to),
    );
  }
  return next;
}

SearchResult? _prevMatch(
  SearchState searchState,
  EditorState state,
  bool wrap,
  int currentFrom,
  int currentTo,
) {
  final range =
      searchState.range ?? SearchRange(from: 0, to: state.doc.content.size);
  var previous = searchState.query.findPrev(
    state,
    _min(currentFrom, range.to),
    range.from,
  );
  if (previous == null && wrap) {
    previous = searchState.query.findPrev(
      state,
      range.to,
      _max(currentTo, range.from),
    );
  }
  return previous;
}

bool _replaceAll(
  EditorState state, [
  void Function(Transaction transaction)? dispatch,
  Object? view,
]) {
  final searchState = getSearchState(state);
  if (searchState == null) {
    return false;
  }

  final matches = <SearchResult>[];
  final range =
      searchState.range ?? SearchRange(from: 0, to: state.doc.content.size);
  for (var position = range.from; ;) {
    final next = searchState.query.findNext(state, position, range.to);
    if (next == null) {
      break;
    }
    if (next.to > position || matches.isEmpty) {
      matches.add(next);
    }
    position = _max(next.to, position + 1);
  }

  if (dispatch != null) {
    final transaction = state.tr;
    for (var matchIndex = matches.length - 1; matchIndex >= 0; matchIndex--) {
      final replacements = searchState.query.getReplacements(
        state,
        matches[matchIndex],
      );
      for (
        var replacementIndex = replacements.length - 1;
        replacementIndex >= 0;
        replacementIndex--
      ) {
        final replacement = replacements[replacementIndex];
        transaction.replace(
          replacement.from,
          replacement.to,
          replacement.insert,
        );
      }
    }
    dispatch(transaction);
  }
  return true;
}

abstract interface class _QueryImplementation {
  SearchResult? findNext(EditorState state, int from, int to);

  SearchResult? findPrev(EditorState state, int from, int to);
}

class _NullQuery implements _QueryImplementation {
  @override
  SearchResult? findNext(EditorState state, int from, int to) {
    return null;
  }

  @override
  SearchResult? findPrev(EditorState state, int from, int to) {
    return null;
  }
}

class _StringQuery implements _QueryImplementation {
  _StringQuery(String string, bool caseSensitive)
    : caseSensitive = caseSensitive,
      string = caseSensitive ? string : string.toLowerCase();

  final String string;
  final bool caseSensitive;

  @override
  SearchResult? findNext(EditorState state, int from, int to) {
    return _scanTextblocks(state.doc, from, to, (node, start) {
      final offset = _max(from, start);
      final content = _textContent(node)
          .substring(offset - start, _min(node.content.size, to - start));
      final searched = caseSensitive ? content : content.toLowerCase();
      final index = searched.indexOf(string);
      return index < 0
          ? null
          : SearchResult(
              from: offset + index,
              to: offset + index + string.length,
              match: null,
              matchStart: start,
            );
    });
  }

  @override
  SearchResult? findPrev(EditorState state, int from, int to) {
    return _scanTextblocks(state.doc, from, to, (node, start) {
      final offset = _max(start, to);
      var content = _textContent(node)
          .substring(offset - start, _min(node.content.size, from - start));
      if (!caseSensitive) {
        content = content.toLowerCase();
      }
      final index = content.lastIndexOf(string);
      return index < 0
          ? null
          : SearchResult(
              from: offset + index,
              to: offset + index + string.length,
              match: null,
              matchStart: start,
            );
    });
  }
}

class _RegExpQuery implements _QueryImplementation {
  _RegExpQuery(String source, bool caseSensitive)
    : expression = RegExp(source, caseSensitive: caseSensitive, unicode: true);

  final RegExp expression;

  @override
  SearchResult? findNext(EditorState state, int from, int to) {
    return _scanTextblocks(state.doc, from, to, (node, start) {
      final searchStart = _max(0, from - start);
      final content = _textContent(node)
          .substring(0, _min(node.content.size, to - start));
      final match =
          expression.matchAsPrefix(content, searchStart) as RegExpMatch?;
      final next =
          match ?? _firstRegExpMatchAtOrAfter(expression, content, searchStart);
      if (next == null) {
        return null;
      }
      return SearchResult(
        from: start + next.start,
        to: start + next.start + next.group(0)!.length,
        match: next,
        matchStart: start,
      );
    });
  }

  @override
  SearchResult? findPrev(EditorState state, int from, int to) {
    return _scanTextblocks(state.doc, from, to, (node, start) {
      final content = _textContent(node)
          .substring(0, _min(node.content.size, from - start));
      RegExpMatch? match;
      for (var offset = 0; offset <= content.length;) {
        final next = _firstRegExpMatchAtOrAfter(expression, content, offset);
        if (next == null) {
          break;
        }
        match = next;
        offset = next.start + 1;
      }
      return match == null
          ? null
          : SearchResult(
              from: start + match.start,
              to: start + match.start + match.group(0)!.length,
              match: match,
              matchStart: start,
            );
    });
  }
}

typedef _TextblockScanner<T> = T? Function(Node node, int startPosition);

T? _scanTextblocks<T>(
  Node node,
  int from,
  int to,
  _TextblockScanner<T> scanner, [
  int nodeStart = 0,
]) {
  if (node.inlineContent) {
    return scanner(node, nodeStart);
  } else if (!node.isLeaf) {
    if (from > to) {
      return _scanTextblocksBackward(node, from, to, scanner, nodeStart);
    }
    return _scanTextblocksForward(node, from, to, scanner, nodeStart);
  }
  return null;
}

T? _scanTextblocksForward<T>(
  Node node,
  int from,
  int to,
  _TextblockScanner<T> scanner,
  int nodeStart,
) {
  for (
    var index = 0, position = nodeStart;
    index < node.childCount && position < to;
    index++
  ) {
    final child = node.child(index);
    final start = position;
    position += child.nodeSize;
    if (position > from) {
      final result = _scanTextblocks(child, from, to, scanner, start + 1);
      if (result != null) {
        return result;
      }
    }
  }
  return null;
}

T? _scanTextblocksBackward<T>(
  Node node,
  int from,
  int to,
  _TextblockScanner<T> scanner,
  int nodeStart,
) {
  for (
    var index = node.childCount - 1, position = nodeStart + node.content.size;
    index >= 0 && position > to;
    index--
  ) {
    final child = node.child(index);
    position -= child.nodeSize;
    if (position < from) {
      final result = _scanTextblocks(child, from, to, scanner, position + 1);
      if (result != null) {
        return result;
      }
    }
  }
  return null;
}

RegExpMatch? _firstRegExpMatchAtOrAfter(
  RegExp expression,
  String content,
  int start,
) {
  for (var offset = start; offset <= content.length; offset++) {
    final match = expression.matchAsPrefix(content, offset);
    if (match != null) {
      return match as RegExpMatch;
    }
  }
  return null;
}

final Expando<String> _textContentCache = Expando<String>();

String _textContent(Node node) {
  final cached = _textContentCache[node];
  if (cached != null) {
    return cached;
  }

  final buffer = StringBuffer();
  for (var index = 0; index < node.childCount; index++) {
    final child = node.child(index);
    if (child.isText) {
      buffer.write(child.text);
    } else if (child.isLeaf) {
      buffer.write("\ufffc");
    } else {
      buffer.write(" ");
      buffer.write(_textContent(child));
      buffer.write(" ");
    }
  }
  final content = buffer.toString();
  _textContentCache[node] = content;
  return content;
}

bool _checkWordBoundary(EditorState state, int position) {
  final resolvedPosition = state.doc.resolve(position);
  final before = resolvedPosition.nodeBefore;
  final after = resolvedPosition.nodeAfter;
  if (before == null || after == null || !before.isText || !after.isText) {
    return true;
  }
  return !_endsWithLetter(before.text!) || !_startsWithLetter(after.text!);
}

bool _endsWithLetter(String text) {
  return text.isNotEmpty && _isLetter(text.runes.last);
}

bool _startsWithLetter(String text) {
  return text.isNotEmpty && _isLetter(text.runes.first);
}

bool _isLetter(int rune) {
  return (rune >= 0x41 && rune <= 0x5a) ||
      (rune >= 0x61 && rune <= 0x7a) ||
      (rune >= 0xc0 && rune <= 0x2af);
}

bool _validRegExp(String source) {
  try {
    RegExp(source, unicode: true);
    return true;
  } catch (_) {
    return false;
  }
}

String _unquote(String string, bool literal) {
  if (literal) {
    return string;
  }
  return string.replaceAllMapped(RegExp(r'\\([nrt\\])'), _unquoteMatch);
}

String _unquoteMatch(Match match) {
  final character = match.group(1);
  if (character == "n") {
    return "\n";
  }
  if (character == "r") {
    return "\r";
  }
  if (character == "t") {
    return "\t";
  }
  return "\\";
}

typedef SearchGroupSpan = ({int from, int to});

List<SearchGroupSpan?> _getGroupIndices(RegExpMatch match) {
  final fullMatch = match.group(0)!;
  final result = <SearchGroupSpan?>[(from: match.start, to: match.end)];
  var position = 0;
  for (var index = 1; index <= match.groupCount; index++) {
    final group = match.group(index);
    final found = group != null ? fullMatch.indexOf(group, position) : -1;
    if (found < 0) {
      result.add(null);
    } else {
      position = found + group!.length;
      result.add((from: match.start + found, to: match.start + position));
    }
  }
  return result;
}

List<Object> _parseReplacement(String text) {
  final result = <Object>[];
  var remaining = text;
  var highestSeen = -1;
  while (remaining.isNotEmpty) {
    final match = _replacementPattern.firstMatch(remaining);
    if (match == null) {
      _addReplacementText(result, remaining);
      return result;
    }
    if (match.start > 0) {
      final end = match.start + (match.group(1) == r"$" ? 1 : 0);
      _addReplacementText(result, remaining.substring(0, end));
    }
    final marker = match.group(1)!;
    if (marker != r"$") {
      final group = marker == "&" ? 0 : int.tryParse(marker);
      if (group == null) {
        highestSeen = 1000;
        remaining = remaining.substring(match.end);
        continue;
      }
      if (highestSeen >= group) {
        result.add(_ReplacementGroup(group: group, copy: true));
      } else {
        highestSeen = group == 0 ? 1000 : group;
        result.add(_ReplacementGroup(group: group, copy: false));
      }
    }
    remaining = remaining.substring(match.end);
  }
  return result;
}

final RegExp _replacementPattern = RegExp(r'\$([$&\d+])');

void _addReplacementText(List<Object> result, String text) {
  if (text.isEmpty) {
    return;
  }
  final lastIndex = result.length - 1;
  if (lastIndex >= 0 && result[lastIndex] is _ReplacementText) {
    final last = result[lastIndex] as _ReplacementText;
    result[lastIndex] = _ReplacementText(last.text + text);
  } else {
    result.add(_ReplacementText(text));
  }
}

class _ReplacementText {
  _ReplacementText(this.text);

  final String text;
}

class _ReplacementGroup {
  _ReplacementGroup({required this.group, required this.copy});

  final int group;
  final bool copy;
}

enum _SearchDirection { next, previous }

class _FindCommand implements Command {
  const _FindCommand({required this.wrap, required this.direction});

  final bool wrap;
  final _SearchDirection direction;

  @override
  bool execute(
    EditorState state, [
    void Function(Transaction transaction)? dispatch,
    Object? view,
  ]) {
    final searchState = getSearchState(state);
    if (searchState == null || !searchState.query.valid) {
      return false;
    }
    final selection = state.selection;
    final next = direction == _SearchDirection.next
        ? _nextMatch(searchState, state, wrap, selection.from, selection.to)
        : _prevMatch(searchState, state, wrap, selection.from, selection.to);
    if (next == null) {
      return false;
    }
    dispatch?.call(
      state.tr
          .setSelection(TextSelection.create(state.doc, next.from, next.to))
          .scrollIntoView(),
    );
    return true;
  }
}

class _ReplaceCommand implements Command {
  const _ReplaceCommand({required this.wrap, required this.moveForward});

  final bool wrap;
  final bool moveForward;

  @override
  bool execute(
    EditorState state, [
    void Function(Transaction transaction)? dispatch,
    Object? view,
  ]) {
    final searchState = getSearchState(state);
    if (searchState == null || !searchState.query.valid) {
      return false;
    }
    final selection = state.selection;
    final next = _nextMatch(
      searchState,
      state,
      wrap,
      selection.from,
      selection.from,
    );
    if (next == null) {
      return false;
    }

    if (dispatch == null) {
      return true;
    }
    if (selection.from == next.from && selection.to == next.to) {
      _replaceSelectedMatch(state, searchState, next, dispatch);
    } else if (!moveForward) {
      return false;
    } else {
      dispatch(
        state.tr
            .setSelection(TextSelection.create(state.doc, next.from, next.to))
            .scrollIntoView(),
      );
    }
    return true;
  }

  void _replaceSelectedMatch(
    EditorState state,
    SearchState searchState,
    SearchResult next,
    void Function(Transaction transaction) dispatch,
  ) {
    final transaction = state.tr;
    final replacements = searchState.query.getReplacements(state, next);
    for (
      var replacementIndex = replacements.length - 1;
      replacementIndex >= 0;
      replacementIndex--
    ) {
      final replacement = replacements[replacementIndex];
      transaction.replace(replacement.from, replacement.to, replacement.insert);
    }

    final after = moveForward
        ? _nextMatch(searchState, state, wrap, next.from, next.to)
        : null;
    if (after != null) {
      transaction.setSelection(
        TextSelection.create(
          transaction.doc,
          transaction.mapping.map(after.from, 1),
          transaction.mapping.map(after.to, -1),
        ),
      );
    } else {
      transaction.setSelection(
        TextSelection.create(
          transaction.doc,
          next.from,
          transaction.mapping.map(next.to, 1),
        ),
      );
    }
    dispatch(transaction.scrollIntoView());
  }
}

class _SearchStateMeta {
  _SearchStateMeta({required this.query, required this.range});

  final SearchQuery query;
  final SearchRange? range;
}

int _min(int first, int second) {
  return first < second ? first : second;
}

int _max(int first, int second) {
  return first > second ? first : second;
}
