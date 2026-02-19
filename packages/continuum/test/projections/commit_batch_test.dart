import 'package:continuum/continuum.dart';
import 'package:test/test.dart';

void main() {
  group('CommittedOperation', () {
    test('stores operation and null metadata for state-based stores', () {
      // Arrange
      final operation = const _FakeOperation('op1');

      // Act
      final committed = CommittedOperation(operation: operation);

      // Assert — metadata fields default to null for state-based stores.
      expect(committed.operation, same(operation));
      expect(committed.streamVersion, isNull);
      expect(committed.globalSequence, isNull);
    });

    test('stores operation with event-sourcing metadata', () {
      // Arrange
      final operation = const _FakeOperation('op1');

      // Act
      final committed = CommittedOperation(
        operation: operation,
        streamVersion: 5,
        globalSequence: 42,
      );

      // Assert — metadata populated by event-sourcing stores.
      expect(committed.operation, same(operation));
      expect(committed.streamVersion, equals(5));
      expect(committed.globalSequence, equals(42));
    });
  });

  group('CommittedEntry', () {
    test('carries stream identity and ordered operations', () {
      // Arrange
      const streamId = StreamId('user-123');
      final op1 = const CommittedOperation(operation: _FakeOperation('a'));
      final op2 = const CommittedOperation(operation: _FakeOperation('b'));

      // Act
      final entry = CommittedEntry(
        streamId: streamId,
        operations: [op1, op2],
      );

      // Assert — stream identity preserved alongside operations.
      expect(entry.streamId, equals(const StreamId('user-123')));
      expect(entry.operations, hasLength(2));
      expect(entry.operations[0], same(op1));
      expect(entry.operations[1], same(op2));
    });

    test('supports empty operation list', () {
      // Arrange & Act
      const entry = CommittedEntry(
        streamId: StreamId('empty-stream'),
        operations: [],
      );

      // Assert — a stream with no pending ops produces an empty entry.
      expect(entry.operations, isEmpty);
    });
  });

  group('CommitBatch', () {
    test('groups entries by stream', () {
      // Arrange
      final entryA = const CommittedEntry(
        streamId: StreamId('stream-a'),
        operations: [
          CommittedOperation(operation: _FakeOperation('a1')),
          CommittedOperation(operation: _FakeOperation('a2')),
        ],
      );
      final entryB = const CommittedEntry(
        streamId: StreamId('stream-b'),
        operations: [
          CommittedOperation(operation: _FakeOperation('b1')),
        ],
      );

      // Act
      final batch = CommitBatch(entries: [entryA, entryB]);

      // Assert — entries are grouped by stream in order.
      expect(batch.entries, hasLength(2));
      expect(batch.entries[0].streamId, equals(const StreamId('stream-a')));
      expect(batch.entries[0].operations, hasLength(2));
      expect(batch.entries[1].streamId, equals(const StreamId('stream-b')));
      expect(batch.entries[1].operations, hasLength(1));
    });

    test('flatOperations returns all operations in commit order', () {
      // Arrange
      final opA1 = const _FakeOperation('a1');
      final opA2 = const _FakeOperation('a2');
      final opB1 = const _FakeOperation('b1');

      final batch = CommitBatch(
        entries: [
          CommittedEntry(
            streamId: const StreamId('stream-a'),
            operations: [
              CommittedOperation(operation: opA1),
              CommittedOperation(operation: opA2),
            ],
          ),
          CommittedEntry(
            streamId: const StreamId('stream-b'),
            operations: [
              CommittedOperation(operation: opB1),
            ],
          ),
        ],
      );

      // Act
      final flat = batch.flatOperations;

      // Assert — flattened in per-stream, per-operation order.
      expect(flat, hasLength(3));
      expect(flat[0], same(opA1));
      expect(flat[1], same(opA2));
      expect(flat[2], same(opB1));
    });

    test('empty batch has no entries', () {
      // Act
      const batch = CommitBatch(entries: []);

      // Assert
      expect(batch.isEmpty, isTrue);
      expect(batch.isNotEmpty, isFalse);
      expect(batch.entries, isEmpty);
      expect(batch.flatOperations, isEmpty);
    });

    test('CommitBatch.empty is an empty batch', () {
      // Assert — static constant for convenience.
      expect(CommitBatch.empty.isEmpty, isTrue);
      expect(CommitBatch.empty.entries, isEmpty);
    });

    test('isEmpty and isNotEmpty reflect entry presence', () {
      // Arrange
      final batch = const CommitBatch(
        entries: [
          CommittedEntry(
            streamId: StreamId('s'),
            operations: [CommittedOperation(operation: _FakeOperation('x'))],
          ),
        ],
      );

      // Assert
      expect(batch.isEmpty, isFalse);
      expect(batch.isNotEmpty, isTrue);
    });
  });
}

// ---------------------------------------------------------------------------
// Test doubles
// ---------------------------------------------------------------------------

/// A fake operation for testing.
final class _FakeOperation implements Operation {
  /// Label for identification in assertions.
  final String label;

  /// Creates a fake operation with the given [label].
  const _FakeOperation(this.label);
}
