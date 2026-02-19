import 'dart:async';

import 'commit_handler.dart';
import 'session.dart';
import 'session_store.dart';

/// Zone key for storing the ambient session.
final _sessionKey = Object();

/// Zone-based unit-of-work manager for session lifecycle.
///
/// Opens a session, executes a user action within a zone-scoped
/// session, auto-commits on success, and publishes through an
/// optional [CommitHandler].
///
/// Each [runAsync] invocation creates a new zone with its own
/// independent session. Two concurrent calls get separate sessions
/// with no shared state. Nested [runAsync] calls create independent
/// transactions.
final class TransactionalRunner {
  /// The store used to open sessions.
  final SessionStore _store;

  /// Optional handler for post-commit side effects.
  final CommitHandler? _commitHandler;

  /// Creates a transactional runner with the given [store] and
  /// optional [commitHandler].
  ///
  /// If no [commitHandler] is provided, operations are persisted but
  /// no post-commit step occurs.
  TransactionalRunner({
    required SessionStore store,
    CommitHandler? commitHandler,
  }) : _store = store,
       _commitHandler = commitHandler;

  /// Executes [action] within a zone-scoped session.
  ///
  /// Opens a new session, places it in a zone value so it can be
  /// accessed via [currentSession], executes the action, auto-commits
  /// via [Session.saveChangesAsync], and calls the configured
  /// [CommitHandler] if present.
  ///
  /// Returns the action's result after commit and publish succeed.
  ///
  /// If the action throws, the session is abandoned without saving
  /// and the exception propagates to the caller.
  Future<T> runAsync<T>(Future<T> Function() action) async {
    // Open a fresh session for this transaction scope.
    final session = _store.openSession();

    // Execute the action in a zone with the session as an ambient value.
    final result = await runZoned(
      action,
      zoneValues: {_sessionKey: session},
    );

    // Auto-commit pending operations after the action completes
    // successfully. Returns a batch of committed operations grouped
    // by stream.
    final batch = await session.saveChangesAsync();

    // Publish through the handler if configured and operations were
    // actually committed. Empty batches are skipped per spec.
    if (_commitHandler != null && batch.isNotEmpty) {
      await _commitHandler.onCommitAsync(batch);
    }

    return result;
  }

  /// Retrieves the ambient session from the current zone.
  ///
  /// Must be called inside a [runAsync] scope. Throws [StateError]
  /// if no ambient session exists (i.e., called outside [runAsync]).
  static Session get currentSession {
    final session = Zone.current[_sessionKey] as Session?;
    if (session == null) {
      throw StateError(
        'No ambient Session found. '
        'TransactionalRunner.currentSession must be called inside runAsync.',
      );
    }
    return session;
  }

  /// Retrieves the ambient session from the current zone, or `null`
  /// if no ambient session exists.
  ///
  /// Safe to call outside [runAsync] — returns `null` instead of
  /// throwing.
  static Session? get currentSessionOrNull {
    return Zone.current[_sessionKey] as Session?;
  }
}
