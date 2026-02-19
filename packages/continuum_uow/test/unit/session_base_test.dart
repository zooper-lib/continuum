import 'package:continuum/continuum.dart';
import 'package:continuum_uow/continuum_uow.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Test domain types
// ---------------------------------------------------------------------------

/// A simple aggregate used in session tests.
final class _Counter {
  int value;
  _Counter(this.value);
}

/// A plain Operation (not ContinuumEvent) to verify ES-agnosticism.
final class _IncrementOperation implements Operation {
  final int amount;
  const _IncrementOperation(this.amount);
}

/// A creation operation for _Counter.
final class _CreateCounterOperation implements Operation {
  final int initialValue;
  const _CreateCounterOperation(this.initialValue);
}

/// A second creation operation — used to test the creation guard.
final class _AnotherCreationOperation implements Operation {
  const _AnotherCreationOperation();
}

// ---------------------------------------------------------------------------
// In-memory test session
// ---------------------------------------------------------------------------

/// Concrete [SessionBase] subclass for testing. Stores entities in a
/// simple in-memory map keyed by stream ID.
final class _InMemoryTestSession extends SessionBase {
  /// Pre-populated persistence store used by [loadAsync].
  final Map<StreamId, ({Object entity, Type entityType, int version})> store;

  /// Track whether saveChangesAsync was called.
  bool saveWasCalled = false;

  /// Track the entities that were saved (for assertions).
  final List<MapEntry<StreamId, TrackedEntity>> savedEntries = [];

  _InMemoryTestSession({
    required super.aggregateFactories,
    required super.eventAppliers,
    required super.applicationMode,
    Map<StreamId, ({Object entity, Type entityType, int version})>? store,
  }) : store = store ?? {};

  @override
  Future<TAggregate> loadAsync<TAggregate>(StreamId streamId) async {
    final entry = store[streamId];
    if (entry == null) {
      throw StateError('Stream ${streamId.value} not found in test store');
    }

    // Track in identity map.
    trackedEntities[streamId] = TrackedEntity(
      entity: entry.entity,
      entityType: entry.entityType,
      loadedVersion: entry.version,
    );

    return entry.entity as TAggregate;
  }

  @override
  Future<List<TAggregate>> loadAllAsync<TAggregate>() async {
    final results = <TAggregate>[];
    for (final entry in store.entries) {
      if (entry.value.entity is TAggregate) {
        trackedEntities[entry.key] = TrackedEntity(
          entity: entry.value.entity,
          entityType: entry.value.entityType,
          loadedVersion: entry.value.version,
        );
        results.add(entry.value.entity as TAggregate);
      }
    }
    return results;
  }

  @override
  Future<CommitBatch> saveChangesAsync({int maxRetries = 1}) async {
    final pendingEntries = trackedEntities.entries.where((e) => e.value.pendingOperations.isNotEmpty).toList();

    // Apply deferred operations before saving.
    applyDeferredOperations(pendingEntries);

    // Build committed entries grouped by stream.
    final entries = <CommittedEntry>[
      for (final entry in pendingEntries)
        CommittedEntry(
          streamId: entry.key,
          operations: [
            for (final op in entry.value.pendingOperations) CommittedOperation(operation: op),
          ],
        ),
    ];

    // Record what was saved for test assertions.
    savedEntries.addAll(pendingEntries);
    saveWasCalled = true;

    // Clear pending operations after successful save.
    for (final entry in pendingEntries) {
      trackedEntities[entry.key] = entry.value.withClearedPendingOperations();
    }

    return CommitBatch(entries: entries);
  }

  @override
  Future<TAggregate> handleMutationOnUntrackedEntity<TAggregate>(
    StreamId streamId,
    Operation operation,
    bool hasExplicitType,
  ) async {
    // Load from store, track, and apply mutation.
    final entry = store[streamId];
    if (entry == null) {
      throw StateError('Stream ${streamId.value} not found in test store');
    }

    final tracked = TrackedEntity(
      entity: entry.entity,
      entityType: entry.entityType,
      loadedVersion: entry.version,
    );
    trackedEntities[streamId] = tracked;

    // Apply the mutation operation.
    if (applicationMode == EventApplicationMode.eager) {
      applyOperationByRuntimeType(
        tracked.entity,
        operation,
        tracked.entityType,
      );
    }
    tracked.pendingOperations.add(operation);

    return tracked.entity as TAggregate;
  }
}

// ---------------------------------------------------------------------------
// Registry builders
// ---------------------------------------------------------------------------

/// Creates registries wired for [_Counter] with [_CreateCounterOperation]
/// and [_IncrementOperation].
({AggregateFactoryRegistry factories, EventApplierRegistry appliers}) _buildCounterRegistries({
  bool includeSecondCreation = false,
}) {
  final factoryMap = <Type, Map<Type, AggregateFactory<Object>>>{
    _Counter: {
      _CreateCounterOperation: (event) {
        final op = event as _CreateCounterOperation;
        return _Counter(op.initialValue);
      },
    },
  };

  if (includeSecondCreation) {
    factoryMap[_Counter]![_AnotherCreationOperation] = (_) => _Counter(0);
  }

  final applierMap = <Type, Map<Type, EventApplier<Object>>>{
    _Counter: {
      _IncrementOperation: (agg, event) {
        final counter = agg as _Counter;
        final op = event as _IncrementOperation;
        counter.value += op.amount;
      },
    },
  };

  return (
    factories: AggregateFactoryRegistry(factoryMap),
    appliers: EventApplierRegistry(applierMap),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('SessionBase', () {
    group('3-path applyAsync detection', () {
      test('Path 2 — creation operation should create and track entity', () async {
        // Arrange
        final (:factories, :appliers) = _buildCounterRegistries();
        final session = _InMemoryTestSession(
          aggregateFactories: factories,
          eventAppliers: appliers,
          applicationMode: EventApplicationMode.eager,
        );
        final streamId = const StreamId('counter-1');

        // Act
        final counter = await session.applyAsync<_Counter>(
          streamId,
          const _CreateCounterOperation(10),
        );

        // Assert — entity should be created with initial value
        expect(counter.value, equals(10));
        expect(session.trackedEntities.containsKey(streamId), isTrue);
        expect(
          session.trackedEntities[streamId]!.loadedVersion,
          equals(-1),
        );
        expect(
          session.trackedEntities[streamId]!.pendingOperations,
          hasLength(1),
        );
      });

      test('Path 1 — already tracked entity should append and apply operation', () async {
        // Arrange
        final (:factories, :appliers) = _buildCounterRegistries();
        final session = _InMemoryTestSession(
          aggregateFactories: factories,
          eventAppliers: appliers,
          applicationMode: EventApplicationMode.eager,
        );
        final streamId = const StreamId('counter-1');

        // Create first.
        await session.applyAsync<_Counter>(
          streamId,
          const _CreateCounterOperation(0),
        );

        // Act — apply mutation to already-tracked entity (Path 1).
        final counter = await session.applyAsync<_Counter>(
          streamId,
          const _IncrementOperation(5),
        );

        // Assert — value should reflect the increment
        expect(counter.value, equals(5));
        expect(
          session.trackedEntities[streamId]!.pendingOperations,
          hasLength(2),
        );
      });

      test('Path 3 — mutation on untracked entity should delegate to handleMutationOnUntrackedEntity', () async {
        // Arrange
        final (:factories, :appliers) = _buildCounterRegistries();
        final existingCounter = _Counter(10);
        final session = _InMemoryTestSession(
          aggregateFactories: factories,
          eventAppliers: appliers,
          applicationMode: EventApplicationMode.eager,
          store: {
            const StreamId('counter-1'): (
              entity: existingCounter,
              entityType: _Counter,
              version: 3,
            ),
          },
        );
        final streamId = const StreamId('counter-1');

        // Act — apply mutation to untracked entity (Path 3).
        final counter = await session.applyAsync<_Counter>(
          streamId,
          const _IncrementOperation(7),
        );

        // Assert — should have loaded from store and applied
        expect(counter.value, equals(17));
        expect(session.trackedEntities[streamId]!.loadedVersion, equals(3));
      });
    });

    group('identity map', () {
      test('should return same instance for repeated applyAsync on same stream', () async {
        // Arrange
        final (:factories, :appliers) = _buildCounterRegistries();
        final session = _InMemoryTestSession(
          aggregateFactories: factories,
          eventAppliers: appliers,
          applicationMode: EventApplicationMode.eager,
        );
        final streamId = const StreamId('counter-1');

        // Act
        final first = await session.applyAsync<_Counter>(
          streamId,
          const _CreateCounterOperation(0),
        );
        final second = await session.applyAsync<_Counter>(
          streamId,
          const _IncrementOperation(1),
        );

        // Assert — should be the exact same object instance
        expect(identical(first, second), isTrue);
      });
    });

    group('creation guard', () {
      test('should throw InvalidOperationException when applying creation operation to tracked entity', () async {
        // Arrange
        final (:factories, :appliers) = _buildCounterRegistries(
          includeSecondCreation: true,
        );
        final session = _InMemoryTestSession(
          aggregateFactories: factories,
          eventAppliers: appliers,
          applicationMode: EventApplicationMode.eager,
        );
        final streamId = const StreamId('counter-1');

        // Create the entity first.
        await session.applyAsync<_Counter>(
          streamId,
          const _CreateCounterOperation(0),
        );

        // Act & Assert — applying a second creation operation should throw
        expect(
          () => session.applyAsync<_Counter>(
            streamId,
            const _AnotherCreationOperation(),
          ),
          throwsA(isA<InvalidOperationException>()),
        );
      });
    });

    group('eager mode', () {
      test('should apply operation immediately', () async {
        // Arrange
        final (:factories, :appliers) = _buildCounterRegistries();
        final session = _InMemoryTestSession(
          aggregateFactories: factories,
          eventAppliers: appliers,
          applicationMode: EventApplicationMode.eager,
        );
        final streamId = const StreamId('counter-1');

        // Act
        await session.applyAsync<_Counter>(
          streamId,
          const _CreateCounterOperation(0),
        );
        final counter = await session.applyAsync<_Counter>(
          streamId,
          const _IncrementOperation(3),
        );

        // Assert — eager mode should have applied immediately
        expect(counter.value, equals(3));
      });
    });

    group('deferred mode', () {
      test('should not apply mutation operation until applyDeferredOperations', () async {
        // Arrange
        final (:factories, :appliers) = _buildCounterRegistries();
        final session = _InMemoryTestSession(
          aggregateFactories: factories,
          eventAppliers: appliers,
          applicationMode: EventApplicationMode.deferred,
        );
        final streamId = const StreamId('counter-1');

        // Act — create and then increment in deferred mode
        await session.applyAsync<_Counter>(
          streamId,
          const _CreateCounterOperation(0),
        );
        final counter = await session.applyAsync<_Counter>(
          streamId,
          const _IncrementOperation(5),
        );

        // Assert — deferred mode should NOT have applied the increment yet
        // The creation factory sets value to 0, but increment is deferred.
        expect(counter.value, equals(0));
      });

      test('should apply deferred operations on saveChangesAsync', () async {
        // Arrange
        final (:factories, :appliers) = _buildCounterRegistries();
        final session = _InMemoryTestSession(
          aggregateFactories: factories,
          eventAppliers: appliers,
          applicationMode: EventApplicationMode.deferred,
        );
        final streamId = const StreamId('counter-1');

        await session.applyAsync<_Counter>(
          streamId,
          const _CreateCounterOperation(0),
        );
        await session.applyAsync<_Counter>(
          streamId,
          const _IncrementOperation(5),
        );

        // Act — save triggers applyDeferredOperations
        await session.saveChangesAsync();

        // Assert — after save, deferred operations should have been applied
        final counter = session.trackedEntities[streamId]!.entity as _Counter;
        expect(counter.value, equals(5));
      });
    });

    group('discard', () {
      test('discardStream should clear pending operations for specific stream', () async {
        // Arrange
        final (:factories, :appliers) = _buildCounterRegistries();
        final session = _InMemoryTestSession(
          aggregateFactories: factories,
          eventAppliers: appliers,
          applicationMode: EventApplicationMode.eager,
        );
        final streamId = const StreamId('counter-1');

        await session.applyAsync<_Counter>(
          streamId,
          const _CreateCounterOperation(0),
        );
        await session.applyAsync<_Counter>(
          streamId,
          const _IncrementOperation(1),
        );

        // Act
        session.discardStream(streamId);

        // Assert — pending operations should be cleared
        expect(
          session.trackedEntities[streamId]!.pendingOperations,
          isEmpty,
        );
      });

      test('discardAll should clear pending operations for all streams', () async {
        // Arrange
        final (:factories, :appliers) = _buildCounterRegistries();
        final session = _InMemoryTestSession(
          aggregateFactories: factories,
          eventAppliers: appliers,
          applicationMode: EventApplicationMode.eager,
        );

        await session.applyAsync<_Counter>(
          const StreamId('c1'),
          const _CreateCounterOperation(0),
        );
        await session.applyAsync<_Counter>(
          const StreamId('c2'),
          const _CreateCounterOperation(0),
        );

        // Act
        session.discardAll();

        // Assert — all streams should have cleared operations
        for (final entry in session.trackedEntities.values) {
          expect(entry.pendingOperations, isEmpty);
        }
      });

      test('discardStream on unknown stream should be a no-op', () {
        // Arrange
        final (:factories, :appliers) = _buildCounterRegistries();
        final session = _InMemoryTestSession(
          aggregateFactories: factories,
          eventAppliers: appliers,
          applicationMode: EventApplicationMode.eager,
        );

        // Act & Assert — should not throw
        session.discardStream(const StreamId('nonexistent'));
      });
    });

    group('plain Operation support', () {
      test('should work with non-ContinuumEvent Operation types', () async {
        // Arrange — _IncrementOperation and _CreateCounterOperation
        // implement Operation but NOT ContinuumEvent, proving the
        // session layer is ES-agnostic.
        final (:factories, :appliers) = _buildCounterRegistries();
        final session = _InMemoryTestSession(
          aggregateFactories: factories,
          eventAppliers: appliers,
          applicationMode: EventApplicationMode.eager,
        );

        // Act
        final counter = await session.applyAsync<_Counter>(
          const StreamId('counter-1'),
          const _CreateCounterOperation(10),
        );
        await session.applyAsync<_Counter>(
          const StreamId('counter-1'),
          const _IncrementOperation(5),
        );

        // Assert — session should work identically with plain Operations
        expect(counter.value, equals(15));
      });
    });

    group('UnsupportedOperationException', () {
      test('should throw when no applier is registered for an operation', () async {
        // Arrange — create registries without _IncrementOperation applier
        final factories = AggregateFactoryRegistry({
          _Counter: {
            _CreateCounterOperation: (event) {
              final op = event as _CreateCounterOperation;
              return _Counter(op.initialValue);
            },
          },
        });
        final appliers = const EventApplierRegistry.empty();

        final session = _InMemoryTestSession(
          aggregateFactories: factories,
          eventAppliers: appliers,
          applicationMode: EventApplicationMode.eager,
        );
        final streamId = const StreamId('counter-1');

        await session.applyAsync<_Counter>(
          streamId,
          const _CreateCounterOperation(0),
        );

        // Act & Assert — applying an unregistered operation should throw
        expect(
          () => session.applyAsync<_Counter>(
            streamId,
            const _IncrementOperation(1),
          ),
          throwsA(isA<UnsupportedOperationException>()),
        );
      });
    });
  });
}
