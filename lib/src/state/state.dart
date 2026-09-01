import 'package:prosemirror/src/model/mark.dart';
import 'package:prosemirror/src/model/node.dart';
import 'package:prosemirror/src/model/schema.dart';

import 'package:prosemirror/src/state/plugin.dart';
import 'package:prosemirror/src/state/selection.dart';
import 'package:prosemirror/src/state/transaction.dart';

class _FieldDesc {
  _FieldDesc(this.name, StateField desc) : init = desc.init, apply = desc.apply;

  final String name;
  final Object? Function(EditorStateConfig config, EditorState instance) init;
  final Object? Function(Transaction tr, Object? value, EditorState oldState, EditorState newState) apply;
}

final List<_FieldDesc> _baseFields = <_FieldDesc>[
  _FieldDesc(
    "doc",
    StateField(
      init: (config, instance) => config.doc ?? config.schema!.topNodeType.createAndFill(),
      apply: (tr, value, oldState, newState) => tr.doc,
    ),
  ),
  _FieldDesc(
    "selection",
    StateField(
      init: (config, instance) => config.selection ?? Selection.atStart(instance.doc),
      apply: (tr, value, oldState, newState) => tr.selection,
    ),
  ),
  _FieldDesc(
    "storedMarks",
    StateField(
      init: (config, instance) => config.storedMarks,
      apply: (tr, value, oldState, newState) {
        final selection = newState.selection;
        return (selection is TextSelection && selection.$cursor != null) ? tr.storedMarks : null;
      },
    ),
  ),
  _FieldDesc(
    "scrollToSelection",
    StateField(
      init: (config, instance) => 0,
      apply: (tr, prev, oldState, newState) => tr.scrolledIntoView ? (prev as int) + 1 : prev,
    ),
  ),
];

/// Object wrapping the part of a state object that stays the same across
/// transactions. Stored in the state's `config` property.
class Configuration {
  Configuration(this.schema, [List<Plugin>? plugins]) {
    _fields = List<_FieldDesc>.from(_baseFields);
    if (plugins != null) {
      for (final plugin in plugins) {
        if (pluginsByKey.containsKey(plugin.key)) {
          throw RangeError("Adding different instances of a keyed plugin (${plugin.key})");
        }
        this.plugins.add(plugin);
        pluginsByKey[plugin.key] = plugin;
        if (plugin.spec.state != null) {
          _fields.add(_FieldDesc(plugin.key, plugin.spec.state!));
        }
      }
    }
  }

  final Schema schema;
  late final List<_FieldDesc> _fields;
  final List<Plugin> plugins = <Plugin>[];
  final Map<String, Plugin> pluginsByKey = <String, Plugin>{};
}

/// The type of object passed to [EditorState.create].
class EditorStateConfig {
  /// Create an editor state config.
  EditorStateConfig({this.schema, this.doc, this.selection, this.storedMarks, this.plugins});

  /// The schema to use (only relevant if no `doc` is specified).
  final Schema? schema;

  /// The starting document. Either this or `schema` must be provided.
  final Node? doc;

  /// A valid selection in the document.
  final Selection? selection;

  /// The initial set of stored marks.
  final List<Mark>? storedMarks;

  /// The plugins that should be active in this state.
  final List<Plugin>? plugins;
}

/// The state of a ProseMirror editor is represented by an object of this
/// type. A state is a persistent data structure—it isn't updated, but
/// rather a new state value is computed from an old one using the [apply]
/// method.
///
/// A state holds a number of built-in fields, and plugins can define
/// additional fields.
class EditorState {
  /// @internal
  EditorState(this.config);

  /// @internal
  final Configuration config;

  /// The current document.
  late Node doc;

  /// The selection.
  late Selection selection;

  /// A set of marks to apply to the next input. Will be null when no
  /// explicit marks have been set.
  List<Mark>? storedMarks;

  /// The number of times scroll-into-view has been requested. Kept as a
  /// base field to mirror the upstream implementation.
  int scrollToSelection = 0;

  final Map<String, Object?> _pluginFields = <String, Object?>{};

  /// Read a plugin field value by plugin key.
  Object? fieldValue(String key) => _pluginFields[key];

  void _setField(String name, Object? value) {
    switch (name) {
      case "doc":
        doc = value as Node;
        break;
      case "selection":
        selection = value as Selection;
        break;
      case "storedMarks":
        storedMarks = value as List<Mark>?;
        break;
      case "scrollToSelection":
        scrollToSelection = value as int;
        break;
      default:
        _pluginFields[name] = value;
    }
  }

  Object? _getField(String name) {
    switch (name) {
      case "doc":
        return doc;
      case "selection":
        return selection;
      case "storedMarks":
        return storedMarks;
      case "scrollToSelection":
        return scrollToSelection;
      default:
        return _pluginFields[name];
    }
  }

  bool _hasField(String name) {
    switch (name) {
      case "doc":
      case "selection":
      case "storedMarks":
      case "scrollToSelection":
        return true;
      default:
        return _pluginFields.containsKey(name);
    }
  }

  /// The schema of the state's document.
  Schema get schema => config.schema;

  /// The plugins that are active in this state.
  List<Plugin> get plugins => config.plugins;

  /// Apply the given transaction to produce a new state.
  EditorState apply(Transaction tr) {
    return applyTransaction(tr).state;
  }

  /// @internal
  bool filterTransaction(Transaction tr, [int ignore = -1]) {
    for (var index = 0; index < config.plugins.length; index++) {
      if (index != ignore) {
        final plugin = config.plugins[index];
        final filter = plugin.spec.filterTransaction;
        if (filter != null && !filter(tr, this)) {
          return false;
        }
      }
    }
    return true;
  }

  /// Verbose variant of [apply] that returns the precise transactions that
  /// were applied along with the new state.
  ({EditorState state, List<Transaction> transactions}) applyTransaction(Transaction rootTr) {
    if (!filterTransaction(rootTr)) {
      return (state: this, transactions: <Transaction>[]);
    }

    final trs = <Transaction>[rootTr];
    var newState = applyInner(rootTr);
    List<({EditorState state, int n})>? seen;
    // This loop repeatedly gives plugins a chance to respond to
    // transactions as new transactions are added, making sure to only pass
    // the transactions the plugin did not see before.
    for (;;) {
      var haveNew = false;
      for (var index = 0; index < config.plugins.length; index++) {
        final plugin = config.plugins[index];
        final append = plugin.spec.appendTransaction;
        if (append != null) {
          final n = seen != null ? seen[index].n : 0;
          final oldState = seen != null ? seen[index].state : this;
          final tr = n < trs.length ? append(n != 0 ? trs.sublist(n) : trs, oldState, newState) : null;
          if (tr != null && newState.filterTransaction(tr, index)) {
            tr.setMeta("appendedTransaction", rootTr);
            if (seen == null) {
              seen = <({EditorState state, int n})>[];
              for (var otherIndex = 0; otherIndex < config.plugins.length; otherIndex++) {
                seen.add(otherIndex < index ? (state: newState, n: trs.length) : (state: this, n: 0));
              }
            }
            trs.add(tr);
            newState = newState.applyInner(tr);
            haveNew = true;
          }
          if (seen != null) {
            seen[index] = (state: newState, n: trs.length);
          }
        }
      }
      if (!haveNew) {
        return (state: newState, transactions: trs);
      }
    }
  }

  /// @internal
  EditorState applyInner(Transaction tr) {
    if (!tr.before.eq(doc)) {
      throw RangeError("Applying a mismatched transaction");
    }
    final newInstance = EditorState(config);
    final fields = config._fields;
    for (var index = 0; index < fields.length; index++) {
      final field = fields[index];
      newInstance._setField(field.name, field.apply(tr, _getField(field.name), this, newInstance));
    }
    return newInstance;
  }

  /// Accessor that constructs and returns a new transaction from this
  /// state.
  Transaction get tr => Transaction(this);

  /// Create a new state.
  static EditorState create(EditorStateConfig config) {
    final schema = config.doc != null ? config.doc!.type.schema : config.schema!;
    final configuration = Configuration(schema, config.plugins);
    final instance = EditorState(configuration);
    for (var index = 0; index < configuration._fields.length; index++) {
      instance._setField(configuration._fields[index].name, configuration._fields[index].init(config, instance));
    }
    return instance;
  }

  /// Create a new state based on this one, but with an adjusted set of
  /// active plugins. State fields that exist in both sets of plugins are
  /// kept unchanged. Those that no longer exist are dropped, and those that
  /// are new are initialized using their [StateField.init] method.
  EditorState reconfigure({List<Plugin>? plugins}) {
    final configuration = Configuration(schema, plugins);
    final fields = configuration._fields;
    final instance = EditorState(configuration);
    final config = EditorStateConfig(plugins: plugins);
    for (var index = 0; index < fields.length; index++) {
      final name = fields[index].name;
      instance._setField(name, _hasField(name) ? _getField(name) : fields[index].init(config, instance));
    }
    return instance;
  }

  /// Serialize this state to JSON. If you want to serialize the state of
  /// plugins, pass an object mapping property names to use in the resulting
  /// JSON object to plugin objects.
  Map<String, Object?> toJSON([Object? pluginFields]) {
    final result = <String, Object?>{"doc": doc.toJSON(), "selection": selection.toJSON()};
    if (storedMarks != null) {
      result["storedMarks"] = storedMarks!.map((mark) => mark.toJSON()).toList();
    }
    if (pluginFields is Map<String, Plugin>) {
      pluginFields.forEach((prop, plugin) {
        if (prop == "doc" || prop == "selection") {
          throw RangeError("The JSON fields `doc` and `selection` are reserved");
        }
        final state = plugin.spec.state;
        if (state != null && state.toJSON != null) {
          result[prop] = state.toJSON!(fieldValue(plugin.key));
        }
      });
    }
    return result;
  }

  /// Deserialize a JSON representation of a state. `config` should have at
  /// least a `schema` field, and should contain array of plugins to
  /// initialize the state with. `pluginFields` can be used to deserialize
  /// the state of plugins.
  static EditorState fromJSON(
    EditorStateConfig config,
    Map<String, Object?> json, [
    Map<String, Plugin>? pluginFields,
  ]) {
    if (config.schema == null) {
      throw RangeError("Required config field 'schema' missing");
    }
    final configuration = Configuration(config.schema!, config.plugins);
    final instance = EditorState(configuration);
    for (final field in configuration._fields) {
      if (field.name == "doc") {
        instance.doc = Node.fromJSON(config.schema!, json["doc"]);
      } else if (field.name == "selection") {
        instance.selection = Selection.fromJSON(instance.doc, json["selection"] as Map<String, Object?>);
      } else if (field.name == "storedMarks") {
        if (json["storedMarks"] != null) {
          instance.storedMarks = (json["storedMarks"] as List)
              .map((mark) => config.schema!.markFromJSON(mark))
              .toList();
        }
      } else {
        var handled = false;
        if (pluginFields != null) {
          for (final prop in pluginFields.keys) {
            final plugin = pluginFields[prop]!;
            final state = plugin.spec.state;
            if (plugin.key == field.name && state != null && state.fromJSON != null && json.containsKey(prop)) {
              // This field belongs to a plugin mapped to a JSON field, read
              // it from there.
              instance._setField(field.name, state.fromJSON!(config, json[prop], instance));
              handled = true;
              break;
            }
          }
        }
        if (!handled) {
          instance._setField(field.name, field.init(config, instance));
        }
      }
    }
    return instance;
  }
}
