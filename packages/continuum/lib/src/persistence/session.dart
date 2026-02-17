import '../events/continuum_event.dart';
import '../identity/stream_id.dart';

/// Unit of work abstraction for aggregate operations.
///
/// A session tracks loaded aggregates and pending events, applying
/// changes optimistically and persisting them atomically on save.
///
/// Sessions are short-lived and should not be reused after [saveChangesAsync]
/// is called.
abstract interface class ContinuumSession {
  /// Loads an aggregate by its stream ID.
  ///
  /// Reconstructs the aggregate by loading stored events and replaying
  /// them through the generated dispatcher.
  ///
  /// Returns the reconstructed aggregate instance.
  ///
  /// Throws [StreamNotFoundException] if the stream does not exist.
  Future<TAggregate> loadAsync<TAggregate>(StreamId streamId);

  /// Applies a domain event to a stream, auto-detecting whether it
  /// is a creation or mutation event.
  ///
  /// Three detection paths in order:
  /// 1. **Already tracked** — stream is in the session's identity map,
  ///    apply event directly (fast path).
  /// 2. **Creation event** — a registered factory exists for the
  ///    (aggregate type, event type) pair. Creates the aggregate and
  ///    begins tracking the stream.
  /// 3. **Mutation event** — no factory found, loads the aggregate
  ///    from the store via [loadAsync], then applies the event.
  ///
  /// Returns the aggregate in its post-event state (when using eager
  /// application mode) or pre-event state (when using deferred mode).
  ///
  /// Throws [InvalidOperationException] if the event is a creation
  /// event but the stream is already tracked (strict creation guard).
  ///
  /// Throws [StreamNotFoundException] if the event is a mutation event
  /// and the stream does not exist in the store.
  Future<TAggregate> applyAsync<TAggregate>(
    StreamId streamId,
    ContinuumEvent event,
  );

  /// Loads all aggregates of the given type from the store.
  ///
  /// Queries the event store for all streams tagged with [TAggregate]'s
  /// type name, then loads each one via [loadAsync]. Streams that are
  /// already tracked in the session's identity map are returned from
  /// cache without a store round-trip.
  ///
  /// Returns an empty list if no streams of that type exist.
  Future<List<TAggregate>> loadAllAsync<TAggregate>();

  /// Persists all pending events to the event store.
  ///
  /// Uses optimistic concurrency control based on the versions
  /// observed when streams were loaded.
  ///
  /// When [maxRetries] is greater than zero and a [ConcurrencyException]
  /// is detected, the session automatically reloads conflicting streams
  /// from the store, reconstructs fresh aggregates, re-applies the
  /// pending events on top of the latest state, and retries the save.
  /// This is repeated up to [maxRetries] times.
  ///
  /// After a successful retry the in-session aggregate references are
  /// replaced with the newly reconstructed instances. Callers holding
  /// references obtained before [saveChangesAsync] should re-read the
  /// aggregate via [loadAsync] if they need the latest state.
  ///
  /// Returns a list of all committed [ContinuumEvent] instances across
  /// all streams, ordered by stream in persistence order. Returns an
  /// empty list if there were no pending events.
  ///
  /// Throws [ConcurrencyException] if a version conflict is detected
  /// and retries are exhausted (or [maxRetries] is zero).
  Future<List<ContinuumEvent>> saveChangesAsync({int maxRetries = 1});

  /// Discards pending events for a specific stream.
  ///
  /// The stream remains in the session but any uncommitted events
  /// are removed. The aggregate state is not reverted.
  void discardStream(StreamId streamId);

  /// Discards all pending events across all streams.
  ///
  /// All streams remain in the session but uncommitted events are
  /// removed. Aggregate states are not reverted.
  void discardAll();
}
