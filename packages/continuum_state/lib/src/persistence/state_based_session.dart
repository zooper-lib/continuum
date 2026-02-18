import 'package:continuum/continuum.dart';
import 'package:continuum_uow/continuum_uow.dart';

import 'aggregate_persistence_adapter.dart';

/// Session implementation backed by [AggregatePersistenceAdapter] instances.
///
/// Delegates load to `adapter.fetchAsync` and save to `adapter.persistAsync`,
/// reusing the shared operation-application logic from [SessionBase]. Supports
/// concurrency retry when adapters throw [ConcurrencyException] and reports
/// partial multi-stream save failures via [PartialSaveException].
final class StateBasedSession extends SessionBase {
  /// Adapter map keyed by aggregate type.
  final Map<Type, AggregatePersistenceAdapter<Object>> _adapters;

  /// Creates a state-based session with the given adapter map and
  /// shared registries.
  StateBasedSession({
    required Map<Type, AggregatePersistenceAdapter<Object>> adapters,
    required super.aggregateFactories,
    required super.eventAppliers,
    super.applicationMode = EventApplicationMode.eager,
  }) : _adapters = adapters;

  @override
  Future<TAggregate> loadAsync<TAggregate>(StreamId streamId) async {
    // Check the identity map first — same stream returns cached instance.
    final existingState = trackedEntities[streamId];
    if (existingState != null) {
      return existingState.entity as TAggregate;
    }

    // Resolve the adapter for this aggregate type.
    final adapter = _resolveAdapter<TAggregate>();

    // Fetch the aggregate from the backend via the adapter.
    final aggregate = await adapter.fetchAsync(streamId) as TAggregate;

    // Track in the identity map with loadedVersion: 0 (sentinel for
    // "loaded from backend, version unknown" — concurrency detection
    // is the adapter's responsibility, not the session's).
    trackedEntities[streamId] = TrackedEntity(
      entity: aggregate as Object,
      entityType: TAggregate,
      loadedVersion: 0,
    );

    return aggregate;
  }

  @override
  Future<List<TAggregate>> loadAllAsync<TAggregate>() async {
    // State-based sessions do not support bulk loading — there is no
    // event store to query for stream IDs by aggregate type.
    throw const InvalidOperationException(
      message:
          'loadAllAsync is not supported by StateBasedSession. '
          'Use loadAsync with explicit stream IDs instead.',
    );
  }

  @override
  Future<TAggregate> handleMutationOnUntrackedEntity<TAggregate>(
    StreamId streamId,
    Operation operation,
    bool hasExplicitType,
  ) async {
    // Path 3: Mutation operation on untracked entity — load via adapter first.
    final adapter = _resolveAdapter<TAggregate>();
    final aggregate = await adapter.fetchAsync(streamId) as TAggregate;

    // Track in the identity map.
    trackedEntities[streamId] = TrackedEntity(
      entity: aggregate as Object,
      entityType: TAggregate,
      loadedVersion: 0,
    );

    final state = trackedEntities[streamId]!;

    if (applicationMode == EventApplicationMode.eager) {
      // Apply the operation immediately in eager mode.
      applyOperationByRuntimeType(state.entity, operation, state.entityType);
    }

    // Record the operation as pending.
    state.pendingOperations.add(operation);

    return aggregate;
  }

  @override
  Future<List<Operation>> saveChangesAsync({int maxRetries = 1}) async {
    // Collect all entities with pending operations.
    final pendingEntries = <MapEntry<StreamId, TrackedEntity>>[];
    for (final entry in trackedEntities.entries) {
      if (entry.value.pendingOperations.isNotEmpty) {
        pendingEntries.add(entry);
      }
    }

    if (pendingEntries.isEmpty) return [];

    // Snapshot the committed operations before clearing them, so we
    // can return them to the caller in application order.
    final committedOperations = <Operation>[
      for (final entry in pendingEntries) ...entry.value.pendingOperations,
    ];

    // In deferred mode, apply all pending operations to entities before
    // persisting so the adapter receives the post-operation state.
    applyDeferredOperations(pendingEntries);

    // Track which streams succeed and which fail.
    final savedStreams = <StreamId>[];
    final failedStreams = <StreamId>[];
    Object? firstFailure;

    // Persist each stream independently via its adapter.
    for (final entry in pendingEntries) {
      final streamId = entry.key;
      final state = entry.value;

      try {
        await _persistStreamWithRetry(streamId, state, maxRetries: maxRetries);
        savedStreams.add(streamId);

        // Clear pending operations for this successfully saved stream.
        trackedEntities[streamId] = state.withClearedPendingOperations();
      } on Exception catch (exception) {
        failedStreams.add(streamId);
        firstFailure ??= exception;
      }
    }

    // Determine what to throw (if anything).
    if (failedStreams.isNotEmpty) {
      _handleSaveFailure(
        savedStreams: savedStreams,
        failedStreams: failedStreams,
        firstFailure: firstFailure!,
        totalStreams: pendingEntries.length,
      );
    }

    return committedOperations;
  }

  /// Persists a single stream with concurrency retry logic.
  ///
  /// Catches [ConcurrencyException] from `persistAsync`, re-fetches the
  /// aggregate via `fetchAsync`, re-applies pending operations, and
  /// retries up to [maxRetries] times.
  Future<void> _persistStreamWithRetry(
    StreamId streamId,
    TrackedEntity state, {
    required int maxRetries,
  }) async {
    final adapter = _adapters[state.entityType]!;
    var currentAggregate = state.entity;
    final pendingOperations = List<Operation>.of(state.pendingOperations);

    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        await adapter.persistAsync(streamId, currentAggregate, pendingOperations);
        return;
      } on ConcurrencyException {
        final isLastAttempt = attempt == maxRetries;
        if (isLastAttempt) {
          // All retries exhausted — propagate to caller.
          rethrow;
        }

        // Reload the aggregate from the backend.
        final freshAggregate = await adapter.fetchAsync(streamId);

        // Re-apply all pending operations on top of the fresh state.
        for (final operation in pendingOperations) {
          applyOperationByRuntimeType(freshAggregate, operation, state.entityType);
        }

        // Update the tracked entity with the fresh aggregate.
        currentAggregate = freshAggregate;
        trackedEntities[streamId] = TrackedEntity(
          entity: freshAggregate,
          entityType: state.entityType,
          loadedVersion: 0,
          pendingOperations: pendingOperations,
        );
      }
    }
  }

  /// Determines how to report save failures based on the number of
  /// saved and failed streams.
  ///
  /// - Single stream total → rethrow original exception
  /// - All streams failed → rethrow first failure directly
  /// - Partial failure → throw [PartialSaveException]
  Never _handleSaveFailure({
    required List<StreamId> savedStreams,
    required List<StreamId> failedStreams,
    required Object firstFailure,
    required int totalStreams,
  }) {
    // Single-stream failure or all-streams-fail: rethrow directly.
    if (savedStreams.isEmpty) {
      // All streams failed — throw the first failure directly, not
      // a PartialSaveException with empty savedStreams.
      throw firstFailure;
    }

    // Partial failure — some succeeded, some failed.
    throw PartialSaveException(
      savedStreams: savedStreams,
      failedStreams: failedStreams,
      cause: firstFailure,
    );
  }

  /// Resolves the adapter for the given aggregate type.
  ///
  /// Throws [InvalidOperationException] if no adapter is registered
  /// for [TAggregate].
  AggregatePersistenceAdapter<Object> _resolveAdapter<TAggregate>() {
    final adapter = _adapters[TAggregate];
    if (adapter == null) {
      throw InvalidOperationException(
        message:
            'No AggregatePersistenceAdapter registered for $TAggregate. '
            'Ensure an adapter is provided in the StateBasedStore constructor.',
      );
    }
    return adapter;
  }
}
