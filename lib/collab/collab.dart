library;

import 'dart:math' as math;

import 'package:prosemirror/src/state/plugin.dart';
import 'package:prosemirror/src/state/selection.dart';
import 'package:prosemirror/src/state/state.dart';
import 'package:prosemirror/src/state/transaction.dart';
import 'package:prosemirror/src/transform/step.dart';
import 'package:prosemirror/src/transform/transform.dart';

/// A collaborative step with the information needed to rebase it.
typedef RebaseableStep = ({Step step, Step inverted, Transform origin});

/// Configuration for [collab].
class CollabConfig {
  /// Creates collaboration configuration.
  const CollabConfig({this.version = 0, this.clientID});

  /// The starting version number for the collaborative editing session.
  final int version;

  /// This client's ID, used to distinguish its changes from other clients.
  final Object? clientID;
}

/// Options for [receiveTransaction].
class ReceiveTransactionOptions {
  /// Creates receive-transaction options.
  const ReceiveTransactionOptions({this.mapSelectionBackward = false});

  /// Whether to map text-selection sides backward through received steps.
  final bool mapSelectionBackward;
}

/// The unconfirmed local steps that should be sent to the authority.
class SendableSteps {
  /// Creates sendable step data.
  SendableSteps({
    required this.version,
    required Iterable<Step> steps,
    required this.clientID,
    required Iterable<Transaction> origins,
  }) : steps = List<Step>.unmodifiable(steps),
       origins = List<Transaction>.unmodifiable(origins);

  /// The version at which these steps apply.
  final int version;

  /// The steps waiting to be confirmed by the authority.
  final List<Step> steps;

  /// The local client ID that produced the steps.
  final Object clientID;

  /// The original transactions that produced each step.
  final List<Transaction> origins;
}

/// Creates a plugin that enables the collaborative editing framework.
Plugin collab([CollabConfig config = const CollabConfig()]) {
  final resolvedConfig = _ResolvedCollabConfig(
    version: config.version,
    clientID: config.clientID ?? math.Random().nextInt(0xffffffff),
  );

  return Plugin(
    PluginSpec(
      key: _collabKey,
      state: _collabStateField,
      extra: <String, Object?>{
        "config": resolvedConfig,
        "historyPreserveItems": true,
      },
    ),
  );
}

/// Undo local steps, apply steps from the authority, and redo local steps.
List<RebaseableStep> rebaseSteps(
  List<RebaseableStep> steps,
  List<Step> over,
  Transform transform,
) {
  for (var stepIndex = steps.length - 1; stepIndex >= 0; stepIndex--) {
    transform.step(steps[stepIndex].inverted);
  }
  for (var stepIndex = 0; stepIndex < over.length; stepIndex++) {
    transform.step(over[stepIndex]);
  }

  final result = <RebaseableStep>[];
  for (
    var stepIndex = 0, mapFrom = steps.length;
    stepIndex < steps.length;
    stepIndex++
  ) {
    final mapped = steps[stepIndex].step.map(transform.mapping.slice(mapFrom));
    mapFrom--;
    if (mapped != null && transform.maybeStep(mapped).failed == null) {
      transform.mapping.setMirror(mapFrom, transform.steps.length - 1);
      result.add((
        step: mapped,
        inverted: mapped.invert(transform.docs[transform.docs.length - 1]),
        origin: steps[stepIndex].origin,
      ));
    }
  }
  return result;
}

/// Creates a transaction that integrates steps received from the authority.
Transaction receiveTransaction(
  EditorState state,
  List<Step> steps,
  List<Object> clientIDs, [
  ReceiveTransactionOptions options = const ReceiveTransactionOptions(),
]) {
  final collabState = _requireCollabState(state);
  final version = collabState.version + steps.length;
  final ourID = _requireCollabConfig(state).clientID;

  var ours = 0;
  while (ours < clientIDs.length && clientIDs[ours] == ourID) {
    ours++;
  }

  var unconfirmed = collabState.unconfirmed.sublist(ours);
  final remoteSteps = ours > 0 ? steps.sublist(ours) : steps;

  if (remoteSteps.isEmpty) {
    return state.tr.setMeta(_collabKey, _CollabState(version, unconfirmed));
  }

  final rebasedCount = unconfirmed.length;
  final transaction = state.tr;
  if (rebasedCount > 0) {
    unconfirmed = rebaseSteps(unconfirmed, remoteSteps, transaction);
  } else {
    for (var stepIndex = 0; stepIndex < remoteSteps.length; stepIndex++) {
      transaction.step(remoteSteps[stepIndex]);
    }
    unconfirmed = <RebaseableStep>[];
  }

  if (options.mapSelectionBackward && state.selection is TextSelection) {
    _mapTextSelectionBackward(state, transaction);
  }

  return transaction
      .setMeta("rebased", rebasedCount)
      .setMeta("addToHistory", false)
      .setMeta(_collabKey, _CollabState(version, unconfirmed));
}

/// Provides data describing unconfirmed local steps to send.
SendableSteps? sendableSteps(EditorState state) {
  final collabState = _requireCollabState(state);
  if (collabState.unconfirmed.isEmpty) {
    return null;
  }

  return SendableSteps(
    version: collabState.version,
    steps: collabState.unconfirmed.map(_stepFromRebaseable),
    clientID: _requireCollabConfig(state).clientID,
    origins: collabState.unconfirmed.map(_originFromRebaseable),
  );
}

/// Gets the version up to which the collab plugin has synced.
int getVersion(EditorState state) {
  return _requireCollabState(state).version;
}

final PluginKey _collabKey = PluginKey("collab");
final StateField _collabStateField = StateField(
  init: _initCollabState,
  apply: _applyCollabState,
);

Object? _initCollabState(EditorStateConfig config, EditorState instance) {
  return _CollabState(
    _requireCollabConfig(instance).version,
    <RebaseableStep>[],
  );
}

Object? _applyCollabState(
  Transaction transaction,
  Object? value,
  EditorState oldState,
  EditorState newState,
) {
  final newStateMeta = transaction.getMeta(_collabKey);
  if (newStateMeta is _CollabState) {
    return newStateMeta;
  }

  final collabState = value as _CollabState;
  if (transaction.docChanged) {
    return _CollabState(collabState.version, [
      ...collabState.unconfirmed,
      ..._unconfirmedFrom(transaction),
    ]);
  }
  return collabState;
}

List<RebaseableStep> _unconfirmedFrom(Transaction transaction) {
  return [
    for (var stepIndex = 0; stepIndex < transaction.steps.length; stepIndex++)
      (
        step: transaction.steps[stepIndex],
        inverted: transaction.steps[stepIndex].invert(
          transaction.docs[stepIndex],
        ),
        origin: transaction,
      ),
  ];
}

void _mapTextSelectionBackward(EditorState state, Transaction transaction) {
  final selection = state.selection;
  transaction.setSelection(
    TextSelection.between(
      transaction.doc.resolve(transaction.mapping.map(selection.anchor, -1)),
      transaction.doc.resolve(transaction.mapping.map(selection.head, -1)),
      -1,
    ),
  );
}

_CollabState _requireCollabState(EditorState state) {
  final collabState = _collabKey.getState(state);
  if (collabState is! _CollabState) {
    throw StateError("The collab plugin is not enabled");
  }
  return collabState;
}

_ResolvedCollabConfig _requireCollabConfig(EditorState state) {
  final plugin = _collabKey.get(state);
  final config = plugin?.spec.extra["config"];
  if (config is! _ResolvedCollabConfig) {
    throw StateError("The collab plugin is not enabled");
  }
  return config;
}

Step _stepFromRebaseable(RebaseableStep step) {
  return step.step;
}

Transaction _originFromRebaseable(RebaseableStep step) {
  return step.origin as Transaction;
}

class _ResolvedCollabConfig {
  _ResolvedCollabConfig({required this.version, required this.clientID});

  final int version;
  final Object clientID;
}

class _CollabState {
  _CollabState(this.version, this.unconfirmed);

  final int version;
  final List<RebaseableStep> unconfirmed;
}
