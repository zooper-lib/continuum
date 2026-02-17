import 'package:continuum/continuum.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../_fixtures/counter_fixtures.dart';

@GenerateNiceMocks([
  MockSpec<AggregatePersistenceAdapter<Counter>>(),
])
import 'state_based_session_test.mocks.dart';

void main() {
  late MockAggregatePersistenceAdapter mockAdapter;
  late AggregateFactoryRegistry factoryRegistry;
  late EventApplierRegistry applierRegistry;

  setUp(() {
    provideDummy<Counter>(Counter(0));
    mockAdapter = MockAggregatePersistenceAdapter();
    factoryRegistry = buildCounterFactoryRegistry();
    applierRegistry = buildCounterApplierRegistry();
  });

  /// Creates a [StateBasedSession] with the given adapter map and mode.
  StateBasedSession createSession({
    Map<Type, AggregatePersistenceAdapter<Object>>? adapters,
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
      '5.1 first call fetches from adapter, second call returns cached',
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
      '5.2 throws InvalidOperationException when no adapter registered',
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

    test('5.3 rethrows StreamNotFoundException from adapter', () async {
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
      '5.4 creation event creates aggregate via factory without calling adapter',
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
      '5.5 mutation event on untracked stream calls fetchAsync first',
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
      '5.6 event on already-tracked stream applies directly without adapter',
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
      '5.7 creation event on already-tracked stream throws InvalidOperationException',
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
    test('5.8 eager mode applies event immediately', () async {
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

    test('5.9 deferred mode records event but aggregate unchanged', () async {
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
      '5.10 calls persistAsync with aggregate and pending events',
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
        final committed = await session.saveChangesAsync();

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

        // Committed events returned.
        expect(committed, hasLength(2));
      },
    );

    test('5.11 deferred mode applies events before persistAsync', () async {
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
      '5.12 no pending events returns empty list without calling adapter',
      () async {
        // Arrange
        final session = createSession();

        // Act — save with no pending events.
        final committed = await session.saveChangesAsync();

        // Assert
        expect(committed, isEmpty);
        verifyNever(mockAdapter.persistAsync(any, any, any));
      },
    );

    test('5.13 pending events cleared after successful save', () async {
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
      final committed = await session.saveChangesAsync();

      // Assert — second call returns empty.
      expect(committed, isEmpty);
      // persistAsync was only called once (during first save).
      verify(mockAdapter.persistAsync(any, any, any)).called(1);
    });

    test('5.14 multiple streams each call persistAsync independently', () async {
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
      final committed = await session.saveChangesAsync();

      // Assert — persistAsync called twice (once per stream).
      verify(mockAdapter.persistAsync(any, any, any)).called(2);
      expect(committed, hasLength(2));
    });
  });

  group('concurrency retry', () {
    test(
      '5.15 ConcurrencyException triggers re-fetch, re-apply, and retry',
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
            throw const ConcurrencyException(
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
        final committed = await session.saveChangesAsync(maxRetries: 1);

        // Assert — succeeded on retry.
        expect(committed, hasLength(1));
        // persistAsync called twice (initial + retry).
        verify(mockAdapter.persistAsync(any, any, any)).called(2);
      },
    );

    test(
      '5.16 exhausted retries rethrows ConcurrencyException',
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
            throw const ConcurrencyException(
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

    test('5.17 maxRetries parameter controls attempt count', () async {
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
          throw const ConcurrencyException(
            streamId: streamId,
            expectedVersion: 0,
            actualVersion: 1,
          );
        }
        // Third attempt succeeds.
      });

      // Act — allow 3 retries (1 initial + 3 retries = 4 attempts).
      final committed = await session.saveChangesAsync(maxRetries: 3);

      // Assert — succeeded on third attempt.
      expect(committed, hasLength(1));
      expect(persistCallCount, equals(3));
    });
  });

  group('partial save', () {
    test(
      '5.18 first stream succeeds, second fails → PartialSaveException',
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
      '5.19 saved streams cleared, failed streams retain pending events',
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

        // Assert — check pending events on the streams.
        // Saved stream should have pending events cleared.
        final savedStreamState = session.streams[streamId1];
        expect(savedStreamState!.pendingEvents, isEmpty);

        // Failed stream should retain its pending events.
        final failedStreamState = session.streams[streamId2];
        expect(failedStreamState!.pendingEvents, isNotEmpty);
      },
    );

    test(
      '5.20 single-stream failure rethrows original exception',
      () async {
        // Arrange — only one stream has pending events.
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
      '5.21 all-streams-fail rethrows first failure',
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

  group('exception propagation', () {
    test(
      '5.22 TransientAdapterException propagates unchanged from persistAsync',
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
      '5.23 PermanentAdapterException propagates unchanged from persistAsync',
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
      '5.24 unknown exception propagates unchanged from persistAsync',
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

  group('discard', () {
    test('5.25 discardStream clears pending events for one stream', () async {
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
      final committed = await session.saveChangesAsync();
      expect(committed, isEmpty);
      verifyNever(mockAdapter.persistAsync(any, any, any));
    });

    test('5.26 discardAll clears pending events for all streams', () async {
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
      final committed = await session.saveChangesAsync();
      expect(committed, isEmpty);
      verifyNever(mockAdapter.persistAsync(any, any, any));
    });
  });
}
