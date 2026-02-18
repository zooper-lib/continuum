import 'package:continuum/continuum.dart';
import 'package:test/test.dart';

void main() {
  group('InlineProjectionExecutor', () {
    late ProjectionRegistry registry;
    late InMemoryReadModelStore<_CounterReadModel, StreamId> store;
    late InlineProjectionExecutor executor;

    setUp(() {
      registry = ProjectionRegistry();
      store = InMemoryReadModelStore<_CounterReadModel, StreamId>();
    });

    test('executeAsync does nothing when no projections registered', () async {
      executor = InlineProjectionExecutor(registry: registry);
      final operation = const _TestOperation(streamId: StreamId('stream-1'));

      // Should not throw — no projections means no work.
      await executor.executeAsync(
        CommitBatch(
          entries: [
            CommittedEntry(
              streamId: const StreamId('stream-1'),
              operations: [CommittedOperation(operation: operation)],
            ),
          ],
        ),
      );

      expect(store.length, equals(0));
    });

    test('executeAsync creates initial read model for new stream', () async {
      final projection = _CounterProjection();
      registry.registerInline(projection, store);
      executor = InlineProjectionExecutor(registry: registry);

      final operation = const _TestOperation(streamId: StreamId('stream-1'));
      await executor.executeAsync(
        CommitBatch(
          entries: [
            CommittedEntry(
              streamId: const StreamId('stream-1'),
              operations: [CommittedOperation(operation: operation)],
            ),
          ],
        ),
      );

      final readModel = await store.loadAsync(const StreamId('stream-1'));
      expect(readModel, isNotNull);
      expect(readModel!.count, equals(1));
    });

    test('executeAsync updates existing read model', () async {
      final projection = _CounterProjection();
      registry.registerInline(projection, store);
      executor = InlineProjectionExecutor(registry: registry);

      // Pre-populate read model.
      await store.saveAsync(
        const StreamId('stream-1'),
        const _CounterReadModel(streamId: 'stream-1', count: 5),
      );

      final operation = const _TestOperation(streamId: StreamId('stream-1'));
      await executor.executeAsync(
        CommitBatch(
          entries: [
            CommittedEntry(
              streamId: const StreamId('stream-1'),
              operations: [CommittedOperation(operation: operation)],
            ),
          ],
        ),
      );

      final readModel = await store.loadAsync(const StreamId('stream-1'));
      expect(readModel!.count, equals(6));
    });

    test('executeAsync processes multiple operations in order', () async {
      final projection = _CounterProjection();
      registry.registerInline(projection, store);
      executor = InlineProjectionExecutor(registry: registry);

      await executor.executeAsync(
        const CommitBatch(
          entries: [
            CommittedEntry(
              streamId: StreamId('stream-1'),
              operations: [
                CommittedOperation(operation: _TestOperation(streamId: StreamId('stream-1'))),
                CommittedOperation(operation: _TestOperation(streamId: StreamId('stream-1'))),
                CommittedOperation(operation: _TestOperation(streamId: StreamId('stream-1'))),
              ],
            ),
          ],
        ),
      );

      final readModel = await store.loadAsync(const StreamId('stream-1'));
      expect(readModel!.count, equals(3));
    });

    test('executeAsync processes operations for multiple streams', () async {
      final projection = _CounterProjection();
      registry.registerInline(projection, store);
      executor = InlineProjectionExecutor(registry: registry);

      await executor.executeAsync(
        const CommitBatch(
          entries: [
            CommittedEntry(
              streamId: StreamId('stream-1'),
              operations: [
                CommittedOperation(operation: _TestOperation(streamId: StreamId('stream-1'))),
                CommittedOperation(operation: _TestOperation(streamId: StreamId('stream-1'))),
              ],
            ),
            CommittedEntry(
              streamId: StreamId('stream-2'),
              operations: [
                CommittedOperation(operation: _TestOperation(streamId: StreamId('stream-2'))),
              ],
            ),
          ],
        ),
      );

      final readModel1 = await store.loadAsync(const StreamId('stream-1'));
      final readModel2 = await store.loadAsync(const StreamId('stream-2'));

      expect(readModel1!.count, equals(2));
      expect(readModel2!.count, equals(1));
    });

    test('executeAsync applies to multiple projections', () async {
      final projection1 = _CounterProjection('counter-1');
      final projection2 = _CounterProjection('counter-2');
      final store1 = InMemoryReadModelStore<_CounterReadModel, StreamId>();
      final store2 = InMemoryReadModelStore<_CounterReadModel, StreamId>();

      registry.registerInline(projection1, store1);
      registry.registerInline(projection2, store2);
      executor = InlineProjectionExecutor(registry: registry);

      final operation = const _TestOperation(streamId: StreamId('stream-1'));
      await executor.executeAsync(
        CommitBatch(
          entries: [
            CommittedEntry(
              streamId: const StreamId('stream-1'),
              operations: [CommittedOperation(operation: operation)],
            ),
          ],
        ),
      );

      final readModel1 = await store1.loadAsync(const StreamId('stream-1'));
      final readModel2 = await store2.loadAsync(const StreamId('stream-1'));

      expect(readModel1!.count, equals(1));
      expect(readModel2!.count, equals(1));
    });

    test('executeAsync skips async projections', () async {
      final inlineProjection = _CounterProjection('inline');
      final asyncProjection = _CounterProjection('async');
      final inlineStore = InMemoryReadModelStore<_CounterReadModel, StreamId>();
      final asyncStore = InMemoryReadModelStore<_CounterReadModel, StreamId>();

      registry.registerInline(inlineProjection, inlineStore);
      registry.registerAsync(asyncProjection, asyncStore);
      executor = InlineProjectionExecutor(registry: registry);

      final operation = const _TestOperation(streamId: StreamId('stream-1'));
      await executor.executeAsync(
        CommitBatch(
          entries: [
            CommittedEntry(
              streamId: const StreamId('stream-1'),
              operations: [CommittedOperation(operation: operation)],
            ),
          ],
        ),
      );

      // Async projections must NOT be executed by the inline executor.
      expect(inlineStore.length, equals(1));
      expect(asyncStore.length, equals(0));
    });

    test('executeAsync propagates projection errors', () async {
      final failingProjection = _FailingProjection();
      final failingStore = InMemoryReadModelStore<int, StreamId>();

      registry.registerInline(failingProjection, failingStore);
      executor = InlineProjectionExecutor(registry: registry);

      final operation = const _TestOperation(streamId: StreamId('stream-1'));

      // Inline projections must propagate errors — they run within the commit.
      await expectLater(
        executor.executeAsync(
          CommitBatch(
            entries: [
              CommittedEntry(
                streamId: const StreamId('stream-1'),
                operations: [CommittedOperation(operation: operation)],
              ),
            ],
          ),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('executeAsync routes operations only to matching projections', () async {
      // Arrange: Two projections that handle different operation types.
      final storeA = InMemoryReadModelStore<int, StreamId>();
      final storeB = InMemoryReadModelStore<int, StreamId>();
      registry.registerInline(_CounterProjectionForA(), storeA);
      registry.registerInline(_CounterProjectionForB(), storeB);
      executor = InlineProjectionExecutor(registry: registry);

      final operationA = const _TestOperationA(streamId: StreamId('stream-1'));

      // Act.
      await executor.executeAsync(
        CommitBatch(
          entries: [
            CommittedEntry(
              streamId: const StreamId('stream-1'),
              operations: [CommittedOperation(operation: operationA)],
            ),
          ],
        ),
      );

      // Assert: Only the matching projection should be updated.
      // This matters because unrelated projections must not mutate read models.
      expect(await storeA.loadAsync(const StreamId('stream-1')), equals(1));
      expect(await storeB.loadAsync(const StreamId('stream-1')), isNull);
    });
  });
}

// --- Test Fixtures ---

/// Test operation with a stream ID for key extraction.
class _TestOperation implements Operation {
  final StreamId streamId;

  const _TestOperation({required this.streamId});
}

/// Typed variant A for routing tests.
class _TestOperationA implements Operation {
  final StreamId streamId;

  const _TestOperationA({required this.streamId});
}

/// Typed variant B for routing tests.
class _TestOperationB implements Operation {
  final StreamId streamId;

  const _TestOperationB({required this.streamId});
}

/// Simple read model for testing.
class _CounterReadModel {
  final String streamId;
  final int count;

  const _CounterReadModel({required this.streamId, required this.count});
}

/// Counter projection that increments on every operation.
class _CounterProjection extends SingleStreamProjection<_CounterReadModel> {
  final String _name;

  _CounterProjection([this._name = 'counter']);

  @override
  Set<Type> get handledEventTypes => {_TestOperation};

  @override
  String get projectionName => _name;

  @override
  _CounterReadModel createInitial(StreamId streamId) {
    return _CounterReadModel(streamId: streamId.value, count: 0);
  }

  @override
  _CounterReadModel apply(_CounterReadModel current, Operation operation) {
    return _CounterReadModel(
      streamId: current.streamId,
      count: current.count + 1,
    );
  }
}

/// Projection that always fails — verifies error propagation.
class _FailingProjection extends SingleStreamProjection<int> {
  @override
  Set<Type> get handledEventTypes => {_TestOperation};

  @override
  String get projectionName => 'failing';

  @override
  int createInitial(StreamId streamId) => 0;

  @override
  int apply(int current, Operation operation) {
    throw StateError('Intentional failure for testing');
  }
}

/// Projection that only handles _TestOperationA.
final class _CounterProjectionForA extends SingleStreamProjection<int> {
  @override
  Set<Type> get handledEventTypes => const {_TestOperationA};

  @override
  String get projectionName => 'counter-a';

  @override
  int createInitial(StreamId streamId) => 0;

  @override
  int apply(int current, Operation operation) => current + 1;
}

/// Projection that only handles _TestOperationB.
final class _CounterProjectionForB extends SingleStreamProjection<int> {
  @override
  Set<Type> get handledEventTypes => const {_TestOperationB};

  @override
  String get projectionName => 'counter-b';

  @override
  int createInitial(StreamId streamId) => 0;

  @override
  int apply(int current, Operation operation) => current + 1;
}
