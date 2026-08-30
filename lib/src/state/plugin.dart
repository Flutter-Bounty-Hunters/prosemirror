import 'state.dart';
import 'transaction.dart';

/// This is the type passed to the [Plugin] constructor. It provides a
/// definition for a plugin.
class PluginSpec {
  /// Create a plugin spec.
  PluginSpec({
    this.props,
    this.state,
    this.key,
    this.view,
    this.filterTransaction,
    this.appendTransaction,
    Map<String, Object?>? extra,
  }) : extra = extra ?? <String, Object?>{};

  /// The view props added by this plugin. Props that are functions will be
  /// bound to have the plugin instance as their receiver.
  final Map<String, Object?>? props;

  /// Allows a plugin to define a state field, an extra slot in the state
  /// object in which it can keep its own data.
  final StateField? state;

  /// Can be used to make this a keyed plugin.
  final PluginKey? key;

  /// When the plugin needs to interact with the editor view, use this
  /// field. `EditorView` is treated as an opaque placeholder in this port.
  final PluginView Function(Object? view)? view;

  /// When present, this will be called before a transaction is applied by
  /// the state, allowing the plugin to cancel it (by returning false).
  final bool Function(Transaction tr, EditorState state)? filterTransaction;

  /// Allows the plugin to append another transaction to be applied after
  /// the given array of transactions.
  final Transaction? Function(
    List<Transaction> transactions,
    EditorState oldState,
    EditorState newState,
  )?
  appendTransaction;

  /// Additional properties allowed on plugin specs, reachable via
  /// [Plugin.spec].
  final Map<String, Object?> extra;
}

/// A stateful object that can be installed in an editor by a plugin.
class PluginView {
  /// Create a plugin view.
  PluginView({this.update, this.destroy});

  /// Called whenever the view's state is updated.
  final void Function(Object? view, EditorState prevState)? update;

  /// Called when the view is destroyed or receives a state with different
  /// plugins.
  final void Function()? destroy;
}

Map<String, Object?> _bindProps(
  Map<String, Object?> obj,
  Plugin self,
  Map<String, Object?> target,
) {
  obj.forEach((prop, value) {
    if (value is Function) {
      target[prop] = () => (value as dynamic)(self);
    } else {
      target[prop] = value;
    }
  });
  return target;
}

/// Plugins bundle functionality that can be added to an editor. They are
/// part of the editor state and may influence that state and the view that
/// contains it.
class Plugin {
  /// Create a plugin.
  Plugin(this.spec) {
    final props = spec.props;
    if (props != null) {
      _bindProps(props, this, this.props);
    }
    key = spec.key != null ? spec.key!.key : _createKey("plugin");
  }

  /// The plugin's spec object.
  final PluginSpec spec;

  /// The props exported by this plugin.
  final Map<String, Object?> props = <String, Object?>{};

  /// @internal
  late final String key;

  /// Extract the plugin's state field from an editor state.
  Object? getState(EditorState state) => state.fieldValue(key);
}

/// A plugin spec may provide a state field (under its [PluginSpec.state]
/// property) of this type, which describes the state it wants to keep.
class StateField {
  /// Create a state field.
  StateField({
    required this.init,
    required this.apply,
    this.toJSON,
    this.fromJSON,
  });

  /// Initialize the value of the field. `config` will be the object passed
  /// to [EditorState.create]. Note that `instance` is a half-initialized
  /// state instance, and will not have values for plugin fields initialized
  /// after this one.
  final Object? Function(EditorStateConfig config, EditorState instance) init;

  /// Apply the given transaction to this state field, producing a new field
  /// value.
  final Object? Function(
    Transaction tr,
    Object? value,
    EditorState oldState,
    EditorState newState,
  )
  apply;

  /// Convert this field to JSON. Optional, can be left off to disable JSON
  /// serialization for the field.
  final Object? Function(Object? value)? toJSON;

  /// Deserialize the JSON representation of this field.
  final Object? Function(
    EditorStateConfig config,
    Object? value,
    EditorState state,
  )?
  fromJSON;
}

final Map<String, int> _keys = <String, int>{};

String _createKey(String name) {
  if (_keys.containsKey(name)) {
    final next = _keys[name]! + 1;
    _keys[name] = next;
    return "$name\$$next";
  }
  _keys[name] = 0;
  return "$name\$";
}

/// A key is used to tag plugins in a way that makes it possible to find
/// them, given an editor state. Assigning a key does mean only one plugin
/// of that type can be active in a state.
class PluginKey {
  /// Create a plugin key.
  PluginKey([String name = "key"]) : key = _createKey(name);

  /// @internal
  final String key;

  /// Get the active plugin with this key, if any, from an editor state.
  Plugin? get(EditorState state) => state.config.pluginsByKey[key];

  /// Get the plugin's state from an editor state.
  Object? getState(EditorState state) => state.fieldValue(key);
}
