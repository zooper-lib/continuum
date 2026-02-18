import 'package:continuum/continuum.dart';
import 'package:continuum_uow/continuum_uow.dart';

import 'atomic_event_store.dart';
import 'event_serializer.dart';
import 'event_store.dart';
import 'expected_version.dart';
import 'stored_event.dart';

/// Internal implementation of the session interface for event sourcing.
///
/// Extends [SessionBase] for shared operation-application logic and adds
/// event-sourcing-specific load (event replay) and save (event store append)
/// operations.
///
/// The [saveChangesAsync] method returns `Future<List<ContinuumEvent>>`
/// (narrowing the base `Future<void>` return). It also validates that
/// all pending operations are [ContinuumEvent] instances before persisting.
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
    final existingState = trackedEntities[streamId];
    if (existingState != null) {
      return existingState.entity as TAggregate;
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
    trackedEntities[streamId] = TrackedEntity(
      entity: aggregate as Object,
      entityType: TAggregate,
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
        operationType: event.runtimeType,
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
  Future<TAggregate> handleMutationOnUntrackedEntity<TAggregate>(
    StreamId streamId,
    Operation operation,
    bool hasExplicitType,
  ) async {
    // Validate that the operation is a ContinuumEvent — ES sessions
    // require events for persistence (serialization, event store append).
    if (operation is! ContinuumEvent) {
      throw InvalidOperationException(
        message:
            'Event sourcing sessions require ContinuumEvent instances. '
            'Received ${operation.runtimeType} which does not implement '
            'ContinuumEvent. Use an event sourcing event type or switch '
            'to a different persistence strategy.',
      );
    }

    final ContinuumEvent event = operation;

    // Path 3: Mutation event — load from store, then apply.
    final storedEvents = await _eventStore.loadStreamAsync(streamId);

    if (storedEvents.isEmpty) {
      final typeHint = hasExplicitType ? '$TAggregate' : 'dynamic (not specified)';

      final registeredAggregates = aggregateFactories.registeredAggregateTypes;
      final registeredEventsForType = hasExplicitType ? aggregateFactories.getRegisteredEventTypes(TAggregate) : <Type>[];

      final diagnosticBuffer = StringBuffer();
      diagnosticBuffer.writeln(
        'Cannot apply ${event.runtimeType} to stream '
        '${streamId.value}: no creation factory was found for '
        '($typeHint, ${event.runtimeType}) and the stream does not '
        'exist in the store.',
      );

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

    final aggregate = _reconstructAggregate<TAggregate>(storedEvents);
    final loadedVersion = storedEvents.last.version;

    trackedEntities[streamId] = TrackedEntity(
      entity: aggregate as Object,
      entityType: TAggregate,
      loadedVersion: loadedVersion,
    );

    final state = trackedEntities[streamId]!;

    // Apply the mutation operation eagerly if in eager mode; always record it.
    if (applicationMode == EventApplicationMode.eager) {
      applyOperationByRuntimeType(
        state.entity,
        event,
        state.entityType,
      );
    }
    state.pendingOperations.add(event);

    return aggregate;
  }

  @override
  Future<List<ContinuumEvent>> saveChangesAsync({int maxRetries = 1}) async {
    // Validate that all pending operations are ContinuumEvent instances.
    // The UoW layer accepts any Operation, but ES persistence requires
    // ContinuumEvent for serialization and event store append.
    for (final entry in trackedEntities.entries) {
      for (final operation in entry.value.pendingOperations) {
        if (operation is! ContinuumEvent) {
          throw InvalidOperationException(
            message:
                'Event sourcing sessions require all pending operations to '
                'be ContinuumEvent instances. Stream ${entry.key.value} '
                'contains a ${operation.runtimeType} which does not '
                'implement ContinuumEvent.',
          );
        }
      }
    }

    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final committedEvents = await _persistPendingEventsAsync();
        return committedEvents;
      } on ConcurrencyException {
        final isLastAttempt = attempt == maxRetries;
        if (isLastAttempt) {
          rethrow;
        }

        await _reloadStreamsWithPendingEventsAsync();
      }
    }

    return [];
  }

  /// Core persistence logic extracted so [saveChangesAsync] can retry it.
  Future<List<ContinuumEvent>> _persistPendingEventsAsync() async {
    final pendingEntries = <MapEntry<StreamId, TrackedEntity>>[];
    for (final entry in trackedEntities.entries) {
      if (entry.value.pendingOperations.isNotEmpty) {
        pendingEntries.add(entry);
      }
    }

    if (pendingEntries.isEmpty) return [];

    final allCommittedEvents = <ContinuumEvent>[];

    // Apply deferred operations before persistence so entity state is correct.
    applyDeferredOperations(pendingEntries);

    if (pendingEntries.length > 1 && _eventStore is AtomicEventStore) {
      // Atomic multi-stream path: batch all streams into one call.
      final batches = <StreamId, StreamAppendBatch>{};
      final newLoadedVersions = <StreamId, int>{};

      for (final entry in pendingEntries) {
        final streamId = entry.key;
        final state = entry.value;

        final expectedVersion = state.loadedVersion == -1 ? ExpectedVersion.noStream : ExpectedVersion.exact(state.loadedVersion);

        final storedEvents = <StoredEvent>[];
        var nextVersion = state.loadedVersion + 1;

        for (final operation in state.pendingOperations) {
          // Safe cast — validated at the top of saveChangesAsync.
          final event = operation as ContinuumEvent;
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
          aggregateType: state.entityType.toString(),
        );
        newLoadedVersions[streamId] = nextVersion - 1;
      }

      await _eventStore.appendEventsToStreamsAsync(batches);

      // Update loaded versions after successful persistence.
      for (final entry in pendingEntries) {
        final streamId = entry.key;
        final state = entry.value;
        trackedEntities[streamId] = TrackedEntity(
          entity: state.entity,
          entityType: state.entityType,
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

      for (final operation in state.pendingOperations) {
        // Safe cast — validated at the top of saveChangesAsync.
        final event = operation as ContinuumEvent;
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
        aggregateType: state.entityType.toString(),
      );

      trackedEntities[streamId] = TrackedEntity(
        entity: state.entity,
        entityType: state.entityType,
        loadedVersion: nextVersion - 1,
      );
    }

    return allCommittedEvents;
  }

  /// Reloads all streams that still carry pending events.
  Future<void> _reloadStreamsWithPendingEventsAsync() async {
    final streamIdsToReload = <StreamId>[];

    for (final entry in trackedEntities.entries) {
      final hasPendingOperations = entry.value.pendingOperations.isNotEmpty;
      final isExistingStream = entry.value.loadedVersion != -1;

      if (hasPendingOperations && isExistingStream) {
        streamIdsToReload.add(entry.key);
      }
    }

    for (final streamId in streamIdsToReload) {
      final currentState = trackedEntities[streamId]!;

      // Preserve the pending events as ContinuumEvent for re-application.
      final pendingEvents = <ContinuumEvent>[];
      for (final operation in currentState.pendingOperations) {
        // Safe cast — validated at the top of saveChangesAsync.
        pendingEvents.add(operation as ContinuumEvent);
      }

      final storedEvents = await _eventStore.loadStreamAsync(streamId);

      if (storedEvents.isEmpty) {
        throw StreamNotFoundException(streamId: streamId);
      }

      final freshAggregate = _reconstructAggregateByRuntimeType(
        storedEvents,
        currentState.entityType,
      );
      final latestVersion = storedEvents.last.version;

      // Re-apply pending events to the fresh aggregate.
      for (final event in pendingEvents) {
        applyOperationByRuntimeType(
          freshAggregate,
          event,
          currentState.entityType,
        );
      }

      // Convert ContinuumEvent list back to Operation list for TrackedEntity.
      final pendingOperations = pendingEvents.map<Operation>((e) => e).toList();

      trackedEntities[streamId] = TrackedEntity(
        entity: freshAggregate,
        entityType: currentState.entityType,
        loadedVersion: latestVersion,
        pendingOperations: pendingOperations,
      );
    }
  }

  /// Reconstructs an aggregate using its runtime [Type] instead of a
  /// generic type parameter.
  Object _reconstructAggregateByRuntimeType(
    List<StoredEvent> events,
    Type aggregateType,
  ) {
    final creationStored = events.first;
    final creationEvent = _serializer.deserialize(
      eventType: creationStored.eventType,
      data: creationStored.data,
      storedMetadata: creationStored.metadata,
    );

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

    for (var i = 1; i < events.length; i++) {
      final storedEvent = events[i];
      final domainEvent = _serializer.deserialize(
        eventType: storedEvent.eventType,
        data: storedEvent.data,
        storedMetadata: storedEvent.metadata,
      );
      applyOperationByRuntimeType(aggregate, domainEvent, aggregateType);
    }

    return aggregate;
  }
}
