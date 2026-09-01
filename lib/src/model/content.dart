import 'package:prosemirror/src/model/fragment.dart';
import 'package:prosemirror/src/model/schema.dart';

/// An outgoing edge of a [ContentMatch] state in the content automaton.
class MatchEdge {
  MatchEdge(this.type, this.next);

  final NodeType type;
  final ContentMatch next;
}

/// Instances of this class represent a match state of a node type's content
/// expression, and can be used to find out whether further content matches
/// here, and whether a given position is a valid end of the node.
class ContentMatch {
  /// @internal
  ContentMatch(this.validEnd);

  /// True when this match state represents a valid end of the node.
  final bool validEnd;

  /// @internal
  final List<MatchEdge> next = [];

  /// @internal
  final List<Object?> wrapCache = [];

  /// @internal
  static ContentMatch parse(String string, Map<String, NodeType> nodeTypes) {
    final stream = _TokenStream(string, nodeTypes);
    if (stream.next == null) {
      return empty;
    }
    final expr = _parseExpr(stream);
    if (stream.next != null) {
      stream.err("Unexpected trailing text");
    }
    final match = _dfa(_nfa(expr));
    _checkForDeadEnds(match, stream);
    return match;
  }

  /// Match a node type, returning a match after that node if successful.
  ContentMatch? matchType(NodeType type) {
    for (var index = 0; index < next.length; index++) {
      if (identical(next[index].type, type)) {
        return next[index].next;
      }
    }
    return null;
  }

  /// Try to match a fragment. Returns the resulting match when successful.
  ContentMatch? matchFragment(Fragment fragment, [int start = 0, int? end]) {
    end ??= fragment.childCount;
    ContentMatch? current = this;
    for (var index = start; current != null && index < end; index++) {
      current = current.matchType(fragment.child(index).type);
    }
    return current;
  }

  /// @internal
  bool get inlineContent => next.isNotEmpty && next[0].type.isInline;

  /// Get the first matching node type at this match position that can be
  /// generated.
  NodeType? get defaultType {
    for (var index = 0; index < next.length; index++) {
      final type = next[index].type;
      if (!(type.isText || type.hasRequiredAttrs())) {
        return type;
      }
    }
    return null;
  }

  /// @internal
  bool compatible(ContentMatch other) {
    for (var index = 0; index < next.length; index++) {
      for (var otherIndex = 0; otherIndex < other.next.length; otherIndex++) {
        if (identical(next[index].type, other.next[otherIndex].type)) {
          return true;
        }
      }
    }
    return false;
  }

  /// Try to match the given fragment, and if that fails, see if it can be made
  /// to match by inserting nodes in front of it.
  Fragment? fillBefore(Fragment after, [bool toEnd = false, int startIndex = 0]) {
    final seen = <ContentMatch>[this];

    Fragment? search(ContentMatch match, List<NodeType> types) {
      final finished = match.matchFragment(after, startIndex);
      if (finished != null && (!toEnd || finished.validEnd)) {
        return Fragment.from(types.map((type) => type.createAndFill()!).toList());
      }

      for (var index = 0; index < match.next.length; index++) {
        final type = match.next[index].type;
        final nextMatch = match.next[index].next;
        if (!(type.isText || type.hasRequiredAttrs()) && !seen.contains(nextMatch)) {
          seen.add(nextMatch);
          final found = search(nextMatch, [...types, type]);
          if (found != null) {
            return found;
          }
        }
      }
      return null;
    }

    return search(this, []);
  }

  /// Find a set of wrapping node types that would allow a node of the given
  /// type to appear at this position.
  List<NodeType>? findWrapping(NodeType target) {
    for (var index = 0; index < wrapCache.length; index += 2) {
      if (identical(wrapCache[index], target)) {
        return wrapCache[index + 1] as List<NodeType>?;
      }
    }
    final computed = computeWrapping(target);
    wrapCache.add(target);
    wrapCache.add(computed);
    return computed;
  }

  /// @internal
  List<NodeType>? computeWrapping(NodeType target) {
    final seen = <String, bool>{};
    final active = <_Active>[_Active(this, null, null)];
    while (active.isNotEmpty) {
      final current = active.removeAt(0);
      final match = current.match;
      if (match.matchType(target) != null) {
        final result = <NodeType>[];
        for (_Active? step = current; step != null && step.type != null; step = step.via) {
          result.add(step.type!);
        }
        return result.reversed.toList();
      }
      for (var index = 0; index < match.next.length; index++) {
        final type = match.next[index].type;
        final nextMatch = match.next[index].next;
        if (!type.isLeaf &&
            !type.hasRequiredAttrs() &&
            !seen.containsKey(type.name) &&
            (current.type == null || nextMatch.validEnd)) {
          active.add(_Active(type.contentMatch, type, current));
          seen[type.name] = true;
        }
      }
    }
    return null;
  }

  /// The number of outgoing edges this node has in the finite automaton.
  int get edgeCount => next.length;

  /// Get the nth outgoing edge from this node in the finite automaton.
  MatchEdge edge(int index) {
    if (index >= next.length) {
      throw RangeError("There's no ${index}th edge in this content match");
    }
    return next[index];
  }

  /// @internal
  @override
  String toString() {
    final seen = <ContentMatch>[];
    void scan(ContentMatch match) {
      seen.add(match);
      for (var index = 0; index < match.next.length; index++) {
        if (!seen.contains(match.next[index].next)) {
          scan(match.next[index].next);
        }
      }
    }

    scan(this);
    final buffer = <String>[];
    for (var stateIndex = 0; stateIndex < seen.length; stateIndex++) {
      final match = seen[stateIndex];
      var line = "$stateIndex${match.validEnd ? "*" : " "} ";
      for (var edgeIndex = 0; edgeIndex < match.next.length; edgeIndex++) {
        line +=
            "${edgeIndex != 0 ? ", " : ""}${match.next[edgeIndex].type.name}->${seen.indexOf(match.next[edgeIndex].next)}";
      }
      buffer.add(line);
    }
    return buffer.join("\n");
  }

  /// @internal
  static final ContentMatch empty = ContentMatch(true);
}

class _Active {
  _Active(this.match, this.type, this.via);

  final ContentMatch match;
  final NodeType? type;
  final _Active? via;
}

class _TokenStream {
  _TokenStream(this.string, this.nodeTypes) : tokens = _tokenize(string);

  final String string;
  final Map<String, NodeType> nodeTypes;
  final List<String> tokens;
  bool? inline;
  int pos = 0;

  String? get next => pos < tokens.length ? tokens[pos] : null;

  bool eat(String token) {
    if (next == token) {
      pos++;
      return true;
    }
    return false;
  }

  Never err(String message) {
    throw FormatException("$message (in content expression '$string')");
  }
}

List<String> _tokenize(String string) {
  final tokens = <String>[];
  var index = 0;
  while (index < string.length) {
    final code = string.codeUnitAt(index);
    if (_isWhitespace(code)) {
      index++;
      continue;
    }
    if (_isWordChar(code)) {
      final start = index;
      while (index < string.length && _isWordChar(string.codeUnitAt(index))) {
        index++;
      }
      tokens.add(string.substring(start, index));
    } else {
      tokens.add(string[index]);
      index++;
    }
  }
  return tokens;
}

bool _isWhitespace(int code) => code == 0x20 || code == 0x09 || code == 0x0A || code == 0x0D || code == 0x0C;

bool _isWordChar(int code) =>
    (code >= 0x30 && code <= 0x39) || // 0-9
    (code >= 0x41 && code <= 0x5A) || // A-Z
    (code >= 0x61 && code <= 0x7A) || // a-z
    code == 0x5F; // _

class _Expr {
  _Expr(this.type, {this.exprs, this.expr, this.min, this.max, this.value});

  final String type;
  final List<_Expr>? exprs;
  final _Expr? expr;
  final int? min;
  final int? max;
  final NodeType? value;
}

_Expr _parseExpr(_TokenStream stream) {
  final exprs = <_Expr>[];
  do {
    exprs.add(_parseExprSeq(stream));
  } while (stream.eat("|"));
  return exprs.length == 1 ? exprs[0] : _Expr("choice", exprs: exprs);
}

_Expr _parseExprSeq(_TokenStream stream) {
  final exprs = <_Expr>[];
  do {
    exprs.add(_parseExprSubscript(stream));
  } while (stream.next != null && stream.next != ")" && stream.next != "|");
  return exprs.length == 1 ? exprs[0] : _Expr("seq", exprs: exprs);
}

_Expr _parseExprSubscript(_TokenStream stream) {
  var expr = _parseExprAtom(stream);
  for (;;) {
    if (stream.eat("+")) {
      expr = _Expr("plus", expr: expr);
    } else if (stream.eat("*")) {
      expr = _Expr("star", expr: expr);
    } else if (stream.eat("?")) {
      expr = _Expr("opt", expr: expr);
    } else if (stream.eat("{")) {
      expr = _parseExprRange(stream, expr);
    } else {
      break;
    }
  }
  return expr;
}

int _parseNum(_TokenStream stream) {
  final token = stream.next;
  if (token == null || RegExp(r'\D').hasMatch(token)) {
    stream.err("Expected number, got '${stream.next}'");
  }
  final result = int.parse(token);
  stream.pos++;
  return result;
}

_Expr _parseExprRange(_TokenStream stream, _Expr expr) {
  final min = _parseNum(stream);
  var max = min;
  if (stream.eat(",")) {
    if (stream.next != "}") {
      max = _parseNum(stream);
    } else {
      max = -1;
    }
  }
  if (!stream.eat("}")) {
    stream.err("Unclosed braced range");
  }
  return _Expr("range", min: min, max: max, expr: expr);
}

List<NodeType> _resolveName(_TokenStream stream, String name) {
  final types = stream.nodeTypes;
  final type = types[name];
  if (type != null) {
    return [type];
  }
  final result = <NodeType>[];
  for (final typeName in types.keys) {
    final candidate = types[typeName]!;
    if (candidate.isInGroup(name)) {
      result.add(candidate);
    }
  }
  if (result.isEmpty) {
    stream.err("No node type or group '$name' found");
  }
  return result;
}

_Expr _parseExprAtom(_TokenStream stream) {
  if (stream.eat("(")) {
    final expr = _parseExpr(stream);
    if (!stream.eat(")")) {
      stream.err("Missing closing paren");
    }
    return expr;
  } else if (stream.next != null && !RegExp(r'\W').hasMatch(stream.next!)) {
    final exprs = _resolveName(stream, stream.next!).map((type) {
      if (stream.inline == null) {
        stream.inline = type.isInline;
      } else if (stream.inline != type.isInline) {
        stream.err("Mixing inline and block content");
      }
      return _Expr("name", value: type);
    }).toList();
    stream.pos++;
    return exprs.length == 1 ? exprs[0] : _Expr("choice", exprs: exprs);
  } else {
    stream.err("Unexpected token '${stream.next}'");
  }
}

class _Edge {
  _Edge(this.term, this.to);

  NodeType? term;
  int? to;
}

List<List<_Edge>> _nfa(_Expr expr) {
  final nfa = <List<_Edge>>[[]];

  int node() {
    nfa.add([]);
    return nfa.length - 1;
  }

  _Edge edge(int from, [int? to, NodeType? term]) {
    final result = _Edge(term, to);
    nfa[from].add(result);
    return result;
  }

  void connect(List<_Edge> edges, int to) {
    for (final outgoing in edges) {
      outgoing.to = to;
    }
  }

  List<_Edge> compile(_Expr expr, int from) {
    switch (expr.type) {
      case "choice":
        final edges = <_Edge>[];
        for (final child in expr.exprs!) {
          edges.addAll(compile(child, from));
        }
        return edges;
      case "seq":
        for (var index = 0; ; index++) {
          final next = compile(expr.exprs![index], from);
          if (index == expr.exprs!.length - 1) {
            return next;
          }
          from = node();
          connect(next, from);
        }
      case "star":
        final loop = node();
        edge(from, loop);
        connect(compile(expr.expr!, loop), loop);
        return [edge(loop)];
      case "plus":
        final loop = node();
        connect(compile(expr.expr!, from), loop);
        connect(compile(expr.expr!, loop), loop);
        return [edge(loop)];
      case "opt":
        return [edge(from), ...compile(expr.expr!, from)];
      case "range":
        var current = from;
        for (var index = 0; index < expr.min!; index++) {
          final next = node();
          connect(compile(expr.expr!, current), next);
          current = next;
        }
        if (expr.max == -1) {
          connect(compile(expr.expr!, current), current);
        } else {
          for (var index = expr.min!; index < expr.max!; index++) {
            final next = node();
            edge(current, next);
            connect(compile(expr.expr!, current), next);
            current = next;
          }
        }
        return [edge(current)];
      case "name":
        return [edge(from, null, expr.value)];
      default:
        throw StateError("Unknown expr type");
    }
  }

  connect(compile(expr, 0), node());
  return nfa;
}

List<int> _nullFrom(List<List<_Edge>> nfa, int start) {
  final result = <int>[];

  void scan(int node) {
    final edges = nfa[node];
    if (edges.length == 1 && edges[0].term == null) {
      scan(edges[0].to!);
      return;
    }
    result.add(node);
    for (var index = 0; index < edges.length; index++) {
      final term = edges[index].term;
      final to = edges[index].to;
      if (term == null && !result.contains(to)) {
        scan(to!);
      }
    }
  }

  scan(start);
  result.sort((a, b) => b - a);
  return result;
}

ContentMatch _dfa(List<List<_Edge>> nfa) {
  final labeled = <String, ContentMatch>{};

  ContentMatch explore(List<int> states) {
    final edgeGroups = <List<Object>>[];
    for (final node in states) {
      for (final edge in nfa[node]) {
        final term = edge.term;
        if (term == null) {
          continue;
        }
        List<int>? stateSet;
        for (var index = 0; index < edgeGroups.length; index++) {
          if (identical(edgeGroups[index][0], term)) {
            stateSet = edgeGroups[index][1] as List<int>;
          }
        }
        for (final reached in _nullFrom(nfa, edge.to!)) {
          if (stateSet == null) {
            stateSet = <int>[];
            edgeGroups.add([term, stateSet]);
          }
          if (!stateSet.contains(reached)) {
            stateSet.add(reached);
          }
        }
      }
    }
    final state = ContentMatch(states.contains(nfa.length - 1));
    labeled[states.join(",")] = state;
    for (var index = 0; index < edgeGroups.length; index++) {
      final childStates = (edgeGroups[index][1] as List<int>)..sort((a, b) => b - a);
      final key = childStates.join(",");
      state.next.add(MatchEdge(edgeGroups[index][0] as NodeType, labeled[key] ?? explore(childStates)));
    }
    return state;
  }

  return explore(_nullFrom(nfa, 0));
}

void _checkForDeadEnds(ContentMatch match, _TokenStream stream) {
  final work = <ContentMatch>[match];
  for (var index = 0; index < work.length; index++) {
    final state = work[index];
    var dead = !state.validEnd;
    final nodes = <String>[];
    for (var edgeIndex = 0; edgeIndex < state.next.length; edgeIndex++) {
      final type = state.next[edgeIndex].type;
      final nextMatch = state.next[edgeIndex].next;
      nodes.add(type.name);
      if (dead && !(type.isText || type.hasRequiredAttrs())) {
        dead = false;
      }
      if (!work.contains(nextMatch)) {
        work.add(nextMatch);
      }
    }
    if (dead) {
      stream.err(
        "Only non-generatable nodes (${nodes.join(", ")}) in a required position (see https://prosemirror.net/docs/guide/#generatable)",
      );
    }
  }
}
