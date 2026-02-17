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
import 'event_sourcing_store.dart';
import 'event_store.dart';
import 'expected_version.dart';
import 'session.dart';
import 'stored_event.dart';

/// Tracks the state of a stream within a session.
final class _StreamState {
  /// The cached aggregate instance.
  final Object aggregate;

  /// The type of the aggregate for runtime checks.
  final Type aggregateType;

  /// The version when the stream was loaded (or -1 for new streams).
  final int loadedVersion;

  /// Pending events not yet persisted.
  final List<ContinuumEvent> pendingEvents;

  /// Creates a stream state for tracking.
  _StreamState({
    required this.aggregate,
    required this.aggregateType,
    required this.loadedVersion,
    List<ContinuumEvent>? pendingEvents,
  }) : pendingEvents = pendingEvents ?? [];

  /// Creates a copy with a new pending events list.
  _StreamState withClearedPendingEvents() {
    return _StreamState(
      aggregate: aggregate,
      aggregateType: aggregateType,
      loadedVersion: loadedVersion,
      pendingEvents: [],
    );
  }
}

/// Internal implementation of the ContinuumSession interface.
final class SessionImpl implements ContinuumSession {
  final EventStore _eventStore;
  final EventSerializer _serializer;
  final AggregateFactoryRegistry _aggregateFactories;
  final EventApplierRegistry _eventAppliers;

  /// Controls when events mutate the in-memory aggregate.
  final EventApplicationMode _applicationMode;

  /// Tracked streams keyed by stream ID.
  final Map<StreamId, _StreamState> _streams = {};

  /// Creates a session implementation with dependencies.
  SessionImpl({
    required EventStore eventStore,
    required EventSerializer serializer,
    required AggregateFactoryRegistry aggregateFactories,
    required EventApplierRegistry eventAppliers,
    EventApplicationMode applicationMode = EventApplicationMode.eager,
  }) : _eventStore = eventStore,
       _serializer = serializer,
       _aggregateFactories = aggregateFactories,
       _eventAppliers = eventAppliers,
       _applicationMode = applicationMode;

  @override
  Future<TAggregate> loadAsync<TAggregate>(StreamId streamId) async {
    // Check if already loaded in this session
    final existingState = _streams[streamId];
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
    _streams[streamId] = _StreamState(
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
    final factory = _aggregateFactories.getFactoryForEvent<TAggregate>(
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
    final applier = _eventAppliers.getApplierForEvent<TAggregate>(
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

  /// Whether the generic type parameter was explicitly provided by the
  /// caller. When [TAggregate] is `dynamic` or `Object`, it was likely
  /// omitted and Dart inferred a top type.
  bool _isExplicitType<TAggregate>() {
    return TAggregate != dynamic && TAggregate != Object;
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
  Future<TAggregate> applyAsync<TAggregate>(
    StreamId streamId,
    ContinuumEvent event,
  ) async {
    // Determine which aggregate type to use for registry lookups.
    // When the caller omits the type parameter (TAggregate is dynamic
    // or Object), fall back to an event-type-only scan so that
    // `session.applyAsync(id, MyCreationEvent(...))` works without
    // requiring `session.applyAsync<MyAggregate>(id, event)`.
    final bool hasExplicitType = _isExplicitType<TAggregate>();

    // Path 1: Already tracked — apply event directly (fast path).
    final existingState = _streams[streamId];
    if (existingState != null) {
      // Strict creation guard: creation events are not allowed on
      // already-tracked streams. A creation event semantically means
      // "this aggregate starts here" — applying one to an existing
      // aggregate is a programming error.
      //
      // Uses predicate-based lookups to correctly detect creation events
      // when the event is a sealed class subtype (e.g., Freezed union).
      final isCreationEvent = hasExplicitType
          ? _aggregateFactories.getFactoryForEvent<TAggregate>(
                  TAggregate,
                  event,
                ) !=
                null
          : _aggregateFactories.getFactoryByEvent(
                  event,
                ) !=
                null;

      if (isCreationEvent) {
        throw InvalidOperationException(
          message:
              'Cannot apply creation event ${event.runtimeType} to '
              'already-tracked stream ${streamId.value}. '
              'Creation events are only valid for new streams.',
        );
      }

      // Apply the mutation event to the tracked aggregate.
      _append(existingState, event);
      return existingState.aggregate as TAggregate;
    }

    // Path 2: Creation event — factory probe succeeds.
    if (hasExplicitType) {
      // Caller specified the aggregate type — use the direct lookup.
      // Predicate-based lookup supports sealed class hierarchies where
      // event.runtimeType is a private subclass (e.g., Freezed union).
      final factory = _aggregateFactories.getFactoryForEvent<TAggregate>(
        TAggregate,
        event,
      );
      if (factory != null) {
        return _createAndTrack<TAggregate>(
          streamId,
          event,
          factory,
          TAggregate,
        );
      }
    } else {
      // Caller omitted the type parameter — scan by event instance.
      final result = _aggregateFactories.getFactoryByEvent(
        event,
      );
      if (result != null) {
        final aggregate = result.factory(event);

        // Track in session with the resolved aggregate type.
        _streams[streamId] = _StreamState(
          aggregate: aggregate,
          aggregateType: result.aggregateType,
          loadedVersion: -1, // New stream
          pendingEvents: [event],
        );

        return aggregate as TAggregate;
      }
    }

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
      final registeredAggregates = _aggregateFactories.registeredAggregateTypes;
      final registeredEventsForType = hasExplicitType ? _aggregateFactories.getRegisteredEventTypes(TAggregate) : <Type>[];

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
    _streams[streamId] = _StreamState(
      aggregate: aggregate as Object,
      aggregateType: TAggregate,
      loadedVersion: loadedVersion,
    );

    final state = _streams[streamId]!;
    _append(state, event);
    return aggregate;
  }

  /// Creates an aggregate from a creation event, tracks it, and returns it.
  TAggregate _createAndTrack<TAggregate>(
    StreamId streamId,
    ContinuumEvent event,
    AggregateFactory<TAggregate> factory,
    Type aggregateType,
  ) {
    final aggregate = factory(event);

    _streams[streamId] = _StreamState(
      aggregate: aggregate as Object,
      aggregateType: aggregateType,
      loadedVersion: -1, // New stream
      pendingEvents: [event],
    );

    return aggregate;
  }

  /// Records a pending event and optionally applies it to the aggregate.
  ///
  /// In [EventApplicationMode.eager], the event handler is called
  /// immediately so the in-memory aggregate reflects the change.
  /// In [EventApplicationMode.deferred], the event is only recorded;
  /// application happens during [saveChangesAsync].
  void _append(_StreamState state, ContinuumEvent event) {
    if (_applicationMode == EventApplicationMode.eager) {
      // Apply the event to the aggregate immediately.
      _applyEventByRuntimeType(
        state.aggregate,
        event,
        state.aggregateType,
      );
    }

    // Record the event as pending regardless of mode.
    state.pendingEvents.add(event);
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
    final pendingEntries = <MapEntry<StreamId, _StreamState>>[];
    for (final entry in _streams.entries) {
      if (entry.value.pendingEvents.isNotEmpty) {
        pendingEntries.add(entry);
      }
    }

    if (pendingEntries.isEmpty) return [];

    // Collect all committed domain events for the return value.
    final allCommittedEvents = <ContinuumEvent>[];

    // In deferred mode, apply all pending events to aggregates before
    // serialization so the aggregate state is correct for persistence.
    if (_applicationMode == EventApplicationMode.deferred) {
      for (final entry in pendingEntries) {
        final state = entry.value;
        for (final event in state.pendingEvents) {
          _applyEventByRuntimeType(
            state.aggregate,
            event,
            state.aggregateType,
          );
        }
      }
    }

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
        _streams[streamId] = _StreamState(
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

      _streams[streamId] = _StreamState(
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
  /// and replaces the internal [_StreamState] so the next save attempt
  /// uses the correct [ExpectedVersion].
  ///
  /// New streams (those created via [applyAsync] with `loadedVersion == -1`)
  /// are skipped because their concurrency conflict is a duplicate-stream
  /// error, not a stale-version error, and reloading would not help.
  Future<void> _reloadStreamsWithPendingEventsAsync() async {
    final streamIdsToReload = <StreamId>[];

    for (final entry in _streams.entries) {
      final hasPendingEvents = entry.value.pendingEvents.isNotEmpty;
      final isExistingStream = entry.value.loadedVersion != -1;

      // Only existing streams benefit from a reload. New streams that
      // conflict have a duplicate-stream problem, not a stale-version one.
      if (hasPendingEvents && isExistingStream) {
        streamIdsToReload.add(entry.key);
      }
    }

    for (final streamId in streamIdsToReload) {
      final currentState = _streams[streamId]!;

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
        _applyEventByRuntimeType(
          freshAggregate,
          event,
          currentState.aggregateType,
        );
      }

      // Replace the stream state so the next persist attempt carries the
      // updated loadedVersion and the correctly-mutated aggregate.
      _streams[streamId] = _StreamState(
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
    final factory = _aggregateFactories.getFactoryForEvent<Object>(
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
      _applyEventByRuntimeType(aggregate, domainEvent, aggregateType);
    }

    return aggregate;
  }

  /// Applies a single event to an aggregate using the runtime [Type].
  ///
  /// Counterpart to [_applyEventToAggregate] for use in retry paths
  /// where the generic type parameter is unavailable.
  void _applyEventByRuntimeType(
    Object aggregate,
    ContinuumEvent event,
    Type aggregateType,
  ) {
    // Use predicate-based lookup for sealed class support.
    final applier = _eventAppliers.getApplierForEvent<Object>(
      aggregateType,
      event,
    );

    if (applier == null) {
      throw UnsupportedEventException(
        eventType: event.runtimeType,
        aggregateType: aggregateType,
      );
    }

    applier(aggregate, event);
  }

  @override
  void discardStream(StreamId streamId) {
    final state = _streams[streamId];
    if (state != null) {
      _streams[streamId] = state.withClearedPendingEvents();
    }
  }

  @override
  void discardAll() {
    for (final entry in _streams.entries) {
      _streams[entry.key] = entry.value.withClearedPendingEvents();
    }
  }
}
