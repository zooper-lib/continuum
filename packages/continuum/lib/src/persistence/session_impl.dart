import '../events/domain_event.dart';
import '../exceptions/invalid_creation_event_exception.dart';
import '../exceptions/stream_not_found_exception.dart';
import '../exceptions/unsupported_event_exception.dart';
import '../identity/stream_id.dart';
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
  final List<DomainEvent> pendingEvents;

  /// Creates a stream state for tracking.
  _StreamState({
    required this.aggregate,
    required this.aggregateType,
    required this.loadedVersion,
    List<DomainEvent>? pendingEvents,
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

/// Internal implementation of the Session interface.
final class SessionImpl implements Session {
  final EventStore _eventStore;
  final EventSerializer _serializer;
  final AggregateFactoryRegistry _aggregateFactories;
  final EventApplierRegistry _eventAppliers;

  /// Tracked streams keyed by stream ID.
  final Map<StreamId, _StreamState> _streams = {};

  /// Creates a session implementation with dependencies.
  SessionImpl({
    required EventStore eventStore,
    required EventSerializer serializer,
    required AggregateFactoryRegistry aggregateFactories,
    required EventApplierRegistry eventAppliers,
  }) : _eventStore = eventStore,
       _serializer = serializer,
       _aggregateFactories = aggregateFactories,
       _eventAppliers = eventAppliers;

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
  void _applyEvent<TAggregate>(TAggregate aggregate, DomainEvent event) {
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
    DomainEvent creationEvent,
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
  void append(StreamId streamId, DomainEvent event) {
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
  Future<void> saveChangesAsync() async {
    // Persist all streams with pending events
    for (final entry in _streams.entries) {
      final streamId = entry.key;
      final state = entry.value;

      if (state.pendingEvents.isEmpty) continue;

      // Determine expected version
      final expectedVersion = state.loadedVersion == -1
          ? ExpectedVersion.noStream
          : ExpectedVersion.exact(state.loadedVersion);

      // Convert pending events to stored events
      final storedEvents = <StoredEvent>[];
      var nextVersion = state.loadedVersion + 1;

      for (final event in state.pendingEvents) {
        final serialized = _serializer.serialize(event);
        storedEvents.add(
          StoredEvent.fromDomainEvent(
            domainEvent: event,
            streamId: streamId,
            version: nextVersion,
            eventType: serialized.eventType,
            data: serialized.data,
          ),
        );
        nextVersion++;
      }

      // Append to store
      await _eventStore.appendEventsAsync(
        streamId,
        expectedVersion,
        storedEvents,
      );

      // Clear pending events after successful save
      // Note: We update the loaded version to reflect persisted state
      _streams[streamId] = _StreamState(
        aggregate: state.aggregate,
        aggregateType: state.aggregateType,
        loadedVersion: nextVersion - 1,
      );
    }
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
