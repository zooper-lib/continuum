import 'dart:async';

import 'package:continuum/continuum.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../_fixtures/counter_fixtures.dart';

@GenerateNiceMocks([
  MockSpec<ContinuumStore>(),
  MockSpec<ContinuumSession>(),
  MockSpec<CommitHandler>(),
])
import 'transactional_runner_test.mocks.dart';

void main() {
  late MockContinuumStore mockStore;
  late MockContinuumSession mockSession;
  late MockCommitHandler mockCommitHandler;

  setUp(() {
    mockStore = MockContinuumStore();
    mockSession = MockContinuumSession();
    mockCommitHandler = MockCommitHandler();

    when(mockStore.openSession()).thenReturn(mockSession);
  });

  // --------------------------------------------------------------------------
  // 10.9 — TransactionalRunner.runAsync lifecycle
  // --------------------------------------------------------------------------
  group('TransactionalRunner.runAsync lifecycle', () {
    test('opens a session, executes action, and auto-commits', () async {
      // Arrange
      when(mockSession.saveChangesAsync(maxRetries: anyNamed('maxRetries'))).thenAnswer((_) async => <ContinuumEvent>[]);

      final runner = TransactionalRunner(store: mockStore);

      // Act
      final result = await runner.runAsync(() async => 42);

      // Assert — session was opened and saved.
      verify(mockStore.openSession()).called(1);
      verify(mockSession.saveChangesAsync(maxRetries: anyNamed('maxRetries'))).called(1);
      expect(result, equals(42), reason: 'Action result must be returned.');
    });

    test('calls commit handler with committed events after save', () async {
      // Arrange
      final committedEvents = <ContinuumEvent>[
        CounterCreated(eventId: const EventId('e-1'), initial: 0),
      ];
      when(mockSession.saveChangesAsync(maxRetries: anyNamed('maxRetries'))).thenAnswer((_) async => committedEvents);
      when(mockCommitHandler.onCommitAsync(any)).thenAnswer((_) async {});

      final runner = TransactionalRunner(
        store: mockStore,
        commitHandler: mockCommitHandler,
      );

      // Act
      await runner.runAsync(() async {});

      // Assert — handler called with the committed events.
      verify(mockCommitHandler.onCommitAsync(committedEvents)).called(1);
    });

    test('does not call commit handler when commit returns empty list', () async {
      // Arrange — no events committed.
      when(mockSession.saveChangesAsync(maxRetries: anyNamed('maxRetries'))).thenAnswer((_) async => <ContinuumEvent>[]);

      final runner = TransactionalRunner(
        store: mockStore,
        commitHandler: mockCommitHandler,
      );

      // Act
      await runner.runAsync(() async {});

      // Assert — handler NOT called because there were no events.
      verifyNever(mockCommitHandler.onCommitAsync(any));
    });

    test('does not call commit handler when none is configured', () async {
      // Arrange — no commit handler.
      when(mockSession.saveChangesAsync(maxRetries: anyNamed('maxRetries'))).thenAnswer(
        (_) async => <ContinuumEvent>[
          CounterCreated(eventId: const EventId('e-1'), initial: 0),
        ],
      );

      final runner = TransactionalRunner(store: mockStore);

      // Act & Assert — should not throw.
      await expectLater(runner.runAsync(() async {}), completes);
    });
  });

  // --------------------------------------------------------------------------
  // 10.10 — currentSession and currentSessionOrNull
  // --------------------------------------------------------------------------
  group('TransactionalRunner.currentSession', () {
    test('returns the ambient session inside runAsync', () async {
      // Arrange
      when(mockSession.saveChangesAsync(maxRetries: anyNamed('maxRetries'))).thenAnswer((_) async => <ContinuumEvent>[]);

      final runner = TransactionalRunner(store: mockStore);
      ContinuumSession? capturedSession;

      // Act — capture the session inside the action.
      await runner.runAsync(() async {
        capturedSession = TransactionalRunner.currentSession;
      });

      // Assert — the captured session is the one opened by the runner.
      expect(
        capturedSession,
        same(mockSession),
        reason: 'currentSession must return the session opened by runAsync.',
      );
    });

    test('throws StateError when called outside runAsync', () {
      // Act & Assert
      expect(
        () => TransactionalRunner.currentSession,
        throwsA(isA<StateError>()),
      );
    });
  });

  group('TransactionalRunner.currentSessionOrNull', () {
    test('returns the ambient session inside runAsync', () async {
      // Arrange
      when(mockSession.saveChangesAsync(maxRetries: anyNamed('maxRetries'))).thenAnswer((_) async => <ContinuumEvent>[]);

      final runner = TransactionalRunner(store: mockStore);
      ContinuumSession? capturedSession;

      // Act
      await runner.runAsync(() async {
        capturedSession = TransactionalRunner.currentSessionOrNull;
      });

      // Assert
      expect(capturedSession, same(mockSession));
    });

    test('returns null when called outside runAsync', () {
      // Act
      final session = TransactionalRunner.currentSessionOrNull;

      // Assert
      expect(
        session,
        isNull,
        reason: 'currentSessionOrNull must return null outside runAsync.',
      );
    });
  });

  // --------------------------------------------------------------------------
  // 10.11 — Exception handling: session abandoned, no save
  // --------------------------------------------------------------------------
  group('TransactionalRunner when action throws', () {
    test('does not call saveChangesAsync when action throws', () async {
      // Arrange
      final runner = TransactionalRunner(store: mockStore);

      // Act — the action throws.
      await expectLater(
        runner.runAsync(() async {
          throw StateError('intentional error');
        }),
        throwsA(isA<StateError>()),
      );

      // Assert — save should NOT have been called because the action failed.
      verifyNever(
        mockSession.saveChangesAsync(maxRetries: anyNamed('maxRetries')),
      );
    });

    test('propagates the original exception to the caller', () async {
      // Arrange
      final runner = TransactionalRunner(store: mockStore);

      // Act & Assert
      await expectLater(
        runner.runAsync(() async {
          throw ArgumentError('test error');
        }),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('does not call commit handler when action throws', () async {
      // Arrange
      final runner = TransactionalRunner(
        store: mockStore,
        commitHandler: mockCommitHandler,
      );

      // Act — suppress the expected error.
      try {
        await runner.runAsync(() async => throw Exception('boom'));
      } catch (_) {
        // Expected.
      }

      // Assert
      verifyNever(mockCommitHandler.onCommitAsync(any));
    });
  });

  // --------------------------------------------------------------------------
  // 10.12 — CommitHandler semantics
  // --------------------------------------------------------------------------
  group('CommitHandler semantics', () {
    test('called after successful save with events', () async {
      // Arrange
      final events = <ContinuumEvent>[
        CounterCreated(eventId: const EventId('e-1'), initial: 0),
        CounterIncremented(amount: 5),
      ];
      when(mockSession.saveChangesAsync(maxRetries: anyNamed('maxRetries'))).thenAnswer((_) async => events);
      when(mockCommitHandler.onCommitAsync(any)).thenAnswer((_) async {});

      final runner = TransactionalRunner(
        store: mockStore,
        commitHandler: mockCommitHandler,
      );

      // Act
      await runner.runAsync(() async {});

      // Assert — handler receives the exact list of committed events.
      verify(mockCommitHandler.onCommitAsync(events)).called(1);
    });

    test('not called on empty commit', () async {
      // Arrange
      when(mockSession.saveChangesAsync(maxRetries: anyNamed('maxRetries'))).thenAnswer((_) async => <ContinuumEvent>[]);

      final runner = TransactionalRunner(
        store: mockStore,
        commitHandler: mockCommitHandler,
      );

      // Act
      await runner.runAsync(() async {});

      // Assert
      verifyNever(mockCommitHandler.onCommitAsync(any));
    });

    test('not called when save fails', () async {
      // Arrange — save throws.
      when(mockSession.saveChangesAsync(maxRetries: anyNamed('maxRetries'))).thenThrow(
        const ConcurrencyException(
          streamId: StreamId('x'),
          expectedVersion: 0,
          actualVersion: 1,
        ),
      );

      final runner = TransactionalRunner(
        store: mockStore,
        commitHandler: mockCommitHandler,
      );

      // Act — suppress the expected error.
      try {
        await runner.runAsync(() async {});
      } catch (_) {
        // Expected.
      }

      // Assert
      verifyNever(mockCommitHandler.onCommitAsync(any));
    });
  });

  // --------------------------------------------------------------------------
  // 10.13 — Zone isolation: concurrent runAsync calls get independent sessions
  // --------------------------------------------------------------------------
  group('zone isolation', () {
    test('two concurrent runAsync calls get independent sessions', () async {
      // Arrange — each openSession call returns a distinct mock.
      final sessionA = MockContinuumSession();
      final sessionB = MockContinuumSession();

      when(sessionA.saveChangesAsync(maxRetries: anyNamed('maxRetries'))).thenAnswer((_) async => <ContinuumEvent>[]);
      when(sessionB.saveChangesAsync(maxRetries: anyNamed('maxRetries'))).thenAnswer((_) async => <ContinuumEvent>[]);

      var callCount = 0;
      when(mockStore.openSession()).thenAnswer((_) {
        callCount++;
        return callCount == 1 ? sessionA : sessionB;
      });

      final runner = TransactionalRunner(store: mockStore);

      // Track captured sessions from each zone.
      ContinuumSession? capturedA;
      ContinuumSession? capturedB;

      // Act — run two transactions concurrently.
      // Use a completer to ensure both zones are alive at the same time.
      final completerA = Completer<void>();
      final completerB = Completer<void>();

      final futureA = runner.runAsync(() async {
        capturedA = TransactionalRunner.currentSession;
        completerA.complete();
        // Wait for B to also be running.
        await completerB.future;
      });

      final futureB = runner.runAsync(() async {
        capturedB = TransactionalRunner.currentSession;
        completerB.complete();
        // Wait for A to also be running.
        await completerA.future;
      });

      await Future.wait([futureA, futureB]);

      // Assert — each zone got its own session.
      expect(
        capturedA,
        same(sessionA),
        reason: 'Zone A must use session A.',
      );
      expect(
        capturedB,
        same(sessionB),
        reason: 'Zone B must use session B.',
      );
      expect(
        capturedA,
        isNot(same(capturedB)),
        reason: 'Concurrent runAsync calls must NOT share sessions.',
      );
    });
  });
}
