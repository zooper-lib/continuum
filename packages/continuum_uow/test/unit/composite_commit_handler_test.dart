import 'package:continuum/continuum.dart';
import 'package:continuum_uow/continuum_uow.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Test doubles
// ---------------------------------------------------------------------------

/// A fake operation for testing.
final class _FakeOperation implements Operation {
  final String label;

  const _FakeOperation(this.label);
}

/// A CommitHandler that records calls and batches.
final class _RecordingCommitHandler implements CommitHandler {
  int callCount = 0;
  final List<CommitBatch> receivedBatches = [];

  @override
  Future<void> onCommitAsync(CommitBatch batch) async {
    callCount++;
    receivedBatches.add(batch);
  }
}

/// A CommitHandler that throws an exception.
final class _FailingCommitHandler implements CommitHandler {
  @override
  Future<void> onCommitAsync(CommitBatch batch) async {
    throw StateError('Handler failure');
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('CompositeCommitHandler', () {
    test('should execute all handlers in sequence', () async {
      // Arrange
      final handler1 = _RecordingCommitHandler();
      final handler2 = _RecordingCommitHandler();
      final handler3 = _RecordingCommitHandler();
      final composite = CompositeCommitHandler([handler1, handler2, handler3]);

      final batch = const CommitBatch(
        entries: [
          CommittedEntry(
            streamId: StreamId('s'),
            operations: [
              CommittedOperation(operation: _FakeOperation('op1')),
              CommittedOperation(operation: _FakeOperation('op2')),
            ],
          ),
        ],
      );

      // Act
      await composite.onCommitAsync(batch);

      // Assert — all handlers should have been called once
      expect(handler1.callCount, equals(1));
      expect(handler2.callCount, equals(1));
      expect(handler3.callCount, equals(1));

      // All handlers should receive the same batch
      expect(handler1.receivedBatches.single, same(batch));
      expect(handler2.receivedBatches.single, same(batch));
      expect(handler3.receivedBatches.single, same(batch));
    });

    test('should propagate exception and skip remaining handlers', () async {
      // Arrange
      final handler1 = _RecordingCommitHandler();
      final handler2 = _FailingCommitHandler(); // Throws
      final handler3 = _RecordingCommitHandler();
      final composite = CompositeCommitHandler([handler1, handler2, handler3]);

      final operations = [
        const CommittedOperation(operation: _FakeOperation('op1')),
      ];
      final batch = CommitBatch(
        entries: [
          CommittedEntry(
            streamId: const StreamId('s'),
            operations: operations,
          ),
        ],
      );

      // Act & Assert — exception should propagate from handler2
      await expectLater(
        () => composite.onCommitAsync(batch),
        throwsA(isA<StateError>()),
      );

      // handler1 should have been called
      expect(handler1.callCount, equals(1));

      // handler3 should NOT have been called because handler2 threw
      expect(handler3.callCount, equals(0));
    });

    test('should handle empty handler list', () async {
      // Arrange
      final composite = const CompositeCommitHandler([]);
      final batch = const CommitBatch(
        entries: [
          CommittedEntry(
            streamId: StreamId('s'),
            operations: [
              CommittedOperation(operation: _FakeOperation('op1')),
            ],
          ),
        ],
      );

      // Act — should complete without error
      await composite.onCommitAsync(batch);

      // No assertions needed — just verifying no exception is thrown
    });

    test('should handle single handler', () async {
      // Arrange
      final handler = _RecordingCommitHandler();
      final composite = CompositeCommitHandler([handler]);
      final batch = const CommitBatch(
        entries: [
          CommittedEntry(
            streamId: StreamId('s'),
            operations: [
              CommittedOperation(operation: _FakeOperation('op1')),
            ],
          ),
        ],
      );

      // Act
      await composite.onCommitAsync(batch);

      // Assert
      expect(handler.callCount, equals(1));
      expect(handler.receivedBatches.single, same(batch));
    });

    test('should handle empty batch', () async {
      // Arrange
      final handler1 = _RecordingCommitHandler();
      final handler2 = _RecordingCommitHandler();
      final composite = CompositeCommitHandler([handler1, handler2]);

      // Act
      await composite.onCommitAsync(CommitBatch.empty);

      // Assert — both handlers should have been called with empty batch
      expect(handler1.callCount, equals(1));
      expect(handler2.callCount, equals(1));
      expect(handler1.receivedBatches.single.isEmpty, isTrue);
      expect(handler2.receivedBatches.single.isEmpty, isTrue);
    });
  });
}
