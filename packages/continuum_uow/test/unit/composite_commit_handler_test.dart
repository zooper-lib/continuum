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

/// A CommitHandler that records calls and operations.
final class _RecordingCommitHandler implements CommitHandler {
  int callCount = 0;
  final List<List<Operation>> receivedOperations = [];

  @override
  Future<void> onCommitAsync(List<Operation> committedOperations) async {
    callCount++;
    receivedOperations.add(committedOperations);
  }
}

/// A CommitHandler that throws an exception.
final class _FailingCommitHandler implements CommitHandler {
  @override
  Future<void> onCommitAsync(List<Operation> committedOperations) async {
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

      final operations = [
        const _FakeOperation('op1'),
        const _FakeOperation('op2'),
      ];

      // Act
      await composite.onCommitAsync(operations);

      // Assert — all handlers should have been called once
      expect(handler1.callCount, equals(1));
      expect(handler2.callCount, equals(1));
      expect(handler3.callCount, equals(1));

      // All handlers should receive the same operation list
      expect(handler1.receivedOperations.single, equals(operations));
      expect(handler2.receivedOperations.single, equals(operations));
      expect(handler3.receivedOperations.single, equals(operations));
    });

    test('should propagate exception and skip remaining handlers', () async {
      // Arrange
      final handler1 = _RecordingCommitHandler();
      final handler2 = _FailingCommitHandler(); // Throws
      final handler3 = _RecordingCommitHandler();
      final composite = CompositeCommitHandler([handler1, handler2, handler3]);

      final operations = [const _FakeOperation('op1')];

      // Act & Assert — exception should propagate from handler2
      await expectLater(
        () => composite.onCommitAsync(operations),
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
      final operations = [const _FakeOperation('op1')];

      // Act — should complete without error
      await composite.onCommitAsync(operations);

      // No assertions needed — just verifying no exception is thrown
    });

    test('should handle single handler', () async {
      // Arrange
      final handler = _RecordingCommitHandler();
      final composite = CompositeCommitHandler([handler]);
      final operations = [const _FakeOperation('op1')];

      // Act
      await composite.onCommitAsync(operations);

      // Assert
      expect(handler.callCount, equals(1));
      expect(handler.receivedOperations.single, equals(operations));
    });

    test('should handle empty operation list', () async {
      // Arrange
      final handler1 = _RecordingCommitHandler();
      final handler2 = _RecordingCommitHandler();
      final composite = CompositeCommitHandler([handler1, handler2]);

      // Act
      await composite.onCommitAsync([]);

      // Assert — both handlers should have been called with empty list
      expect(handler1.callCount, equals(1));
      expect(handler2.callCount, equals(1));
      expect(handler1.receivedOperations.single, isEmpty);
      expect(handler2.receivedOperations.single, isEmpty);
    });
  });
}
