import 'package:continuum/continuum.dart';

/// Adapter interface for state-based aggregate persistence.
///
/// Provides fetch/hydrate and persist operations against a backend
/// (REST API, GraphQL, database, etc.). Each adapter is typed to a
/// specific aggregate and is responsible for translating between
/// domain objects and backend representations.
abstract interface class AggregatePersistenceAdapter<TAggregate> {
  /// Loads and fully constructs an aggregate from the backend.
  ///
  /// The adapter is responsible for calling the backend, receiving the
  /// response, and constructing the aggregate. The session does not
  /// need to know how hydration works.
  ///
  /// Throws if the aggregate does not exist or the backend call fails.
  Future<TAggregate> fetchAsync(StreamId streamId);

  /// Persists changes for an aggregate to the backend.
  ///
  /// Receives the stream ID, the aggregate in its post-event state, and
  /// the list of pending operations. The adapter decides how to
  /// translate these into backend API calls (single PATCH, multiple
  /// requests, batch command, etc.).
  ///
  /// Must be all-or-nothing: either all changes for the given stream
  /// are persisted, or the method throws and no changes are committed.
  Future<void> persistAsync(
    StreamId streamId,
    TAggregate aggregate,
    List<Operation> pendingOperations,
  );
}
