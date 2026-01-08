import '../events/continuum_event.dart';
import '../identity/stream_id.dart';

/// Unit of work abstraction for event-sourced aggregate operations.
///
/// A session tracks loaded aggregates and pending events, applying
/// changes optimistically and persisting them atomically on save.
///
/// Sessions are short-lived and should not be reused after [saveChangesAsync]
/// is called.
abstract interface class Session {
  /// Loads an aggregate by its stream ID.
  ///
  /// Reconstructs the aggregate by loading stored events and replaying
  /// them through the generated dispatcher.
  ///
  /// Returns the reconstructed aggregate instance.
  ///
  /// Throws [StreamNotFoundException] if the stream does not exist.
  Future<TAggregate> loadAsync<TAggregate>(StreamId streamId);

  /// Starts a new stream with a creation event.
  ///
  /// Creates a new aggregate instance using the generated creation
  /// dispatcher and tracks it for persistence.
  ///
  /// Returns the newly created aggregate instance.
  ///
  /// Throws [InvalidCreationEventException] if the event is not a valid
  /// creation event for the aggregate type.
  TAggregate startStream<TAggregate>(
    StreamId streamId,
    ContinuumEvent creationEvent,
  );

  /// Appends a mutation event to an existing stream.
  ///
  /// The event is applied to the cached aggregate immediately and
  /// recorded as pending for persistence.
  ///
  /// Throws if the stream has not been loaded or started in this session.
  void append(StreamId streamId, ContinuumEvent event);

  /// Persists all pending events to the event store.
  ///
  /// Uses optimistic concurrency control based on the versions
  /// observed when streams were loaded.
  ///
  /// Throws [ConcurrencyException] if a version conflict is detected.
  Future<void> saveChangesAsync();

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
