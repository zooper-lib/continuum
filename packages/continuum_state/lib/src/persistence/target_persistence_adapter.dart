import 'package:continuum/continuum.dart';

/// Adapter interface for state-based target persistence.
///
/// Provides fetch/hydrate and persist operations against a backend
/// (REST API, GraphQL, database, etc.). Each adapter is typed to a
/// specific target and is responsible for translating between
/// domain objects and backend representations.
abstract interface class TargetPersistenceAdapter<TTarget> {
  /// Loads and fully constructs a target from the backend.
  ///
  /// The adapter is responsible for calling the backend, receiving the
  /// response, and constructing the target. The session does not
  /// need to know how hydration works.
  ///
  /// Throws if the target does not exist or the backend call fails.
  Future<TTarget> fetchAsync(StreamId streamId);

  /// Persists changes for a target to the backend.
  ///
  /// Receives the stream ID, the target in its post-operation state, and
  /// the list of pending operations. The adapter decides how to
  /// translate these into backend API calls (single PATCH, multiple
  /// requests, batch command, etc.).
  ///
  /// Must be all-or-nothing: either all changes for the given stream
  /// are persisted, or the method throws and no changes are committed.
  Future<void> persistAsync(
    StreamId streamId,
    TTarget target,
    List<Operation> pendingOperations,
  );

  /// Deletes a target from the backend.
  ///
  /// Removes the entity identified by [streamId] from the underlying
  /// store. Called during commit when a session marks a stream for
  /// deletion via [Session.deleteAsync].
  ///
  /// Must be idempotent: deleting a non-existent target should not
  /// throw. Throws on transient failures (network errors, etc.).
  Future<void> deleteAsync(StreamId streamId);
}