import 'package:continuum/continuum.dart';
import 'package:continuum_state/continuum_state.dart';
import 'package:continuum_uow/continuum_uow.dart' show ConcurrencyException, InvalidOperationException, PartialSaveException;
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../_fixtures/counter_fixtures.dart';

@GenerateNiceMocks([
  MockSpec<TargetPersistenceAdapter<Counter>>(),
])
import 'state_based_session_test.mocks.dart';

void main() {
  late MockTargetPersistenceAdapter mockAdapter;
  late AggregateFactoryRegistry factoryRegistry;
  late EventApplierRegistry applierRegistry;

  setUp(() {
    provideDummy<Counter>(Counter(0));
    mockAdapter = MockTargetPersistenceAdapter();
    factoryRegistry = buildCounterFactoryRegistry();
    applierRegistry = buildCounterApplierRegistry();
  });

  /// Creates a [StateBasedSession] with the given adapter map and mode.
  StateBasedSession createSession({
    Map<Type, TargetPersistenceAdapter<Object>>? adapters,
    EventApplicationMode applicationMode = EventApplicationMode.eager,
  }) {
    return StateBasedSession(
      adapters: adapters ?? {Counter: mockAdapter},
      aggregateFactories: factoryRegistry,
      eventAppliers: applierRegistry,
      applicationMode: applicationMode,
    );
  }

  group('loadAsync', () {
    test(
      'First call fetches from adapter, second call returns cached',
      () async {
        // Arrange
        final session = createSession();
        const streamId = StreamId('counter-1');
        final counter = Counter(42);

        when(mockAdapter.fetchAsync(streamId)).thenAnswer((_) async => counter);

        // Act — first load hits the adapter.
        final result1 = await session.loadAsync<Counter>(streamId);
        // Act — second load returns cached aggregate.
        final result2 = await session.loadAsync<Counter>(streamId);

        // Assert — both returns are the same instance.
        expect(identical(result1, result2), isTrue);
        expect(result1.value, equals(42));
        // Adapter should only have been called once.
        verify(mockAdapter.fetchAsync(streamId)).called(1);
      },
    );

    test(
      'Throws InvalidOperationException when no adapter registered',
      () async {
        // Arrange — session has no adapters registered.
        final session = createSession(adapters: {});
        const streamId = StreamId('counter-1');

        // Act & Assert
        expect(
          () => session.loadAsync<Counter>(streamId),
          throwsA(isA<InvalidOperationException>()),
        );
      },
    );

    test('Rethrows StreamNotFoundException from adapter', () async {
      // Arrange
      final session = createSession();
      const streamId = StreamId('missing-1');

      when(mockAdapter.fetchAsync(streamId)).thenAnswer(
        (_) async => throw const StreamNotFoundException(streamId: streamId),
      );

      // Act & Assert — StreamNotFoundException propagates unchanged.
      expect(
        () => session.loadAsync<Counter>(streamId),
        throwsA(isA<StreamNotFoundException>()),
      );
    });
  });

  group('applyAsync', () {
    test(
      'Creation event creates aggregate via factory without calling adapter',
      () async {
        // Arrange
        final session = createSession();
        const streamId = StreamId('counter-1');
        final creationEvent = CounterCreated(
          eventId: const EventId('e-1'),
          initial: 10,
        );

        // Act — apply creation event.
        final counter = await session.applyAsync<Counter>(
          streamId,
          creationEvent,
        );

        // Assert — aggregate created from factory, not from adapter.
        expect(counter.value, equals(10));
        verifyNever(mockAdapter.fetchAsync(any));
      },
    );

    test(
      'Mutation event on untracked stream calls fetchAsync first',
      () async {
        // Arrange
        final session = createSession();
        const streamId = StreamId('counter-1');
        final existingCounter = Counter(10);

        when(mockAdapter.fetchAsync(streamId)).thenAnswer(
          (_) async => existingCounter,
        );

        final mutationEvent = CounterIncremented(
          eventId: const EventId('e-1'),
          amount: 5,
        );

        // Act — apply mutation to untracked stream.
        final counter = await session.applyAsync<Counter>(
          streamId,
          mutationEvent,
        );

        // Assert — adapter was called to load, then event applied.
        verify(mockAdapter.fetchAsync(streamId)).called(1);
        expect(counter.value, equals(15));
      },
    );

    test(
      'Event on already-tracked stream applies directly without adapter',
      () async {
        // Arrange — load stream so it's tracked.
        final session = createSession();
        const streamId = StreamId('counter-1');
        final counter = Counter(10);

        when(mockAdapter.fetchAsync(streamId)).thenAnswer(
          (_) async => counter,
        );

        await session.loadAsync<Counter>(streamId);
        // Reset the mock so we can verify no more fetchAsync calls.
        clearInteractions(mockAdapter);

        final mutationEvent = CounterIncremented(
          eventId: const EventId('e-1'),
          amount: 5,
        );

        // Act — apply to already-tracked stream.
        final result = await session.applyAsync<Counter>(
          streamId,
          mutationEvent,
        );

        // Assert — adapter NOT called again, event applied directly.
        verifyNever(mockAdapter.fetchAsync(any));
        expect(result.value, equals(15));
      },
    );

    test(
      'Creation event on already-tracked stream throws InvalidOperationException',
      () async {
        // Arrange — create a stream so it's tracked.
        final session = createSession();
        const streamId = StreamId('counter-1');

        await session.applyAsync<Counter>(
          streamId,
          CounterCreated(eventId: const EventId('e-1'), initial: 1),
        );

        // Act & Assert — second creation event on same stream.
        expect(
          () => session.applyAsync<Counter>(
            streamId,
            CounterCreated(eventId: const EventId('e-2'), initial: 2),
          ),
          throwsA(isA<InvalidOperationException>()),
        );
      },
    );
  });

  group('EventApplicationMode', () {
    test('Eager mode applies event immediately', () async {
      // Arrange — eager mode is the default.
      final session = createSession(
        applicationMode: EventApplicationMode.eager,
      );
      const streamId = StreamId('counter-1');

      // Act
      final counter = await session.applyAsync<Counter>(
        streamId,
        CounterCreated(eventId: const EventId('e-1'), initial: 10),
      );
      await session.applyAsync<Counter>(
        streamId,
        CounterIncremented(eventId: const EventId('e-2'), amount: 5),
      );

      // Assert — aggregate reflects post-event state immediately.
      expect(counter.value, equals(15));
    });

    test('Deferred mode records event but aggregate unchanged', () async {
      // Arrange — deferred mode.
      final session = createSession(
        applicationMode: EventApplicationMode.deferred,
      );
      const streamId = StreamId('counter-1');

      // Act
      final counter = await session.applyAsync<Counter>(
        streamId,
        CounterCreated(eventId: const EventId('e-1'), initial: 10),
      );
      await session.applyAsync<Counter>(
        streamId,
        CounterIncremented(eventId: const EventId('e-2'), amount: 5),
      );

      // Assert — aggregate still at creation state until save.
      expect(counter.value, equals(10));
    });
  });

  group('saveChangesAsync', () {
    test(
      'Calls persistAsync with aggregate and pending operations',
      () async {
        // Arrange
        final session = createSession();
        const streamId = StreamId('counter-1');
        final creationEvent = CounterCreated(
          eventId: const EventId('e-1'),
          initial: 10,
        );
        final mutationEvent = CounterIncremented(
          eventId: const EventId('e-2'),
          amount: 5,
        );

        await session.applyAsync<Counter>(streamId, creationEvent);
        await session.applyAsync<Counter>(streamId, mutationEvent);

        when(mockAdapter.persistAsync(any, any, any)).thenAnswer(
          (_) async {},
        );

        // Act
        await session.saveChangesAsync();

        // Assert — persistAsync called with correct arguments.
        final captured = verify(
          mockAdapter.persistAsync(
            captureAny,
            captureAny,
            captureAny,
          ),
        ).captured;

        expect(captured[0], equals(streamId));
        expect((captured[1] as Counter).value, equals(15));
        expect((captured[2] as List).length, equals(2));
      },
    );

    test('Deferred mode applies events before persistAsync', () async {
      // Arrange
      final session = createSession(
        applicationMode: EventApplicationMode.deferred,
      );
      const streamId = StreamId('counter-1');

      await session.applyAsync<Counter>(
        streamId,
        CounterCreated(eventId: const EventId('e-1'), initial: 10),
      );
      await session.applyAsync<Counter>(
        streamId,
        CounterIncremented(eventId: const EventId('e-2'), amount: 5),
      );

      when(mockAdapter.persistAsync(any, any, any)).thenAnswer(
        (_) async {},
      );

      // Act
      await session.saveChangesAsync();

      // Assert — the aggregate passed to persistAsync has post-event state.
      final captured = verify(
        mockAdapter.persistAsync(
          captureAny,
          captureAny,
          captureAny,
        ),
      ).captured;

      // The aggregate should reflect all applied events.
      expect((captured[1] as Counter).value, equals(15));
    });

    test(
      'No pending operations completes without calling adapter',
      () async {
        // Arrange
        final session = createSession();

        // Act — save with no pending operations.
        await session.saveChangesAsync();

        // Assert
        verifyNever(mockAdapter.persistAsync(any, any, any));
      },
    );

    test('Pending operations cleared after successful save', () async {
      // Arrange
      final session = createSession();
      const streamId = StreamId('counter-1');

      await session.applyAsync<Counter>(
        streamId,
        CounterCreated(eventId: const EventId('e-1'), initial: 10),
      );

      when(mockAdapter.persistAsync(any, any, any)).thenAnswer(
        (_) async {},
      );

      // Act — first save.
      await session.saveChangesAsync();
      // Act — second save should have nothing to persist.
      await session.saveChangesAsync();

      // Assert — persistAsync was only called once (during first save).
      verify(mockAdapter.persistAsync(any, any, any)).called(1);
    });

    test('Multiple streams each call persistAsync independently', () async {
      // Arrange — two separate streams share the same adapter.
      final session = createSession();
      const streamId1 = StreamId('counter-1');
      const streamId2 = StreamId('counter-2');

      await session.applyAsync<Counter>(
        streamId1,
        CounterCreated(eventId: const EventId('e-1'), initial: 10),
      );
      await session.applyAsync<Counter>(
        streamId2,
        CounterCreated(eventId: const EventId('e-2'), initial: 20),
      );

      when(mockAdapter.persistAsync(any, any, any)).thenAnswer(
        (_) async {},
      );

      // Act
      await session.saveChangesAsync();

      // Assert — persistAsync called twice (once per stream).
      verify(mockAdapter.persistAsync(any, any, any)).called(2);
    });
  });

  group('Concurrency retry', () {
    test(
      'ConcurrencyException triggers re-fetch, re-apply, and retry',
      () async {
        // Arrange
        final session = createSession();
        const streamId = StreamId('counter-1');
        final existingCounter = Counter(10);

        when(mockAdapter.fetchAsync(streamId)).thenAnswer(
          (_) async => existingCounter,
        );

        await session.loadAsync<Counter>(streamId);

        await session.applyAsync<Counter>(
          streamId,
          CounterIncremented(eventId: const EventId('e-1'), amount: 5),
        );

        var callCount = 0;
        when(mockAdapter.persistAsync(any, any, any)).thenAnswer((_) async {
          callCount++;
          if (callCount == 1) {
            // First attempt fails with ConcurrencyException.
            throw ConcurrencyException(
              streamId: streamId,
              expectedVersion: 0,
              actualVersion: 1,
            );
          }
          // Second attempt succeeds.
        });

        // fetchAsync is called again during retry to get fresh state.
        final freshCounter = Counter(12);
        // After initial load, subsequent fetch returns fresh counter.
        when(mockAdapter.fetchAsync(streamId)).thenAnswer(
          (_) async => freshCounter,
        );

        // Act
        await session.saveChangesAsync(maxRetries: 1);

        // Assert — persistAsync called twice (initial + retry).
        verify(mockAdapter.persistAsync(any, any, any)).called(2);
      },
    );

    test(
      'Exhausted retries rethrows ConcurrencyException',
      () async {
        // Arrange
        final session = createSession();
        const streamId = StreamId('counter-1');

        when(mockAdapter.fetchAsync(streamId)).thenAnswer(
          (_) async => Counter(10),
        );

        await session.loadAsync<Counter>(streamId);

        await session.applyAsync<Counter>(
          streamId,
          CounterIncremented(eventId: const EventId('e-1'), amount: 5),
        );

        // persistAsync always throws ConcurrencyException.
        when(mockAdapter.persistAsync(any, any, any)).thenAnswer(
          (_) async {
            throw ConcurrencyException(
              streamId: streamId,
              expectedVersion: 0,
              actualVersion: 1,
            );
          },
        );

        // Act & Assert
        expect(
          () => session.saveChangesAsync(maxRetries: 1),
          throwsA(isA<ConcurrencyException>()),
        );
      },
    );

    test('MaxRetries parameter controls attempt count', () async {
      // Arrange
      final session = createSession();
      const streamId = StreamId('counter-1');

      when(mockAdapter.fetchAsync(streamId)).thenAnswer(
        (_) async => Counter(10),
      );

      await session.loadAsync<Counter>(streamId);

      await session.applyAsync<Counter>(
        streamId,
        CounterIncremented(eventId: const EventId('e-1'), amount: 5),
      );

      var persistCallCount = 0;
      when(mockAdapter.persistAsync(any, any, any)).thenAnswer((_) async {
        persistCallCount++;
        if (persistCallCount <= 2) {
          throw ConcurrencyException(
            streamId: streamId,
            expectedVersion: 0,
            actualVersion: 1,
          );
        }
        // Third attempt succeeds.
      });

      // Act — allow 3 retries (1 initial + 3 retries = 4 attempts).
      await session.saveChangesAsync(maxRetries: 3);

      // Assert — succeeded on third attempt.
      expect(persistCallCount, equals(3));
    });
  });

  group('Partial save', () {
    test(
      'First stream succeeds, second fails → PartialSaveException',
      () async {
        // Arrange
        final session = createSession();
        const streamId1 = StreamId('counter-1');
        const streamId2 = StreamId('counter-2');

        await session.applyAsync<Counter>(
          streamId1,
          CounterCreated(eventId: const EventId('e-1'), initial: 10),
        );
        await session.applyAsync<Counter>(
          streamId2,
          CounterCreated(eventId: const EventId('e-2'), initial: 20),
        );

        var callCount = 0;
        when(mockAdapter.persistAsync(any, any, any)).thenAnswer(
          (_) async {
            callCount++;
            if (callCount == 2) {
              // Second stream fails.
              throw const PermanentAdapterException(
                message: 'Validation failed',
              );
            }
          },
        );

        // Act & Assert
        expect(
          () => session.saveChangesAsync(),
          throwsA(
            isA<PartialSaveException>()
                .having(
                  (e) => e.savedStreams.length,
                  'savedStreams.length',
                  1,
                )
                .having(
                  (e) => e.failedStreams.length,
                  'failedStreams.length',
                  1,
                ),
          ),
        );
      },
    );

    test(
      'Saved streams cleared, failed streams retain pending operations',
      () async {
        // Arrange
        final session = createSession();
        const streamId1 = StreamId('counter-1');
        const streamId2 = StreamId('counter-2');

        await session.applyAsync<Counter>(
          streamId1,
          CounterCreated(eventId: const EventId('e-1'), initial: 10),
        );
        await session.applyAsync<Counter>(
          streamId2,
          CounterCreated(eventId: const EventId('e-2'), initial: 20),
        );

        var callCount = 0;
        when(mockAdapter.persistAsync(any, any, any)).thenAnswer(
          (_) async {
            callCount++;
            if (callCount == 2) {
              throw const PermanentAdapterException(
                message: 'Validation failed',
              );
            }
          },
        );

        // Act — catch the PartialSaveException.
        try {
          await session.saveChangesAsync();
        } on PartialSaveException {
          // Expected.
        }

        // Assert — check pending operations on the tracked entities.
        // Saved stream should have pending operations cleared.
        final savedEntity = session.trackedEntities[streamId1];
        expect(savedEntity!.pendingOperations, isEmpty);

        // Failed stream should retain its pending operations.
        final failedEntity = session.trackedEntities[streamId2];
        expect(failedEntity!.pendingOperations, isNotEmpty);
      },
    );

    test(
      'Single-stream failure rethrows original exception',
      () async {
        // Arrange — only one stream has pending operations.
        final session = createSession();
        const streamId = StreamId('counter-1');

        await session.applyAsync<Counter>(
          streamId,
          CounterCreated(eventId: const EventId('e-1'), initial: 10),
        );

        when(mockAdapter.persistAsync(any, any, any)).thenAnswer(
          (_) async {
            throw const PermanentAdapterException(message: 'Bad request');
          },
        );

        // Act & Assert — original exception, not PartialSaveException.
        expect(
          () => session.saveChangesAsync(),
          throwsA(isA<PermanentAdapterException>()),
        );
      },
    );

    test(
      'All-streams-fail rethrows first failure',
      () async {
        // Arrange — two streams, both fail.
        final session = createSession();
        const streamId1 = StreamId('counter-1');
        const streamId2 = StreamId('counter-2');

        await session.applyAsync<Counter>(
          streamId1,
          CounterCreated(eventId: const EventId('e-1'), initial: 10),
        );
        await session.applyAsync<Counter>(
          streamId2,
          CounterCreated(eventId: const EventId('e-2'), initial: 20),
        );

        when(mockAdapter.persistAsync(any, any, any)).thenAnswer(
          (_) async {
            throw const PermanentAdapterException(message: 'All fail');
          },
        );

        // Act & Assert — first failure thrown directly, not
        // PartialSaveException with empty savedStreams.
        expect(
          () => session.saveChangesAsync(),
          throwsA(isA<PermanentAdapterException>()),
        );
      },
    );
  });

  group('Exception propagation', () {
    test(
      'TransientAdapterException propagates unchanged from persistAsync',
      () async {
        // Arrange
        final session = createSession();
        const streamId = StreamId('counter-1');

        await session.applyAsync<Counter>(
          streamId,
          CounterCreated(eventId: const EventId('e-1'), initial: 10),
        );

        when(mockAdapter.persistAsync(any, any, any)).thenAnswer(
          (_) async {
            throw const TransientAdapterException(message: 'Network timeout');
          },
        );

        // Act & Assert — propagates unchanged.
        expect(
          () => session.saveChangesAsync(),
          throwsA(isA<TransientAdapterException>()),
        );
      },
    );

    test(
      'PermanentAdapterException propagates unchanged from persistAsync',
      () async {
        // Arrange
        final session = createSession();
        const streamId = StreamId('counter-1');

        await session.applyAsync<Counter>(
          streamId,
          CounterCreated(eventId: const EventId('e-1'), initial: 10),
        );

        when(mockAdapter.persistAsync(any, any, any)).thenAnswer(
          (_) async {
            throw const PermanentAdapterException(message: 'Forbidden');
          },
        );

        // Act & Assert
        expect(
          () => session.saveChangesAsync(),
          throwsA(isA<PermanentAdapterException>()),
        );
      },
    );

    test(
      'Unknown exception propagates unchanged from persistAsync',
      () async {
        // Arrange
        final session = createSession();
        const streamId = StreamId('counter-1');

        await session.applyAsync<Counter>(
          streamId,
          CounterCreated(eventId: const EventId('e-1'), initial: 10),
        );

        when(mockAdapter.persistAsync(any, any, any)).thenAnswer(
          (_) async {
            throw Exception('Raw unknown error');
          },
        );

        // Act & Assert — raw exception propagates, not wrapped.
        expect(
          () => session.saveChangesAsync(),
          throwsA(isA<Exception>()),
        );
      },
    );
  });

  group('Discard', () {
    test('DiscardStream clears pending operations for one stream', () async {
      // Arrange
      final session = createSession();
      const streamId = StreamId('counter-1');

      await session.applyAsync<Counter>(
        streamId,
        CounterCreated(eventId: const EventId('e-1'), initial: 10),
      );

      // Act
      session.discardStream(streamId);

      // Assert — save should have nothing to persist.
      await session.saveChangesAsync();
      verifyNever(mockAdapter.persistAsync(any, any, any));
    });

    test('DiscardAll clears pending operations for all streams', () async {
      // Arrange
      final session = createSession();
      const streamId1 = StreamId('counter-1');
      const streamId2 = StreamId('counter-2');

      await session.applyAsync<Counter>(
        streamId1,
        CounterCreated(eventId: const EventId('e-1'), initial: 10),
      );
      await session.applyAsync<Counter>(
        streamId2,
        CounterCreated(eventId: const EventId('e-2'), initial: 20),
      );

      // Act
      session.discardAll();

      // Assert — save should have nothing to persist.
      await session.saveChangesAsync();
      verifyNever(mockAdapter.persistAsync(any, any, any));
    });
  });

  group('DeleteAsync', () {
    test('Deleting a loaded entity calls adapter.deleteAsync on save', () async {
      // Arrange — load an entity, then mark it for deletion.
      final session = createSession();
      const streamId = StreamId('counter-1');
      final counter = Counter(42);

      when(mockAdapter.fetchAsync(streamId)).thenAnswer((_) async => counter);
      when(mockAdapter.deleteAsync(streamId)).thenAnswer((_) async {});

      await session.loadAsync<Counter>(streamId);

      // Act — mark for deletion and commit.
      session.deleteAsync(streamId);
      await session.saveChangesAsync();

      // Assert — deleteAsync was called on the adapter, persistAsync was not.
      verify(mockAdapter.deleteAsync(streamId)).called(1);
      verifyNever(mockAdapter.persistAsync(any, any, any));
    });

    test('Deleting a created entity calls adapter.deleteAsync on save', () async {
      // Arrange — create an entity via applyAsync, then mark for deletion.
      final session = createSession();
      const streamId = StreamId('counter-1');

      when(mockAdapter.deleteAsync(streamId)).thenAnswer((_) async {});

      await session.applyAsync<Counter>(
        streamId,
        CounterCreated(eventId: const EventId('e-1'), initial: 10),
      );

      // Act — mark for deletion and commit.
      session.deleteAsync(streamId);
      await session.saveChangesAsync();

      // Assert — deleteAsync was called; the creation was never persisted
      // because the entity was marked for deletion before commit.
      verify(mockAdapter.deleteAsync(streamId)).called(1);
      verifyNever(mockAdapter.persistAsync(any, any, any));
    });

    test('Deleting removes entity from identity map after save', () async {
      // Arrange — load, mark for deletion, save.
      final session = createSession();
      const streamId = StreamId('counter-1');
      final counter = Counter(42);

      when(mockAdapter.fetchAsync(streamId)).thenAnswer((_) async => counter);
      when(mockAdapter.deleteAsync(streamId)).thenAnswer((_) async {});

      await session.loadAsync<Counter>(streamId);
      session.deleteAsync(streamId);
      await session.saveChangesAsync();

      // Act — loading the same stream again should call fetchAsync
      // because it is no longer in the identity map.
      final freshCounter = Counter(99);
      when(mockAdapter.fetchAsync(streamId)).thenAnswer((_) async => freshCounter);

      final reloaded = await session.loadAsync<Counter>(streamId);

      // Assert — the reloaded entity is the fresh one, not the deleted one.
      expect(reloaded.value, equals(99));
      verify(mockAdapter.fetchAsync(streamId)).called(2);
    });

    test('DeleteAsync accepts untracked stream without throwing', () async {
      // Arrange
      final session = createSession();
      const streamId = StreamId('unknown-stream');

      when(mockAdapter.deleteAsync(streamId)).thenAnswer((_) async {});

      // Act — deleting an untracked stream should not throw.
      session.deleteAsync(streamId);
      await session.saveChangesAsync();

      // Assert — adapter.deleteAsync was called (idempotent no-op on
      // the backend side).
      verify(mockAdapter.deleteAsync(streamId)).called(1);
    });

    test('DeleteAsync failure does not remove entity from identity map', () async {
      // Arrange — load entity, mark for deletion, but adapter throws.
      final session = createSession();
      const streamId = StreamId('counter-1');
      final counter = Counter(42);

      when(mockAdapter.fetchAsync(streamId)).thenAnswer((_) async => counter);
      when(mockAdapter.deleteAsync(streamId)).thenThrow(
        StateError('Backend unavailable'),
      );

      await session.loadAsync<Counter>(streamId);
      session.deleteAsync(streamId);

      // Act & Assert — save should throw due to adapter failure.
      expect(
        () => session.saveChangesAsync(),
        throwsA(isA<StateError>()),
      );
    });

    test('Save with mixed persist and delete handles both', () async {
      // Arrange — create two entities, delete one, persist the other.
      final session = createSession();
      const streamId1 = StreamId('counter-1');
      const streamId2 = StreamId('counter-2');
      final counter2 = Counter(50);

      when(mockAdapter.fetchAsync(streamId2)).thenAnswer((_) async => counter2);
      when(mockAdapter.deleteAsync(streamId1)).thenAnswer((_) async {});
      when(mockAdapter.persistAsync(any, any, any)).thenAnswer((_) async {});

      // Create counter-1 and mark for deletion.
      await session.applyAsync<Counter>(
        streamId1,
        CounterCreated(eventId: const EventId('e-1'), initial: 10),
      );
      session.deleteAsync(streamId1);

      // Load counter-2 and apply a mutation.
      await session.loadAsync<Counter>(streamId2);
      await session.applyAsync<Counter>(
        streamId2,
        CounterIncremented(eventId: const EventId('e-2'), amount: 5),
      );

      // Act — save should handle both persist and delete.
      await session.saveChangesAsync();

      // Assert — deleteAsync for counter-1, persistAsync for counter-2.
      verify(mockAdapter.deleteAsync(streamId1)).called(1);
      verify(mockAdapter.persistAsync(streamId2, any, any)).called(1);
    });
  });
}
