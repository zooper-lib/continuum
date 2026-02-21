import 'package:continuum/continuum.dart';
import 'package:meta/meta.dart';

import 'invalid_operation_exception.dart';
import 'session.dart';
import 'tracked_entity.dart';

/// Abstract base class containing persistence-agnostic session logic.
///
/// Captures the operation-application invariant — "operations mutate
/// entities identically regardless of persistence strategy" — as
/// shared code. Subclasses define only how to load and save.
///
/// Contains the identity map, 3-path [applyAsync] detection,
/// eager/deferred branching, creation guard, and discard operations.
///
/// Subclasses must implement four abstract methods:
/// - [loadAsync] — load a single entity from persistence
/// - [loadAllAsync] — load all entities of a type from persistence
/// - [saveChangesAsync] — persist all pending operations
/// - [handleMutationOnUntrackedEntity] — handle Path 3 of [applyAsync]
abstract class SessionBase implements Session {
  /// Aggregate factory registry for creating instances from operations.
  @protected
  final AggregateFactoryRegistry aggregateFactories;

  /// Event applier registry for applying operations to entities.
  @protected
  final EventApplierRegistry eventAppliers;

  /// Controls when operations mutate the in-memory entity.
  final EventApplicationMode applicationMode;

  /// Tracked entities keyed by stream ID.
  ///
  /// The identity map ensures each stream ID maps to exactly one
  /// in-memory entity instance for the lifetime of the session.
  final Map<StreamId, TrackedEntity> trackedEntities = {};

  /// Stream IDs marked for deletion during the next commit.
  ///
  /// Populated by [deleteAsync], consumed and cleared by
  /// [saveChangesAsync]. Subclass implementations must iterate
  /// this set during save to perform the actual deletion.
  @protected
  final Set<StreamId> streamsMarkedForDeletion = {};

  /// Creates a session base with shared dependencies.
  ///
  /// Requires an [AggregateFactoryRegistry] for creation dispatch,
  /// an [EventApplierRegistry] for mutation dispatch, and an
  /// [EventApplicationMode] controlling eager vs deferred application.
  SessionBase({
    required this.aggregateFactories,
    required this.eventAppliers,
    required this.applicationMode,
  });

  /// Whether the generic type parameter was explicitly provided by
  /// the caller.
  ///
  /// When [TAggregate] is `dynamic` or `Object`, it was likely omitted
  /// and Dart inferred a top type. This distinction controls how
  /// factory lookups are performed in [applyAsync].
  bool isExplicitType<TAggregate>() {
    return TAggregate != dynamic && TAggregate != Object;
  }

  @override
  Future<TAggregate> applyAsync<TAggregate>(
    StreamId streamId,
    Operation operation,
  ) async {
    // Determine which aggregate type to use for registry lookups.
    // When the caller omits the type parameter (TAggregate is dynamic
    // or Object), fall back to an event-type-only scan so that
    // `session.applyAsync(id, MyCreationEvent(...))` works without
    // requiring `session.applyAsync<MyAggregate>(id, event)`.
    final bool hasExplicitType = isExplicitType<TAggregate>();

    // Path 1: Already tracked — apply operation directly (fast path).
    final existingState = trackedEntities[streamId];
    if (existingState != null) {
      // Strict creation guard: creation operations are not allowed on
      // already-tracked entities. A creation operation semantically
      // means "this entity starts here" — applying one to an existing
      // entity is a programming error.
      //
      // Uses predicate-based lookups to correctly detect creation
      // operations when the operation is a sealed class subtype
      // (e.g., Freezed union).
      final isCreationOperation = hasExplicitType
          ? aggregateFactories.getFactoryForEvent<TAggregate>(
                  TAggregate,
                  operation,
                ) !=
                null
          : aggregateFactories.getFactoryByEvent(
                  operation,
                ) !=
                null;

      if (isCreationOperation) {
        throw InvalidOperationException(
          message:
              'Cannot apply creation operation ${operation.runtimeType} to '
              'already-tracked stream ${streamId.value}. '
              'Creation operations are only valid for new streams.',
        );
      }

      // Apply the mutation operation to the tracked entity.
      _append(existingState, operation);
      return existingState.entity as TAggregate;
    }

    // Path 2: Creation operation — factory probe succeeds.
    if (hasExplicitType) {
      // Caller specified the aggregate type — use the direct lookup.
      // Predicate-based lookup supports sealed class hierarchies where
      // operation.runtimeType is a private subclass (e.g., Freezed
      // union).
      final factory = aggregateFactories.getFactoryForEvent<TAggregate>(
        TAggregate,
        operation,
      );
      if (factory != null) {
        return _createAndTrack<TAggregate>(
          streamId,
          operation,
          factory,
          TAggregate,
        );
      }
    } else {
      // Caller omitted the type parameter — scan by operation instance.
      final result = aggregateFactories.getFactoryByEvent(
        operation,
      );
      if (result != null) {
        final aggregate = result.factory(operation);

        // Track in session with the resolved aggregate type.
        trackedEntities[streamId] = TrackedEntity(
          entity: aggregate,
          entityType: result.aggregateType,
          loadedVersion: -1, // New entity
          pendingOperations: [operation],
        );

        return aggregate as TAggregate;
      }
    }

    // Path 3: Mutation operation — load from persistence, then apply.
    // No creation factory was found, so this operation is treated as a
    // mutation. Delegates to the subclass-specific load.
    return handleMutationOnUntrackedEntity<TAggregate>(
      streamId,
      operation,
      hasExplicitType,
    );
  }

  /// Handles Path 3 of [applyAsync] — a mutation operation on an entity
  /// not yet tracked.
  ///
  /// Subclasses implement loading from their persistence backend,
  /// tracking the loaded entity, and applying the mutation operation.
  Future<TAggregate> handleMutationOnUntrackedEntity<TAggregate>(
    StreamId streamId,
    Operation operation,
    bool hasExplicitType,
  );

  /// Creates an entity from a creation operation, tracks it, and
  /// returns it.
  ///
  /// Used by Path 2 of [applyAsync] when a factory probe succeeds.
  TAggregate _createAndTrack<TAggregate>(
    StreamId streamId,
    Operation operation,
    AggregateFactory<TAggregate> factory,
    Type aggregateType,
  ) {
    final aggregate = factory(operation);

    trackedEntities[streamId] = TrackedEntity(
      entity: aggregate as Object,
      entityType: aggregateType,
      loadedVersion: -1, // New entity
      pendingOperations: [operation],
    );

    return aggregate;
  }

  /// Records a pending operation and optionally applies it to the entity.
  ///
  /// In [EventApplicationMode.eager], the operation handler is called
  /// immediately so the in-memory entity reflects the change.
  /// In [EventApplicationMode.deferred], the operation is only recorded;
  /// application happens during [applyDeferredOperations].
  void _append(TrackedEntity state, Operation operation) {
    if (applicationMode == EventApplicationMode.eager) {
      // Apply the operation to the entity immediately.
      applyOperationByRuntimeType(
        state.entity,
        operation,
        state.entityType,
      );
    }

    // Record the operation as pending regardless of mode.
    state.pendingOperations.add(operation);
  }

  /// Applies a single operation to an entity using the runtime [Type].
  ///
  /// Used by both eager application and during deferred-mode flush
  /// before persistence.
  @protected
  void applyOperationByRuntimeType(
    Object entity,
    Operation operation,
    Type entityType,
  ) {
    // Use predicate-based lookup for sealed class support.
    final applier = eventAppliers.getApplierForEvent<Object>(
      entityType,
      operation,
    );

    if (applier == null) {
      throw UnsupportedOperationException(
        operationType: operation.runtimeType,
        aggregateType: entityType,
      );
    }

    applier(entity, operation);
  }

  /// Applies all pending operations on entities in deferred mode.
  ///
  /// Called before persistence so the entity state is correct. In
  /// eager mode this is a no-op because operations were already applied.
  ///
  /// For new entities ([TrackedEntity.loadedVersion] == -1), the first
  /// pending operation is the creation operation that was already
  /// applied via the factory during [applyAsync] Path 2. Only
  /// subsequent mutation operations need deferred application.
  @protected
  void applyDeferredOperations(
    List<MapEntry<StreamId, TrackedEntity>> pendingEntries,
  ) {
    if (applicationMode == EventApplicationMode.deferred) {
      for (final entry in pendingEntries) {
        final state = entry.value;
        final isNewEntity = state.loadedVersion == -1;

        for (var i = 0; i < state.pendingOperations.length; i++) {
          // Skip the creation operation on new entities — it was
          // already applied by the factory when the entity was created.
          if (isNewEntity && i == 0) continue;

          applyOperationByRuntimeType(
            state.entity,
            state.pendingOperations[i],
            state.entityType,
          );
        }
      }
    }
  }

  @override
  void deleteAsync(StreamId streamId) {
    // Record the stream ID for deletion during the next commit.
    // The actual deletion is handled by the subclass in
    // saveChangesAsync. No prior load is required — the stream ID
    // alone is sufficient for both state-based adapters and event
    // store tombstone writes.
    streamsMarkedForDeletion.add(streamId);
  }

  @override
  void discardStream(StreamId streamId) {
    final state = trackedEntities[streamId];
    if (state != null) {
      trackedEntities[streamId] = state.withClearedPendingOperations();
    }
  }

  @override
  void discardAll() {
    for (final entry in trackedEntities.entries) {
      trackedEntities[entry.key] = entry.value.withClearedPendingOperations();
    }
  }
}
