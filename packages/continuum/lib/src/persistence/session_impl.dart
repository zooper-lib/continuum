import '../events/continuum_event.dart';
import '../exceptions/concurrency_exception.dart';
import '../exceptions/invalid_creation_event_exception.dart';
import '../exceptions/invalid_operation_exception.dart';
import '../exceptions/stream_not_found_exception.dart';
import '../exceptions/unsupported_event_exception.dart';
import '../identity/stream_id.dart';
import 'atomic_event_store.dart';
import 'event_application_mode.dart';
import 'event_serializer.dart';
import 'event_store.dart';
import 'expected_version.dart';
import 'session_base.dart';
import 'stored_event.dart';

/// Internal implementation of the ContinuumSession interface for event sourcing.
///
/// Extends [SessionBase] for shared event-application logic and adds
/// event-sourcing-specific load (event replay) and save (event store append)
/// operations.
final class SessionImpl extends SessionBase {
  /// The underlying event store for persistence.
  final EventStore _eventStore;

  /// Serializer for converting events to/from stored form.
  final EventSerializer _serializer;

  /// Creates a session implementation with dependencies.
  SessionImpl({
    required EventStore eventStore,
    required EventSerializer serializer,
    required super.aggregateFactories,
    required super.eventAppliers,
    super.applicationMode = EventApplicationMode.eager,
  }) : _eventStore = eventStore,
       _serializer = serializer;

  @override
  Future<TAggregate> loadAsync<TAggregate>(StreamId streamId) async {
    // Check if already loaded in this session
    final existingState = streams[streamId];
    if (existingState != null) {
      return existingState.aggregate as TAggregate;
    }

    // Load events from store
    final storedEvents = await _eventStore.loadStreamAsync(streamId);

    // Throw if stream doesn't exist
    if (storedEvents.isEmpty) {
      throw StreamNotFoundException(streamId: streamId);
    }

    // Reconstruct aggregate from events
    final aggregate = _reconstructAggregate<TAggregate>(storedEvents);
    final loadedVersion = storedEvents.last.version;

    // Track in session
    streams[streamId] = StreamState(
      aggregate: aggregate as Object,
      aggregateType: TAggregate,
      loadedVersion: loadedVersion,
    );

    return aggregate;
  }

  /// Reconstructs an aggregate from its stored events.
  TAggregate _reconstructAggregate<TAggregate>(List<StoredEvent> events) {
    // Deserialize and apply the creation event (first event)
    final creationStored = events.first;
    final creationEvent = _serializer.deserialize(
      eventType: creationStored.eventType,
      data: creationStored.data,
      storedMetadata: creationStored.metadata,
    );

    // Get the factory for creating the aggregate from the creation event.
    // Uses predicate-based lookup to support sealed class hierarchies
    // (e.g., Freezed unions) where creationEvent.runtimeType may be a
    // private subclass of the annotated base event type.
    final factory = aggregateFactories.getFactoryForEvent<TAggregate>(
      TAggregate,
      creationEvent,
    );

    if (factory == null) {
      throw InvalidCreationEventException(
        eventType: creationEvent.runtimeType,
        aggregateType: TAggregate,
      );
    }

    // Create the aggregate from the creation event
    final aggregate = factory(creationEvent);

    // Apply remaining mutation events
    for (var i = 1; i < events.length; i++) {
      final storedEvent = events[i];
      final domainEvent = _serializer.deserialize(
        eventType: storedEvent.eventType,
        data: storedEvent.data,
        storedMetadata: storedEvent.metadata,
      );
      _applyEventToAggregate<TAggregate>(aggregate, domainEvent);
    }

    return aggregate;
  }

  /// Applies an event to an aggregate using the registered applier.
  void _applyEventToAggregate<TAggregate>(
    TAggregate aggregate,
    ContinuumEvent event,
  ) {
    // Use predicate-based lookup to support sealed class hierarchies
    // (e.g., Freezed unions) where event.runtimeType may be a private
    // subclass of the annotated base event type.
    final applier = eventAppliers.getApplierForEvent<TAggregate>(
      TAggregate,
      event,
    );

    if (applier == null) {
      throw UnsupportedEventException(
        eventType: event.runtimeType,
        aggregateType: TAggregate,
      );
    }

    applier(aggregate, event);
  }

  @override
  Future<List<TAggregate>> loadAllAsync<TAggregate>() async {
    final streamIds = await _eventStore.getStreamIdsByAggregateTypeAsync(
      TAggregate.toString(),
    );

    final List<TAggregate> aggregates = <TAggregate>[];
    for (final streamId in streamIds) {
      final aggregate = await loadAsync<TAggregate>(streamId);
      aggregates.add(aggregate);
    }

    return aggregates;
  }

  @override
  Future<TAggregate> handleMutationOnUntrackedStream<TAggregate>(
    StreamId streamId,
    ContinuumEvent event,
    bool hasExplicitType,
  ) async {
    // Path 3: Mutation event — load from store, then apply.
    // No creation factory was found, so this event is treated as a
    // mutation. The stream must already exist in the store.
    final storedEvents = await _eventStore.loadStreamAsync(streamId);

    if (storedEvents.isEmpty) {
      // The stream does not exist and no creation factory was found.
      // Build an actionable error message with diagnostic details so the
      // user can immediately see what IS registered versus what they
      // expected.
      final typeHint = hasExplicitType ? '$TAggregate' : 'dynamic (not specified)';

      // Gather diagnostic info about what factories are available.
      final registeredAggregates = aggregateFactories.registeredAggregateTypes;
      final registeredEventsForType = hasExplicitType ? aggregateFactories.getRegisteredEventTypes(TAggregate) : <Type>[];

      final diagnosticBuffer = StringBuffer();
      diagnosticBuffer.writeln(
        'Cannot apply ${event.runtimeType} to stream '
        '${streamId.value}: no creation factory was found for '
        '($typeHint, ${event.runtimeType}) and the stream does not '
        'exist in the store.',
      );

      // Show what aggregates are registered.
      if (registeredAggregates.isEmpty) {
        diagnosticBuffer.writeln(
          'No aggregate types are registered in the factory registry.',
        );
      } else {
        diagnosticBuffer.writeln(
          'Registered aggregate types: '
          '${registeredAggregates.join(', ')}.',
        );
      }

      // Show what creation events are registered for the requested
      // aggregate.
      if (hasExplicitType) {
        if (registeredEventsForType.isEmpty) {
          diagnosticBuffer.writeln(
            'No creation events are registered for $TAggregate. '
            'Verify that $TAggregate appears in the generated '
            '\$aggregateList and that build_runner has been re-run.',
          );
        } else {
          diagnosticBuffer.writeln(
            'Registered creation event types for $TAggregate: '
            '${registeredEventsForType.join(', ')}.',
          );
        }
      }

      diagnosticBuffer.write(
        'If this is a creation event, ensure the @AggregateEvent '
        'annotation includes `creation: true` and that a matching '
        'static factory method exists on the aggregate. Also verify '
        'that applyAsync is called with an explicit type parameter, '
        'e.g. session.applyAsync<MyAggregate>(...).',
      );

      throw InvalidOperationException(
        message: diagnosticBuffer.toString(),
      );
    }

    // Reconstruct the aggregate from persisted events.
    final aggregate = _reconstructAggregate<TAggregate>(storedEvents);
    final loadedVersion = storedEvents.last.version;

    // Track in session so subsequent calls hit the fast path.
    streams[streamId] = StreamState(
      aggregate: aggregate as Object,
      aggregateType: TAggregate,
      loadedVersion: loadedVersion,
    );

    final state = streams[streamId]!;
    append(state, event);
    return aggregate;
  }

  @override
  Future<List<ContinuumEvent>> saveChangesAsync({int maxRetries = 1}) async {
    // Attempt to persist, retrying on concurrency conflicts up to the
    // configured limit. Each retry reloads conflicting streams and
    // re-applies pending events on top of the latest persisted state.
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final committedEvents = await _persistPendingEventsAsync();
        return committedEvents;
      } on ConcurrencyException {
        final isLastAttempt = attempt == maxRetries;
        if (isLastAttempt) {
          // All retries exhausted — propagate the conflict to the caller.
          rethrow;
        }

        // Reload every stream that still has pending events so the next
        // attempt uses the latest persisted versions.
        await _reloadStreamsWithPendingEventsAsync();
      }
    }

    // Unreachable — the loop always returns or rethrows.
    return [];
  }

  /// Core persistence logic extracted so [saveChangesAsync] can retry it.
  ///
  /// Serialises pending events, writes them to the store (atomically when
  /// possible), and updates internal stream state.
  ///
  /// Returns the list of committed [ContinuumEvent] instances in
  /// persistence order.
  Future<List<ContinuumEvent>> _persistPendingEventsAsync() async {
    final pendingEntries = <MapEntry<StreamId, StreamState>>[];
    for (final entry in streams.entries) {
      if (entry.value.pendingEvents.isNotEmpty) {
        pendingEntries.add(entry);
      }
    }

    if (pendingEntries.isEmpty) return [];

    // Collect all committed domain events for the return value.
    final allCommittedEvents = <ContinuumEvent>[];

    // In deferred mode, apply all pending events to aggregates before
    // serialization so the aggregate state is correct for persistence.
    applyDeferredEvents(pendingEntries);

    // If the store supports atomic multi-stream writes, use it for true
    // all-or-nothing semantics when saving across multiple streams.
    if (pendingEntries.length > 1 && _eventStore is AtomicEventStore) {
      final batches = <StreamId, StreamAppendBatch>{};
      final newLoadedVersions = <StreamId, int>{};

      for (final entry in pendingEntries) {
        final streamId = entry.key;
        final state = entry.value;

        final expectedVersion = state.loadedVersion == -1 ? ExpectedVersion.noStream : ExpectedVersion.exact(state.loadedVersion);

        final storedEvents = <StoredEvent>[];
        var nextVersion = state.loadedVersion + 1;

        for (final event in state.pendingEvents) {
          final serialized = _serializer.serialize(event);
          final storedEvent = StoredEvent.fromContinuumEvent(
            continuumEvent: event,
            streamId: streamId,
            version: nextVersion,
            eventType: serialized.eventType,
            data: serialized.data,
          );
          storedEvents.add(storedEvent);
          allCommittedEvents.add(event);
          nextVersion++;
        }

        batches[streamId] = StreamAppendBatch(
          expectedVersion: expectedVersion,
          events: storedEvents,
          aggregateType: state.aggregateType.toString(),
        );
        newLoadedVersions[streamId] = nextVersion - 1;
      }

      await _eventStore.appendEventsToStreamsAsync(batches);

      for (final entry in pendingEntries) {
        final streamId = entry.key;
        final state = entry.value;
        streams[streamId] = StreamState(
          aggregate: state.aggregate,
          aggregateType: state.aggregateType,
          loadedVersion: newLoadedVersions[streamId]!,
        );
      }

      return allCommittedEvents;
    }

    // Fallback: persist streams independently.
    for (final entry in pendingEntries) {
      final streamId = entry.key;
      final state = entry.value;

      final expectedVersion = state.loadedVersion == -1 ? ExpectedVersion.noStream : ExpectedVersion.exact(state.loadedVersion);

      final storedEvents = <StoredEvent>[];
      var nextVersion = state.loadedVersion + 1;

      for (final event in state.pendingEvents) {
        final serialized = _serializer.serialize(event);
        final storedEvent = StoredEvent.fromContinuumEvent(
          continuumEvent: event,
          streamId: streamId,
          version: nextVersion,
          eventType: serialized.eventType,
          data: serialized.data,
        );
        storedEvents.add(storedEvent);
        allCommittedEvents.add(event);
        nextVersion++;
      }

      await _eventStore.appendEventsAsync(
        streamId,
        expectedVersion,
        storedEvents,
        aggregateType: state.aggregateType.toString(),
      );

      streams[streamId] = StreamState(
        aggregate: state.aggregate,
        aggregateType: state.aggregateType,
        loadedVersion: nextVersion - 1,
      );
    }

    return allCommittedEvents;
  }

  /// Reloads all streams that still carry pending events.
  ///
  /// For each such stream the method fetches the latest persisted events,
  /// reconstructs a fresh aggregate, re-applies the pending events on top,
  /// and replaces the internal [StreamState] so the next save attempt
  /// uses the correct [ExpectedVersion].
  ///
  /// New streams (those created via [applyAsync] with `loadedVersion == -1`)
  /// are skipped because their concurrency conflict is a duplicate-stream
  /// error, not a stale-version error, and reloading would not help.
  Future<void> _reloadStreamsWithPendingEventsAsync() async {
    final streamIdsToReload = <StreamId>[];

    for (final entry in streams.entries) {
      final hasPendingEvents = entry.value.pendingEvents.isNotEmpty;
      final isExistingStream = entry.value.loadedVersion != -1;

      // Only existing streams benefit from a reload. New streams that
      // conflict have a duplicate-stream problem, not a stale-version one.
      if (hasPendingEvents && isExistingStream) {
        streamIdsToReload.add(entry.key);
      }
    }

    for (final streamId in streamIdsToReload) {
      final currentState = streams[streamId]!;

      // Snapshot the events we still need to persist.
      final pendingEvents = List<ContinuumEvent>.of(
        currentState.pendingEvents,
      );

      // Fetch the latest persisted events from the store.
      final storedEvents = await _eventStore.loadStreamAsync(streamId);

      if (storedEvents.isEmpty) {
        throw StreamNotFoundException(streamId: streamId);
      }

      // Reconstruct the aggregate from all persisted events (including any
      // that were written by competing sessions since our last load).
      final freshAggregate = _reconstructAggregateByRuntimeType(
        storedEvents,
        currentState.aggregateType,
      );
      final latestVersion = storedEvents.last.version;

      // Re-apply our pending events on top of the freshly rebuilt state.
      for (final event in pendingEvents) {
        applyEventByRuntimeType(
          freshAggregate,
          event,
          currentState.aggregateType,
        );
      }

      // Replace the stream state so the next persist attempt carries the
      // updated loadedVersion and the correctly-mutated aggregate.
      streams[streamId] = StreamState(
        aggregate: freshAggregate,
        aggregateType: currentState.aggregateType,
        loadedVersion: latestVersion,
        pendingEvents: pendingEvents,
      );
    }
  }

  /// Reconstructs an aggregate using its runtime [Type] instead of a
  /// generic type parameter.
  ///
  /// This is used during concurrency retries where the concrete generic
  /// type is no longer available — only the [Type] captured at load time.
  Object _reconstructAggregateByRuntimeType(
    List<StoredEvent> events,
    Type aggregateType,
  ) {
    // Deserialize the creation event (first event in the stream).
    final creationStored = events.first;
    final creationEvent = _serializer.deserialize(
      eventType: creationStored.eventType,
      data: creationStored.data,
      storedMetadata: creationStored.metadata,
    );

    // Look up the factory using predicate-based matching for sealed
    // class support.
    final factory = aggregateFactories.getFactoryForEvent<Object>(
      aggregateType,
      creationEvent,
    );

    if (factory == null) {
      throw InvalidCreationEventException(
        eventType: creationEvent.runtimeType,
        aggregateType: aggregateType,
      );
    }

    final aggregate = factory(creationEvent);

    // Apply remaining mutation events.
    for (var i = 1; i < events.length; i++) {
      final storedEvent = events[i];
      final domainEvent = _serializer.deserialize(
        eventType: storedEvent.eventType,
        data: storedEvent.data,
        storedMetadata: storedEvent.metadata,
      );
      applyEventByRuntimeType(aggregate, domainEvent, aggregateType);
    }

    return aggregate;
  }
}
