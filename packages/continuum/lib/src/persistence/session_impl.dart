import '../events/continuum_event.dart';
import '../exceptions/concurrency_exception.dart';
import '../exceptions/invalid_creation_event_exception.dart';
import '../exceptions/stream_not_found_exception.dart';
import '../exceptions/unsupported_event_exception.dart';
import '../identity/stream_id.dart';
import '../projections/inline_projection_executor.dart';
import 'atomic_event_store.dart';
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

  /// Optional executor for inline projections.
  ///
  /// If provided, inline projections are executed after events are persisted
  /// during [saveChangesAsync].
  final InlineProjectionExecutor? _inlineProjectionExecutor;

  /// Tracked streams keyed by stream ID.
  final Map<StreamId, _StreamState> _streams = {};

  /// Creates a session implementation with dependencies.
  SessionImpl({
    required EventStore eventStore,
    required EventSerializer serializer,
    required AggregateFactoryRegistry aggregateFactories,
    required EventApplierRegistry eventAppliers,
    InlineProjectionExecutor? inlineProjectionExecutor,
  }) : _eventStore = eventStore,
       _serializer = serializer,
       _aggregateFactories = aggregateFactories,
       _eventAppliers = eventAppliers,
       _inlineProjectionExecutor = inlineProjectionExecutor;

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

    // Get the factory for creating the aggregate from the creation event
    final factory = _aggregateFactories.getFactory<TAggregate>(
      TAggregate,
      creationEvent.runtimeType,
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
      _applyEvent<TAggregate>(aggregate, domainEvent);
    }

    return aggregate;
  }

  /// Applies an event to an aggregate using the registered applier.
  void _applyEvent<TAggregate>(TAggregate aggregate, ContinuumEvent event) {
    final applier = _eventAppliers.getApplier<TAggregate>(
      TAggregate,
      event.runtimeType,
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
  TAggregate startStream<TAggregate>(
    StreamId streamId,
    ContinuumEvent creationEvent,
  ) {
    // Get the factory for creating the aggregate
    final factory = _aggregateFactories.getFactory<TAggregate>(
      TAggregate,
      creationEvent.runtimeType,
    );

    if (factory == null) {
      throw InvalidCreationEventException(
        eventType: creationEvent.runtimeType,
        aggregateType: TAggregate,
      );
    }

    // Create the aggregate from the creation event
    final aggregate = factory(creationEvent);

    // Track in session with pending creation event
    _streams[streamId] = _StreamState(
      aggregate: aggregate as Object,
      aggregateType: TAggregate,
      loadedVersion: -1, // New stream
      pendingEvents: [creationEvent],
    );

    return aggregate;
  }

  @override
  void append(StreamId streamId, ContinuumEvent event) {
    final state = _streams[streamId];

    if (state == null) {
      throw StateError(
        'Stream ${streamId.value} has not been loaded or started in this session',
      );
    }

    // Apply the event to the aggregate
    final applier = _eventAppliers.getApplier<Object>(
      state.aggregateType,
      event.runtimeType,
    );

    if (applier == null) {
      throw UnsupportedEventException(
        eventType: event.runtimeType,
        aggregateType: state.aggregateType,
      );
    }

    applier(state.aggregate, event);

    // Record as pending
    state.pendingEvents.add(event);
  }

  @override
  Future<void> saveChangesAsync({int maxRetries = 1}) async {
    // Attempt to persist, retrying on concurrency conflicts up to the
    // configured limit. Each retry reloads conflicting streams and
    // re-applies pending events on top of the latest persisted state.
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        await _persistPendingEventsAsync();
        return;
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
  }

  /// Core persistence logic extracted so [saveChangesAsync] can retry it.
  ///
  /// Serialises pending events, writes them to the store (atomically when
  /// possible), runs inline projections, and updates internal stream state.
  Future<void> _persistPendingEventsAsync() async {
    final pendingEntries = <MapEntry<StreamId, _StreamState>>[];
    for (final entry in _streams.entries) {
      if (entry.value.pendingEvents.isNotEmpty) {
        pendingEntries.add(entry);
      }
    }

    if (pendingEntries.isEmpty) return;

    // Collect all stored events for inline projection execution.
    final allStoredEvents = <StoredEvent>[];

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
          allStoredEvents.add(storedEvent);
          nextVersion++;
        }

        batches[streamId] = StreamAppendBatch(
          expectedVersion: expectedVersion,
          events: storedEvents,
        );
        newLoadedVersions[streamId] = nextVersion - 1;
      }

      await (_eventStore).appendEventsToStreamsAsync(batches);

      // Execute inline projections after successful persistence.
      if (_inlineProjectionExecutor != null) {
        await _inlineProjectionExecutor.executeAsync(allStoredEvents);
      }

      for (final entry in pendingEntries) {
        final streamId = entry.key;
        final state = entry.value;
        _streams[streamId] = _StreamState(
          aggregate: state.aggregate,
          aggregateType: state.aggregateType,
          loadedVersion: newLoadedVersions[streamId]!,
        );
      }

      return;
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
        allStoredEvents.add(storedEvent);
        nextVersion++;
      }

      await _eventStore.appendEventsAsync(streamId, expectedVersion, storedEvents);

      _streams[streamId] = _StreamState(
        aggregate: state.aggregate,
        aggregateType: state.aggregateType,
        loadedVersion: nextVersion - 1,
      );
    }

    // Execute inline projections after successful persistence.
    if (_inlineProjectionExecutor != null) {
      await _inlineProjectionExecutor.executeAsync(allStoredEvents);
    }
  }

  /// Reloads all streams that still carry pending events.
  ///
  /// For each such stream the method fetches the latest persisted events,
  /// reconstructs a fresh aggregate, re-applies the pending events on top,
  /// and replaces the internal [_StreamState] so the next save attempt
  /// uses the correct [ExpectedVersion].
  ///
  /// New streams (those created via [startStream] with `loadedVersion == -1`)
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
      final pendingEvents = List<ContinuumEvent>.of(currentState.pendingEvents);

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
        _applyEventByRuntimeType(freshAggregate, event, currentState.aggregateType);
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

    // Look up the factory using the runtime type.
    final factory = _aggregateFactories.getFactory<Object>(
      aggregateType,
      creationEvent.runtimeType,
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
  /// Counterpart to [_applyEvent] for use in retry paths where the
  /// generic type parameter is unavailable.
  void _applyEventByRuntimeType(
    Object aggregate,
    ContinuumEvent event,
    Type aggregateType,
  ) {
    final applier = _eventAppliers.getApplier<Object>(
      aggregateType,
      event.runtimeType,
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
