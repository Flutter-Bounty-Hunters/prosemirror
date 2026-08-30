/// The public API of the `prosemirror-state` port.
library;

export 'selection.dart'
    show
        Selection,
        SelectionRange,
        TextSelection,
        NodeSelection,
        AllSelection,
        SelectionBookmark;
export 'transaction.dart' show Transaction, Command;
export 'state.dart' show EditorState, EditorStateConfig, Configuration;
export 'plugin.dart' show Plugin, PluginKey, PluginSpec, StateField, PluginView;
