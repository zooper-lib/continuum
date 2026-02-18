import 'package:continuum/continuum.dart';
import 'package:continuum_uow/continuum_uow.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Test doubles
// ---------------------------------------------------------------------------

/// A fake operation for testing.
final class _FakeOperation implements Operation {
  /// Identifier for test assertions.
  final String label;

  /// Creates a fake operation with the given [label].
  const _FakeOperation(this.label);
}

/// A single-stream projection that records apply calls.
final class _RecordingProjection extends SingleStreamProjection<int> {
  int applyCount = 0;

  @override
  Set<Type> get handledEventTypes => {_FakeOperation};

  @override
  String get projectionName => 'recording';

  @override
  int createInitial(StreamId streamId) => 0;

  @override
  int apply(int current, Operation operation) {
    applyCount++;
    return current + 1;
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ProjectionCommitHandler', () {
    test('delegates batch to executor', () async {
      // Arrange
      final projection = _RecordingProjection();
      final registry = ProjectionRegistry();
      final store = InMemoryReadModelStore<int, StreamId>();
      registry.registerInline(projection, store);
      final executor = InlineProjectionExecutor(registry: registry);
      final handler = ProjectionCommitHandler(executor);
      final batch = const CommitBatch(
        entries: [
          CommittedEntry(
            streamId: StreamId('s-1'),
            operations: [
              CommittedOperation(operation: _FakeOperation('op-1')),
            ],
          ),
        ],
      );

      // Act
      await handler.onCommitAsync(batch);

      // Assert — projection was executed via the executor
      expect(projection.applyCount, equals(1));
      expect(await store.loadAsync(const StreamId('s-1')), equals(1));
    });

    test('propagates executor exception', () async {
      // Arrange — use a projection that throws
      final registry = ProjectionRegistry();
      final store = InMemoryReadModelStore<int, StreamId>();
      registry.registerInline(_FailingProjection(), store);
      final executor = InlineProjectionExecutor(registry: registry);
      final handler = ProjectionCommitHandler(executor);
      final batch = const CommitBatch(
        entries: [
          CommittedEntry(
            streamId: StreamId('s-1'),
            operations: [
              CommittedOperation(operation: _FakeOperation('op-1')),
            ],
          ),
        ],
      );

      // Act & Assert
      await expectLater(
        () => handler.onCommitAsync(batch),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('AsyncProjectionCommitHandler', () {
    test('invokes callback with batch', () async {
      // Arrange
      CommitBatch? received;
      final handler = AsyncProjectionCommitHandler((batch) async {
        received = batch;
      });
      final batch = const CommitBatch(
        entries: [
          CommittedEntry(
            streamId: StreamId('s-1'),
            operations: [
              CommittedOperation(operation: _FakeOperation('op-1')),
            ],
          ),
        ],
      );

      // Act
      await handler.onCommitAsync(batch);

      // Assert
      expect(received, same(batch));
    });

    test('propagates callback exception', () async {
      // Arrange
      final handler = AsyncProjectionCommitHandler((batch) async {
        throw StateError('callback failure');
      });
      final batch = const CommitBatch(
        entries: [
          CommittedEntry(
            streamId: StreamId('s-1'),
            operations: [
              CommittedOperation(operation: _FakeOperation('op-1')),
            ],
          ),
        ],
      );

      // Act & Assert
      await expectLater(
        () => handler.onCommitAsync(batch),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('Composition', () {
    test('ProjectionCommitHandler composes via CompositeCommitHandler', () async {
      // Arrange
      final projection = _RecordingProjection();
      final registry = ProjectionRegistry();
      final store = InMemoryReadModelStore<int, StreamId>();
      registry.registerInline(projection, store);
      final executor = InlineProjectionExecutor(registry: registry);
      final projectionHandler = ProjectionCommitHandler(executor);

      CommitBatch? asyncReceived;
      final asyncHandler = AsyncProjectionCommitHandler((batch) async {
        asyncReceived = batch;
      });
      final composite = CompositeCommitHandler([projectionHandler, asyncHandler]);

      final batch = const CommitBatch(
        entries: [
          CommittedEntry(
            streamId: StreamId('s-1'),
            operations: [
              CommittedOperation(operation: _FakeOperation('op-1')),
            ],
          ),
        ],
      );

      // Act
      await composite.onCommitAsync(batch);

      // Assert — both handlers executed
      expect(projection.applyCount, equals(1));
      expect(asyncReceived, same(batch));
    });
  });
}

/// A projection that always fails — verifies error propagation.
final class _FailingProjection extends SingleStreamProjection<int> {
  @override
  Set<Type> get handledEventTypes => {_FakeOperation};

  @override
  String get projectionName => 'failing';

  @override
  int createInitial(StreamId streamId) => 0;

  @override
  int apply(int current, Operation operation) {
    throw StateError('Intentional failure');
  }
}
