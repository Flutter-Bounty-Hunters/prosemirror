/// The public API of the `prosemirror-state` port.
library;

export 'package:prosemirror/src/state/selection.dart'
    show
        Selection,
        SelectionRange,
        TextSelection,
        NodeSelection,
        AllSelection,
        SelectionBookmark;
export 'package:prosemirror/src/state/transaction.dart'
    show Transaction, Command;
export 'package:prosemirror/src/state/state.dart'
    show EditorState, EditorStateConfig, Configuration;
export 'package:prosemirror/src/state/plugin.dart'
    show Plugin, PluginKey, PluginSpec, StateField, PluginView;
