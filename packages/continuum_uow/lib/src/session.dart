import 'package:continuum/continuum.dart';

/// Unit of Work abstraction for aggregate operations.
///
/// A session tracks loaded aggregates and pending operations, applying
/// changes optimistically and persisting them atomically on save.
///
/// Sessions are short-lived and should not be reused after
/// [saveChangesAsync] is called.
abstract interface class Session {
  /// Loads a single aggregate by its [streamId].
  ///
  /// Returns the aggregate instance hydrated from persistence. The
  /// target is cached in the identity map — subsequent calls with
  /// the same [streamId] return the cached instance.
  Future<TTarget> loadAsync<TTarget>(StreamId streamId);

  /// Loads all targets of type [TTarget].
  ///
  /// Returns all target instances of the requested type from
  /// persistence. Each loaded target is cached in the identity map.
  Future<List<TTarget>> loadAllAsync<TTarget>();

  /// Applies an [operation] to the target identified by [streamId].
  ///
  /// The operation parameter type is [Operation], allowing both
  /// [ContinuumEvent] instances and plain [Operation] implementations
  /// to be used interchangeably.
  ///
  /// Returns the target instance after the operation is processed.
  Future<TTarget> applyAsync<TTarget>(
    StreamId streamId,
    Operation operation,
  );

  /// Persists all pending operations atomically.
  ///
  /// Returns a [CommitBatch] containing the committed operations
  /// grouped by stream. Returns an empty batch when there are no
  /// pending operations. The [maxRetries] parameter controls how
  /// many times the save should be retried on concurrency conflicts.
  Future<CommitBatch> saveChangesAsync({int maxRetries = 1});

  /// Marks the target identified by [streamId] for deletion.
  ///
  /// The target does not need to be loaded first — the stream ID
  /// alone is sufficient. If the target is tracked in the identity
  /// map it will be removed on save; otherwise the deletion is
  /// forwarded directly to the persistence backend.
  ///
  /// The actual deletion happens when [saveChangesAsync] is called.
  void deleteAsync(StreamId streamId);

  /// Discards all pending operations for the given [streamId].
  ///
  /// The target remains in the identity map but its pending
  /// operations are cleared.
  void discardStream(StreamId streamId);

  /// Discards all pending operations across all tracked streams.
  ///
  /// All targets remain in the identity map but their pending
  /// operations are cleared.
  void discardAll();
}
