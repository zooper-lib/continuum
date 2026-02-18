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
  /// aggregate is cached in the identity map — subsequent calls with
  /// the same [streamId] return the cached instance.
  Future<TAggregate> loadAsync<TAggregate>(StreamId streamId);

  /// Loads all aggregates of type [TAggregate].
  ///
  /// Returns all aggregate instances of the requested type from
  /// persistence. Each loaded aggregate is cached in the identity map.
  Future<List<TAggregate>> loadAllAsync<TAggregate>();

  /// Applies an [operation] to the aggregate identified by [streamId].
  ///
  /// The operation parameter type is [Operation], allowing both
  /// [ContinuumEvent] instances and plain [Operation] implementations
  /// to be used interchangeably.
  ///
  /// Returns the aggregate instance after the operation is processed.
  Future<TAggregate> applyAsync<TAggregate>(
    StreamId streamId,
    Operation operation,
  );

  /// Persists all pending operations atomically.
  ///
  /// Returns the list of [Operation] instances that were committed,
  /// in application order. Returns an empty list when there are no
  /// pending operations. The [maxRetries] parameter controls how
  /// many times the save should be retried on concurrency conflicts.
  Future<List<Operation>> saveChangesAsync({int maxRetries = 1});

  /// Discards all pending operations for the given [streamId].
  ///
  /// The aggregate remains in the identity map but its pending
  /// operations are cleared.
  void discardStream(StreamId streamId);

  /// Discards all pending operations across all tracked streams.
  ///
  /// All aggregates remain in the identity map but their pending
  /// operations are cleared.
  void discardAll();
}
