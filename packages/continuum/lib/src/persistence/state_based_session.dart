import '../events/continuum_event.dart';
import '../exceptions/concurrency_exception.dart';
import '../exceptions/invalid_operation_exception.dart';
import '../exceptions/partial_save_exception.dart';
import '../identity/stream_id.dart';
import 'aggregate_persistence_adapter.dart';
import 'event_application_mode.dart';
import 'session_base.dart';

/// Session implementation backed by [AggregatePersistenceAdapter] instances.
///
/// Delegates load to `adapter.fetchAsync` and save to `adapter.persistAsync`,
/// reusing the shared event-application logic from [SessionBase]. Supports
/// concurrency retry when adapters throw [ConcurrencyException] and reports
/// partial multi-stream save failures via `PartialSaveException`.
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
    final existingState = streams[streamId];
    if (existingState != null) {
      return existingState.aggregate as TAggregate;
    }

    // Resolve the adapter for this aggregate type.
    final adapter = _resolveAdapter<TAggregate>();

    // Fetch the aggregate from the backend via the adapter.
    final aggregate = await adapter.fetchAsync(streamId) as TAggregate;

    // Track in the identity map with loadedVersion: 0 (sentinel for
    // "loaded from backend, version unknown" — concurrency detection
    // is the adapter's responsibility, not the session's).
    streams[streamId] = StreamState(
      aggregate: aggregate as Object,
      aggregateType: TAggregate,
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
  Future<TAggregate> handleMutationOnUntrackedStream<TAggregate>(
    StreamId streamId,
    ContinuumEvent event,
    bool hasExplicitType,
  ) async {
    // Path 3: Mutation event on untracked stream — load via adapter first.
    final adapter = _resolveAdapter<TAggregate>();
    final aggregate = await adapter.fetchAsync(streamId) as TAggregate;

    // Track in the identity map.
    streams[streamId] = StreamState(
      aggregate: aggregate as Object,
      aggregateType: TAggregate,
      loadedVersion: 0,
    );

    final state = streams[streamId]!;
    append(state, event);
    return aggregate;
  }

  @override
  Future<List<ContinuumEvent>> saveChangesAsync({int maxRetries = 1}) async {
    // Collect all streams with pending events.
    final pendingEntries = <MapEntry<StreamId, StreamState>>[];
    for (final entry in streams.entries) {
      if (entry.value.pendingEvents.isNotEmpty) {
        pendingEntries.add(entry);
      }
    }

    if (pendingEntries.isEmpty) return [];

    // In deferred mode, apply all pending events to aggregates before
    // persisting so the adapter receives the post-event state.
    applyDeferredEvents(pendingEntries);

    // Track which streams succeed and which fail.
    final savedStreams = <StreamId>[];
    final failedStreams = <StreamId>[];
    Object? firstFailure;

    // Persist each stream independently via its adapter.
    for (final entry in pendingEntries) {
      final streamId = entry.key;
      final state = entry.value;

      try {
        await _persistStreamWithRetry(
          streamId,
          state,
          maxRetries: maxRetries,
        );
        savedStreams.add(streamId);

        // Clear pending events for this successfully saved stream.
        streams[streamId] = state.withClearedPendingEvents();
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

    // All streams saved successfully — collect committed events.
    final allCommittedEvents = <ContinuumEvent>[];
    for (final entry in pendingEntries) {
      allCommittedEvents.addAll(entry.value.pendingEvents);
    }
    return allCommittedEvents;
  }

  /// Persists a single stream with concurrency retry logic.
  ///
  /// Catches [ConcurrencyException] from `persistAsync`, re-fetches the
  /// aggregate via `fetchAsync`, re-applies pending events, and retries
  /// up to [maxRetries] times.
  Future<void> _persistStreamWithRetry(
    StreamId streamId,
    StreamState state, {
    required int maxRetries,
  }) async {
    final adapter = _adapters[state.aggregateType]!;
    var currentAggregate = state.aggregate;
    final pendingEvents = List<ContinuumEvent>.of(state.pendingEvents);

    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        await adapter.persistAsync(streamId, currentAggregate, pendingEvents);
        return;
      } on ConcurrencyException {
        final isLastAttempt = attempt == maxRetries;
        if (isLastAttempt) {
          // All retries exhausted — propagate to caller.
          rethrow;
        }

        // Reload the aggregate from the backend.
        final freshAggregate = await adapter.fetchAsync(streamId);

        // Re-apply all pending events on top of the fresh state.
        for (final event in pendingEvents) {
          applyEventByRuntimeType(
            freshAggregate,
            event,
            state.aggregateType,
          );
        }

        // Update the stream state with the fresh aggregate.
        currentAggregate = freshAggregate;
        streams[streamId] = StreamState(
          aggregate: freshAggregate,
          aggregateType: state.aggregateType,
          loadedVersion: 0,
          pendingEvents: pendingEvents,
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
