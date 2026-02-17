import 'package:meta/meta.dart';

import '../events/continuum_event.dart';
import '../exceptions/invalid_operation_exception.dart';
import '../exceptions/unsupported_event_exception.dart';
import '../identity/stream_id.dart';
import 'event_application_mode.dart';
import 'event_sourcing_store.dart';
import 'session.dart';

/// Tracks the state of a stream within a session.
///
/// Shared by all session implementations. Holds the cached aggregate,
/// its type, the version at load time, and any pending (uncommitted)
/// events.
final class StreamState {
  /// The cached aggregate instance.
  final Object aggregate;

  /// The type of the aggregate for runtime checks.
  final Type aggregateType;

  /// The version when the stream was loaded (or -1 for new streams).
  final int loadedVersion;

  /// Pending events not yet persisted.
  final List<ContinuumEvent> pendingEvents;

  /// Creates a stream state for tracking.
  StreamState({
    required this.aggregate,
    required this.aggregateType,
    required this.loadedVersion,
    List<ContinuumEvent>? pendingEvents,
  }) : pendingEvents = pendingEvents ?? [];

  /// Creates a copy with a new pending events list.
  StreamState withClearedPendingEvents() {
    return StreamState(
      aggregate: aggregate,
      aggregateType: aggregateType,
      loadedVersion: loadedVersion,
      pendingEvents: [],
    );
  }
}

/// Abstract base class containing persistence-agnostic session logic.
///
/// Captures the domain-event-application invariant — "events mutate
/// aggregates identically regardless of persistence strategy" — as
/// shared code. Subclasses define only how to load and save.
///
/// Contains the identity map, 3-path `applyAsync` detection, eager/deferred
/// branching, creation guard, and discard operations.
abstract class SessionBase implements ContinuumSession {
  /// Aggregate factory registry for creating instances from events.
  @protected
  final AggregateFactoryRegistry aggregateFactories;

  /// Event applier registry for applying events to aggregates.
  @protected
  final EventApplierRegistry eventAppliers;

  /// Controls when events mutate the in-memory aggregate.
  final EventApplicationMode applicationMode;

  /// Tracked streams keyed by stream ID.
  final Map<StreamId, StreamState> streams = {};

  /// Creates a session base with shared dependencies.
  SessionBase({
    required this.aggregateFactories,
    required this.eventAppliers,
    required this.applicationMode,
  });

  /// Whether the generic type parameter was explicitly provided by the
  /// caller. When [TAggregate] is `dynamic` or `Object`, it was likely
  /// omitted and Dart inferred a top type.
  bool isExplicitType<TAggregate>() {
    return TAggregate != dynamic && TAggregate != Object;
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
    final bool hasExplicitType = isExplicitType<TAggregate>();

    // Path 1: Already tracked — apply event directly (fast path).
    final existingState = streams[streamId];
    if (existingState != null) {
      // Strict creation guard: creation events are not allowed on
      // already-tracked streams. A creation event semantically means
      // "this aggregate starts here" — applying one to an existing
      // aggregate is a programming error.
      //
      // Uses predicate-based lookups to correctly detect creation events
      // when the event is a sealed class subtype (e.g., Freezed union).
      final isCreationEvent = hasExplicitType
          ? aggregateFactories.getFactoryForEvent<TAggregate>(
                  TAggregate,
                  event,
                ) !=
                null
          : aggregateFactories.getFactoryByEvent(
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
      append(existingState, event);
      return existingState.aggregate as TAggregate;
    }

    // Path 2: Creation event — factory probe succeeds.
    if (hasExplicitType) {
      // Caller specified the aggregate type — use the direct lookup.
      // Predicate-based lookup supports sealed class hierarchies where
      // event.runtimeType is a private subclass (e.g., Freezed union).
      final factory = aggregateFactories.getFactoryForEvent<TAggregate>(
        TAggregate,
        event,
      );
      if (factory != null) {
        return createAndTrack<TAggregate>(
          streamId,
          event,
          factory,
          TAggregate,
        );
      }
    } else {
      // Caller omitted the type parameter — scan by event instance.
      final result = aggregateFactories.getFactoryByEvent(
        event,
      );
      if (result != null) {
        final aggregate = result.factory(event);

        // Track in session with the resolved aggregate type.
        streams[streamId] = StreamState(
          aggregate: aggregate,
          aggregateType: result.aggregateType,
          loadedVersion: -1, // New stream
          pendingEvents: [event],
        );

        return aggregate as TAggregate;
      }
    }

    // Path 3: Mutation event — load from store/adapter, then apply.
    // No creation factory was found, so this event is treated as a
    // mutation. Delegates to the subclass-specific load.
    return handleMutationOnUntrackedStream<TAggregate>(
      streamId,
      event,
      hasExplicitType,
    );
  }

  /// Handles Path 3 of `applyAsync` — a mutation event on a stream not
  /// yet tracked. Subclasses implement loading from their persistence
  /// backend.
  Future<TAggregate> handleMutationOnUntrackedStream<TAggregate>(
    StreamId streamId,
    ContinuumEvent event,
    bool hasExplicitType,
  );

  /// Creates an aggregate from a creation event, tracks it, and returns it.
  TAggregate createAndTrack<TAggregate>(
    StreamId streamId,
    ContinuumEvent event,
    AggregateFactory<TAggregate> factory,
    Type aggregateType,
  ) {
    final aggregate = factory(event);

    streams[streamId] = StreamState(
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
  void append(StreamState state, ContinuumEvent event) {
    if (applicationMode == EventApplicationMode.eager) {
      // Apply the event to the aggregate immediately.
      applyEventByRuntimeType(
        state.aggregate,
        event,
        state.aggregateType,
      );
    }

    // Record the event as pending regardless of mode.
    state.pendingEvents.add(event);
  }

  /// Applies a single event to an aggregate using the runtime [Type].
  ///
  /// Used by both session types for eager application and during
  /// deferred-mode flush before persistence.
  void applyEventByRuntimeType(
    Object aggregate,
    ContinuumEvent event,
    Type aggregateType,
  ) {
    // Use predicate-based lookup for sealed class support.
    final applier = eventAppliers.getApplierForEvent<Object>(
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

  /// Applies all pending events on streams in deferred mode.
  ///
  /// Called before persistence so the aggregate state is correct. In
  /// eager mode this is a no-op because events were already applied.
  ///
  /// For new streams (`loadedVersion == -1`), the first pending event
  /// is the creation event that was already applied via the factory
  /// during [applyAsync] Path 2. Only subsequent mutation events need
  /// deferred application.
  void applyDeferredEvents(
    List<MapEntry<StreamId, StreamState>> pendingEntries,
  ) {
    if (applicationMode == EventApplicationMode.deferred) {
      for (final entry in pendingEntries) {
        final state = entry.value;
        final isNewStream = state.loadedVersion == -1;

        for (var i = 0; i < state.pendingEvents.length; i++) {
          // Skip the creation event on new streams — it was already
          // applied by the factory when the aggregate was created.
          if (isNewStream && i == 0) continue;

          applyEventByRuntimeType(
            state.aggregate,
            state.pendingEvents[i],
            state.aggregateType,
          );
        }
      }
    }
  }

  @override
  void discardStream(StreamId streamId) {
    final state = streams[streamId];
    if (state != null) {
      streams[streamId] = state.withClearedPendingEvents();
    }
  }

  @override
  void discardAll() {
    for (final entry in streams.entries) {
      streams[entry.key] = entry.value.withClearedPendingEvents();
    }
  }
}
