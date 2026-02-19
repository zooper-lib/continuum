import 'package:continuum/continuum.dart';
import 'package:continuum_uow/continuum_uow.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Test doubles
// ---------------------------------------------------------------------------

/// A minimal Session implementation for testing TransactionalRunner.
final class _StubSession implements Session {
  bool saveWasCalled = false;
  int saveCallCount = 0;

  /// Batch to return from [saveChangesAsync].
  CommitBatch batchToReturn = CommitBatch.empty;

  @override
  Future<TAggregate> loadAsync<TAggregate>(StreamId streamId) async {
    throw UnimplementedError();
  }

  @override
  Future<List<TAggregate>> loadAllAsync<TAggregate>() async {
    throw UnimplementedError();
  }

  @override
  Future<TAggregate> applyAsync<TAggregate>(
    StreamId streamId,
    Operation operation,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<CommitBatch> saveChangesAsync({int maxRetries = 1}) async {
    saveWasCalled = true;
    saveCallCount++;
    return batchToReturn;
  }

  @override
  void discardStream(StreamId streamId) {}

  @override
  void discardAll() {}
}

/// A SessionStore that returns a pre-built stub session.
final class _StubSessionStore implements SessionStore {
  final List<_StubSession> createdSessions = [];

  /// Batch that newly created sessions will return from save.
  CommitBatch defaultBatchToReturn = CommitBatch.empty;

  @override
  Session openSession() {
    final session = _StubSession()..batchToReturn = defaultBatchToReturn;
    createdSessions.add(session);
    return session;
  }
}

/// A fake operation for testing that operations flow through to the handler.
final class _FakeOperation implements Operation {
  /// Identifier for test assertions.
  final String label;

  /// Creates a fake operation with the given [label].
  const _FakeOperation(this.label);
}

/// A CommitHandler that records calls and received batches.
final class _RecordingCommitHandler implements CommitHandler {
  int callCount = 0;

  /// All batches received across all calls.
  final List<CommitBatch> receivedBatches = [];

  @override
  Future<void> onCommitAsync(CommitBatch batch) async {
    callCount++;
    receivedBatches.add(batch);
  }
}

/// A CommitHandler that throws.
final class _FailingCommitHandler implements CommitHandler {
  @override
  Future<void> onCommitAsync(CommitBatch batch) async {
    throw StateError('CommitHandler failure');
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('TransactionalRunner', () {
    group('lifecycle', () {
      test('should open session, execute action, and save', () async {
        // Arrange
        final store = _StubSessionStore();
        final runner = TransactionalRunner(store: store);

        // Act
        final result = await runner.runAsync(() async {
          return 42;
        });

        // Assert — session should have been opened and saved
        expect(result, equals(42));
        expect(store.createdSessions, hasLength(1));
        expect(store.createdSessions.first.saveWasCalled, isTrue);
      });

      test('should not save when action throws', () async {
        // Arrange
        final store = _StubSessionStore();
        final runner = TransactionalRunner(store: store);

        // Act & Assert — exception should propagate
        await expectLater(
          () => runner.runAsync(() async {
            throw StateError('action failed');
          }),
          throwsA(isA<StateError>()),
        );

        // Session was opened but save should NOT have been called
        // because the action threw before completion.
        expect(store.createdSessions, hasLength(1));
        expect(store.createdSessions.first.saveWasCalled, isFalse);
      });
    });

    group('zone scoping', () {
      test('currentSession should return ambient session inside runAsync', () async {
        // Arrange
        final store = _StubSessionStore();
        final runner = TransactionalRunner(store: store);
        Session? capturedSession;

        // Act
        await runner.runAsync(() async {
          capturedSession = TransactionalRunner.currentSession;
          return null;
        });

        // Assert — captured session should be the one created by the store
        expect(capturedSession, isNotNull);
        expect(capturedSession, isA<_StubSession>());
      });

      test('currentSession should throw StateError outside runAsync', () {
        // Act & Assert
        expect(
          () => TransactionalRunner.currentSession,
          throwsA(isA<StateError>()),
        );
      });

      test('currentSessionOrNull should return null outside runAsync', () {
        // Act
        final session = TransactionalRunner.currentSessionOrNull;

        // Assert
        expect(session, isNull);
      });

      test('currentSessionOrNull should return session inside runAsync', () async {
        // Arrange
        final store = _StubSessionStore();
        final runner = TransactionalRunner(store: store);
        Session? capturedSession;

        // Act
        await runner.runAsync(() async {
          capturedSession = TransactionalRunner.currentSessionOrNull;
          return null;
        });

        // Assert
        expect(capturedSession, isNotNull);
      });
    });

    group('nested runAsync', () {
      test('should create independent sessions for nested calls', () async {
        // Arrange
        final store = _StubSessionStore();
        final runner = TransactionalRunner(store: store);
        Session? outerSession;
        Session? innerSession;

        // Act
        await runner.runAsync(() async {
          outerSession = TransactionalRunner.currentSession;
          await runner.runAsync(() async {
            innerSession = TransactionalRunner.currentSession;
            return null;
          });
          return null;
        });

        // Assert — each runAsync should have its own session
        expect(outerSession, isNotNull);
        expect(innerSession, isNotNull);
        expect(identical(outerSession, innerSession), isFalse);
        expect(store.createdSessions, hasLength(2));
      });
    });

    group('CommitHandler integration', () {
      test('should call CommitHandler with committed operations after save', () async {
        // Arrange — configure the session to return committed operations
        final operations = [const _FakeOperation('op-1'), const _FakeOperation('op-2')];
        final batch = CommitBatch(
          entries: [
            CommittedEntry(
              streamId: const StreamId('test-stream'),
              operations: [
                for (final op in operations) CommittedOperation(operation: op),
              ],
            ),
          ],
        );
        final store = _StubSessionStore()..defaultBatchToReturn = batch;
        final handler = _RecordingCommitHandler();
        final runner = TransactionalRunner(
          store: store,
          commitHandler: handler,
        );

        // Act
        await runner.runAsync(() async {
          return null;
        });

        // Assert — handler should have received the committed batch
        expect(handler.callCount, equals(1));
        expect(handler.receivedBatches.first.flatOperations, equals(operations));
      });

      test('should not call CommitHandler when no operations committed', () async {
        // Arrange — session returns empty batch (no pending operations)
        final store = _StubSessionStore();
        final handler = _RecordingCommitHandler();
        final runner = TransactionalRunner(
          store: store,
          commitHandler: handler,
        );

        // Act
        await runner.runAsync(() async {
          return null;
        });

        // Assert — handler should NOT be called for empty commits
        expect(handler.callCount, equals(0));
      });

      test('should not call CommitHandler when action throws', () async {
        // Arrange
        final batch = const CommitBatch(
          entries: [
            CommittedEntry(
              streamId: StreamId('s'),
              operations: [CommittedOperation(operation: _FakeOperation('op-1'))],
            ),
          ],
        );
        final store = _StubSessionStore()..defaultBatchToReturn = batch;
        final handler = _RecordingCommitHandler();
        final runner = TransactionalRunner(
          store: store,
          commitHandler: handler,
        );

        // Act — action throws before save
        try {
          await runner.runAsync(() async {
            throw StateError('action failed');
          });
        } on StateError {
          // Expected
        }

        // Assert — handler should NOT have been called because save
        // never executed.
        expect(handler.callCount, equals(0));
      });

      test('should propagate CommitHandler exception', () async {
        // Arrange — configure batch so the handler is actually called
        final batch = const CommitBatch(
          entries: [
            CommittedEntry(
              streamId: StreamId('s'),
              operations: [CommittedOperation(operation: _FakeOperation('op-1'))],
            ),
          ],
        );
        final store = _StubSessionStore()..defaultBatchToReturn = batch;
        final runner = TransactionalRunner(
          store: store,
          commitHandler: _FailingCommitHandler(),
        );

        // Act & Assert — CommitHandler exception should propagate
        await expectLater(
          () => runner.runAsync(() async => null),
          throwsA(isA<StateError>()),
        );

        // Save was still called (committed), but handler threw afterward.
        expect(store.createdSessions.first.saveWasCalled, isTrue);
      });

      test('should pass operations in application order', () async {
        // Arrange — verify ordering is preserved
        final operations = [
          const _FakeOperation('first'),
          const _FakeOperation('second'),
          const _FakeOperation('third'),
        ];
        final batch = CommitBatch(
          entries: [
            CommittedEntry(
              streamId: const StreamId('test-stream'),
              operations: [
                for (final op in operations) CommittedOperation(operation: op),
              ],
            ),
          ],
        );
        final store = _StubSessionStore()..defaultBatchToReturn = batch;
        final handler = _RecordingCommitHandler();
        final runner = TransactionalRunner(
          store: store,
          commitHandler: handler,
        );

        // Act
        await runner.runAsync(() async => null);

        // Assert — operations received in the same order
        final received = handler.receivedBatches.first.flatOperations;
        expect(received, hasLength(3));
        expect((received[0] as _FakeOperation).label, equals('first'));
        expect((received[1] as _FakeOperation).label, equals('second'));
        expect((received[2] as _FakeOperation).label, equals('third'));
      });
    });

    group('no handler', () {
      test('should work without CommitHandler', () async {
        // Arrange
        final store = _StubSessionStore();
        final runner = TransactionalRunner(store: store);

        // Act & Assert — should complete without errors
        final result = await runner.runAsync(() async => 'done');
        expect(result, equals('done'));
        expect(store.createdSessions.first.saveWasCalled, isTrue);
      });
    });
  });
}
