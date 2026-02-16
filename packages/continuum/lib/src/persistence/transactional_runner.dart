import 'dart:async';

import 'commit_handler.dart';
import 'continuum_store.dart';
import 'session.dart';

/// Zone key for storing the ambient session.
final _sessionKey = Object();

/// Zone-based unit-of-work manager for session lifecycle.
///
/// Opens a session, executes a user action within a zone-scoped
/// session, auto-commits on success, and publishes committed events
/// through an optional [CommitHandler].
///
/// Each [runAsync] invocation creates a new zone with its own
/// independent session. Two concurrent calls get separate sessions
/// with no shared state. Nested [runAsync] calls create independent
/// transactions.
final class TransactionalRunner {
  /// The store used to open sessions.
  final ContinuumStore _store;

  /// Optional handler for post-commit event publishing.
  final CommitHandler? _commitHandler;

  /// Creates a transactional runner with the given [store] and
  /// optional [commitHandler].
  ///
  /// If no [commitHandler] is provided, events are persisted but
  /// no post-commit publishing occurs.
  TransactionalRunner({
    required ContinuumStore store,
    CommitHandler? commitHandler,
  }) : _store = store,
       _commitHandler = commitHandler;

  /// Executes [action] within a zone-scoped session.
  ///
  /// Opens a new session, places it in a zone value so it can be
  /// accessed via [currentSession], executes the action, auto-commits
  /// via [ContinuumSession.saveChangesAsync], and calls the configured
  /// [CommitHandler] if events were committed.
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

    // Auto-commit pending events after the action completes successfully.
    final committedEvents = await session.saveChangesAsync();

    // Publish committed events through the handler if configured and
    // the commit was non-empty.
    if (_commitHandler != null && committedEvents.isNotEmpty) {
      await _commitHandler.onCommitAsync(committedEvents);
    }

    return result;
  }

  /// Retrieves the ambient session from the current zone.
  ///
  /// Must be called inside a [runAsync] scope. Throws [StateError]
  /// if no ambient session exists (i.e., called outside [runAsync]).
  static ContinuumSession get currentSession {
    final session = Zone.current[_sessionKey] as ContinuumSession?;
    if (session == null) {
      throw StateError(
        'No ambient ContinuumSession found. '
        'TransactionalRunner.currentSession must be called inside runAsync.',
      );
    }
    return session;
  }

  /// Retrieves the ambient session from the current zone, or `null`
  /// if no ambient session exists.
  ///
  /// Safe to call outside [runAsync] — returns `null` instead of throwing.
  static ContinuumSession? get currentSessionOrNull {
    return Zone.current[_sessionKey] as ContinuumSession?;
  }
}
