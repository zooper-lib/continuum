import 'package:continuum/continuum.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../_fixtures/counter_fixtures.dart';

@GenerateNiceMocks([
  MockSpec<EventStore>(),
  MockSpec<AtomicEventStore>(),
])
import 'session_concurrency_retry_test.mocks.dart';

void main() {
  // Shared helpers scoped to the test file.
  late MockEventStore eventStore;
  late EventSourcingStore store;
  late JsonEventSerializer serializer;

  setUp(() {
    eventStore = MockEventStore();
    store = EventSourcingStore(
      eventStore: eventStore,
      aggregates: [buildGeneratedCounterAggregate()],
    );
    serializer = JsonEventSerializer(
      registry: buildCounterSerializerRegistry(),
    );
  });

  /// Builds a list of [StoredEvent]s for a counter stream that starts
  /// with a [CounterCreated] followed by any number of [CounterIncremented].
  List<StoredEvent> buildStoredEvents(
    StreamId streamId,
    List<ContinuumEvent> events,
  ) {
    return [
      for (final (index, event) in events.indexed)
        StoredEvent.fromContinuumEvent(
          continuumEvent: event,
          streamId: streamId,
          version: index,
          eventType: serializer.serialize(event).eventType,
          data: serializer.serialize(event).data,
        ),
    ];
  }

  // --------------------------------------------------------------------------
  // Backward compatibility — default maxRetries = 0
  // --------------------------------------------------------------------------
  group('saveChangesAsync with default maxRetries (0)', () {
    test('throws ConcurrencyException without retrying', () async {
      // Arrange — load a stream at version 0, then simulate a conflict.
      final streamId = const StreamId('counter-1');
      final created = CounterCreated(eventId: const EventId('e-1'), initial: 5);
      final stored = buildStoredEvents(streamId, [created]);

      when(eventStore.loadStreamAsync(streamId)).thenAnswer((_) async => stored);
      when(eventStore.appendEventsAsync(any, any, any)).thenThrow(
        ConcurrencyException(
          streamId: streamId,
          expectedVersion: 0,
          actualVersion: 1,
        ),
      );

      final session = store.openSession();
      await session.loadAsync<Counter>(streamId);

      // Mutate via applyAsync (already-tracked fast path).
      await session.applyAsync<Counter>(
        streamId,
        CounterIncremented(amount: 1),
      );

      // Act & Assert — must throw immediately, no reload attempt.
      await expectLater(
        session.saveChangesAsync(maxRetries: 0),
        throwsA(isA<ConcurrencyException>()),
      );

      // The store should NOT have been asked to reload the stream because
      // no retry was requested (maxRetries = 0).
      verify(eventStore.loadStreamAsync(streamId)).called(1);
    });
  });

  // --------------------------------------------------------------------------
  // Single retry — happy path
  // --------------------------------------------------------------------------
  group('saveChangesAsync with maxRetries = 1', () {
    test('retries once and succeeds after reloading latest version', () async {
      // Arrange — stream at version 0.
      final streamId = const StreamId('counter-retry-1');
      final created = CounterCreated(eventId: const EventId('e-1'), initial: 0);
      final initialEvents = buildStoredEvents(streamId, [created]);

      // After the conflict, a competing session added an increment event.
      final competingIncrement = CounterIncremented(
        eventId: const EventId('e-2'),
        amount: 7,
      );
      final updatedEvents = buildStoredEvents(
        streamId,
        [created, competingIncrement],
      );

      // First load: returns only the creation event (version 0).
      // Second load (retry): returns creation + competing increment (version 1).
      var loadCallCount = 0;
      when(eventStore.loadStreamAsync(streamId)).thenAnswer((_) async {
        loadCallCount++;
        if (loadCallCount == 1) return initialEvents;
        return updatedEvents;
      });

      // First append: conflict. Second append: succeeds.
      var appendCallCount = 0;
      when(eventStore.appendEventsAsync(any, any, any)).thenAnswer((_) async {
        appendCallCount++;
        if (appendCallCount == 1) {
          throw ConcurrencyException(
            streamId: streamId,
            expectedVersion: 0,
            actualVersion: 1,
          );
        }
        // Second call succeeds.
      });

      final session = store.openSession();
      await session.loadAsync<Counter>(streamId);

      // Mutate via applyAsync.
      await session.applyAsync<Counter>(
        streamId,
        CounterIncremented(amount: 3),
      );

      // Act — should succeed on the second attempt.
      await expectLater(session.saveChangesAsync(maxRetries: 1), completes);

      // Assert — the second append must use the updated expected version.
      final secondAppendArgs = verify(
        eventStore.appendEventsAsync(
          streamId,
          captureAny,
          captureAny,
        ),
      ).captured;

      // captured comes in pairs: [expectedVersion1, events1, expectedVersion2, events2]
      // First attempt used ExpectedVersion.exact(0), second used ExpectedVersion.exact(1).
      final secondExpectedVersion = secondAppendArgs[2] as ExpectedVersion;
      expect(
        secondExpectedVersion,
        equals(ExpectedVersion.exact(1)),
        reason: 'Retry must use the version from the freshly reloaded stream.',
      );

      // Verify the pending event was re-applied: version should be 2.
      final secondEvents = secondAppendArgs[3] as List<StoredEvent>;
      expect(secondEvents, hasLength(1));
      expect(
        secondEvents.single.version,
        equals(2),
        reason: 'Event version must follow the latest persisted version.',
      );
    });

    test('throws ConcurrencyException when retry also conflicts', () async {
      // Arrange — every append attempt conflicts.
      final streamId = const StreamId('counter-double-conflict');
      final created = CounterCreated(eventId: const EventId('e-1'), initial: 0);
      final initialEvents = buildStoredEvents(streamId, [created]);

      // Each reload returns one more event than the previous one.
      final increment1 = CounterIncremented(eventId: const EventId('e-2'), amount: 1);
      final eventsAfterFirstConflict = buildStoredEvents(streamId, [created, increment1]);

      var loadCallCount = 0;
      when(eventStore.loadStreamAsync(streamId)).thenAnswer((_) async {
        loadCallCount++;
        if (loadCallCount == 1) return initialEvents;
        return eventsAfterFirstConflict;
      });

      // Every append throws.
      when(eventStore.appendEventsAsync(any, any, any)).thenThrow(
        ConcurrencyException(
          streamId: streamId,
          expectedVersion: 0,
          actualVersion: 1,
        ),
      );

      final session = store.openSession();
      await session.loadAsync<Counter>(streamId);

      // Mutate via applyAsync.
      await session.applyAsync<Counter>(
        streamId,
        CounterIncremented(amount: 10),
      );

      // Act & Assert — with only 1 retry allowed, the second failure
      // must propagate to the caller.
      await expectLater(
        session.saveChangesAsync(maxRetries: 1),
        throwsA(isA<ConcurrencyException>()),
      );
    });
  });

  // --------------------------------------------------------------------------
  // Multiple retries
  // --------------------------------------------------------------------------
  group('saveChangesAsync with maxRetries > 1', () {
    test('succeeds on the third attempt (maxRetries = 3)', () async {
      // Arrange — two conflicts, then success on the third try.
      final streamId = const StreamId('counter-multi-retry');
      final created = CounterCreated(eventId: const EventId('e-1'), initial: 0);

      final eventsV0 = buildStoredEvents(streamId, [created]);
      final inc1 = CounterIncremented(eventId: const EventId('e-2'), amount: 1);
      final eventsV1 = buildStoredEvents(streamId, [created, inc1]);
      final inc2 = CounterIncremented(eventId: const EventId('e-3'), amount: 2);
      final eventsV2 = buildStoredEvents(streamId, [created, inc1, inc2]);

      var loadCallCount = 0;
      when(eventStore.loadStreamAsync(streamId)).thenAnswer((_) async {
        loadCallCount++;
        switch (loadCallCount) {
          case 1:
            return eventsV0;
          case 2:
            return eventsV1;
          default:
            return eventsV2;
        }
      });

      var appendCallCount = 0;
      when(eventStore.appendEventsAsync(any, any, any)).thenAnswer((_) async {
        appendCallCount++;
        if (appendCallCount <= 2) {
          throw ConcurrencyException(
            streamId: streamId,
            expectedVersion: 0,
            actualVersion: appendCallCount,
          );
        }
        // Third call succeeds.
      });

      final session = store.openSession();
      await session.loadAsync<Counter>(streamId);

      // Mutate via applyAsync.
      await session.applyAsync<Counter>(
        streamId,
        CounterIncremented(amount: 5),
      );

      // Act
      await expectLater(session.saveChangesAsync(maxRetries: 3), completes);

      // Assert — should have loaded stream 3 times (initial + 2 reloads).
      verify(eventStore.loadStreamAsync(streamId)).called(3);

      // And attempted to append 3 times.
      verify(eventStore.appendEventsAsync(any, any, any)).called(3);
    });

    test('exhausts all retries then throws', () async {
      // Arrange — every attempt conflicts.
      final streamId = const StreamId('counter-exhaust');
      final created = CounterCreated(eventId: const EventId('e-1'), initial: 0);
      final events = buildStoredEvents(streamId, [created]);

      when(eventStore.loadStreamAsync(streamId)).thenAnswer((_) async => events);
      when(eventStore.appendEventsAsync(any, any, any)).thenThrow(
        ConcurrencyException(
          streamId: streamId,
          expectedVersion: 0,
          actualVersion: 1,
        ),
      );

      final session = store.openSession();
      await session.loadAsync<Counter>(streamId);

      // Mutate via applyAsync.
      await session.applyAsync<Counter>(
        streamId,
        CounterIncremented(amount: 1),
      );

      // Act & Assert — 3 retries + 1 initial = 4 total attempts, all fail.
      await expectLater(
        session.saveChangesAsync(maxRetries: 3),
        throwsA(isA<ConcurrencyException>()),
      );

      // Initial load + 3 reloads for retries = 4 loads total.
      verify(eventStore.loadStreamAsync(streamId)).called(4);
      // 1 initial attempt + 3 retries = 4 append calls.
      verify(eventStore.appendEventsAsync(any, any, any)).called(4);
    });
  });

  // --------------------------------------------------------------------------
  // Aggregate state correctness after retry
  // --------------------------------------------------------------------------
  group('aggregate state after retry', () {
    test('in-session aggregate reflects merged state after successful retry', () async {
      // Arrange — stream at version 0, a competing event at version 1.
      final streamId = const StreamId('counter-state');
      final created = CounterCreated(eventId: const EventId('e-1'), initial: 10);
      final initialEvents = buildStoredEvents(streamId, [created]);

      final competingIncrement = CounterIncremented(
        eventId: const EventId('e-2'),
        amount: 5,
      );
      final updatedEvents = buildStoredEvents(
        streamId,
        [created, competingIncrement],
      );

      var loadCallCount = 0;
      when(eventStore.loadStreamAsync(streamId)).thenAnswer((_) async {
        loadCallCount++;
        if (loadCallCount == 1) return initialEvents;
        return updatedEvents;
      });

      var appendCallCount = 0;
      when(eventStore.appendEventsAsync(any, any, any)).thenAnswer((_) async {
        appendCallCount++;
        if (appendCallCount == 1) {
          throw ConcurrencyException(
            streamId: streamId,
            expectedVersion: 0,
            actualVersion: 1,
          );
        }
      });

      final session = store.openSession();
      final counter = await session.loadAsync<Counter>(streamId);

      // Our pending event via applyAsync.
      await session.applyAsync<Counter>(
        streamId,
        CounterIncremented(amount: 3),
      );

      // Before retry, the counter only knows about its own events.
      expect(counter.value, equals(13));

      // Act — save with retry.
      await session.saveChangesAsync(maxRetries: 1);

      // Assert — after retry, loading the aggregate from the session should
      // return the rebuilt instance that includes the competing event.
      final reloaded = await session.loadAsync<Counter>(streamId);

      // Expected: initial(10) + competing(5) + ours(3) = 18
      expect(
        reloaded.value,
        equals(18),
        reason:
            'After retry the aggregate must reflect both the '
            'competing event and our pending event.',
      );
    });

    test('multiple pending events are all re-applied after retry', () async {
      // Arrange — stream with one creation event, we add two increments.
      final streamId = const StreamId('counter-multi-pending');
      final created = CounterCreated(eventId: const EventId('e-1'), initial: 0);
      final initialEvents = buildStoredEvents(streamId, [created]);

      final competingEvent = CounterIncremented(
        eventId: const EventId('e-2'),
        amount: 100,
      );
      final updatedEvents = buildStoredEvents(
        streamId,
        [created, competingEvent],
      );

      var loadCallCount = 0;
      when(eventStore.loadStreamAsync(streamId)).thenAnswer((_) async {
        loadCallCount++;
        if (loadCallCount == 1) return initialEvents;
        return updatedEvents;
      });

      var appendCallCount = 0;
      when(eventStore.appendEventsAsync(any, any, any)).thenAnswer((_) async {
        appendCallCount++;
        if (appendCallCount == 1) {
          throw ConcurrencyException(
            streamId: streamId,
            expectedVersion: 0,
            actualVersion: 1,
          );
        }
      });

      final session = store.openSession();
      await session.loadAsync<Counter>(streamId);

      // Mutate via applyAsync — two events.
      await session.applyAsync<Counter>(
        streamId,
        CounterIncremented(amount: 1),
      );
      await session.applyAsync<Counter>(
        streamId,
        CounterIncremented(amount: 2),
      );

      // Act
      await session.saveChangesAsync(maxRetries: 1);

      // Assert — both pending events must be in the second append call.
      final captured = verify(
        eventStore.appendEventsAsync(streamId, captureAny, captureAny),
      ).captured;

      // Second call's events (index 2 = expectedVersion, index 3 = events).
      final retryEvents = captured[3] as List<StoredEvent>;
      expect(
        retryEvents,
        hasLength(2),
        reason: 'Both pending events must be re-applied and persisted.',
      );

      // Versions must follow the latest persisted version (1), so 2 and 3.
      expect(retryEvents[0].version, equals(2));
      expect(retryEvents[1].version, equals(3));
    });
  });

  // --------------------------------------------------------------------------
  // New streams (applyAsync with creation event) — no retry applicable
  // --------------------------------------------------------------------------
  group('new streams and retry', () {
    test('new stream conflict is not retried (duplicate stream error)', () async {
      // Arrange — attempt to create a stream that already exists.
      final streamId = const StreamId('counter-duplicate');

      when(eventStore.appendEventsAsync(any, any, any)).thenThrow(
        ConcurrencyException(
          streamId: streamId,
          expectedVersion: -1,
          actualVersion: 0,
        ),
      );

      final session = store.openSession();

      // Create stream via applyAsync.
      await session.applyAsync<Counter>(
        streamId,
        CounterCreated(eventId: const EventId('e-1'), initial: 0),
      );

      // Act & Assert — even with retries, a new-stream conflict cannot
      // be resolved by reloading (the stream was never loaded to begin with).
      // The exception propagates after the first retry fails again.
      await expectLater(
        session.saveChangesAsync(maxRetries: 1),
        throwsA(isA<ConcurrencyException>()),
      );
    });
  });

  // --------------------------------------------------------------------------
  // No pending events — no-op
  // --------------------------------------------------------------------------
  group('edge cases', () {
    test('saveChangesAsync with no pending events is a no-op even with retries', () async {
      final session = store.openSession();

      // Act — nothing to save.
      final committedEvents = await session.saveChangesAsync(maxRetries: 5);

      // Assert — no store interactions should occur and returns empty list.
      expect(committedEvents, isEmpty);
      verifyNever(eventStore.loadStreamAsync(any));
      verifyNever(eventStore.appendEventsAsync(any, any, any));
    });

    test('saveChangesAsync succeeds on first attempt without touching retry logic', () async {
      // Arrange — no conflict at all.
      final streamId = const StreamId('counter-no-conflict');
      final created = CounterCreated(eventId: const EventId('e-1'), initial: 0);
      final events = buildStoredEvents(streamId, [created]);

      when(eventStore.loadStreamAsync(streamId)).thenAnswer((_) async => events);
      when(eventStore.appendEventsAsync(any, any, any)).thenAnswer((_) async {});

      final session = store.openSession();
      await session.loadAsync<Counter>(streamId);

      // Mutate via applyAsync.
      await session.applyAsync<Counter>(
        streamId,
        CounterIncremented(amount: 1),
      );

      // Act
      final committedEvents = await session.saveChangesAsync(maxRetries: 5);

      // Assert — returns committed events.
      expect(committedEvents, hasLength(1));

      // Only the initial load, no reloads for retry.
      verify(eventStore.loadStreamAsync(streamId)).called(1);
      verify(eventStore.appendEventsAsync(any, any, any)).called(1);
    });
  });

  // --------------------------------------------------------------------------
  // Atomic (multi-stream) retry
  // --------------------------------------------------------------------------
  group('atomic multi-stream retry', () {
    test('retries atomic save when concurrency conflict occurs', () async {
      // Arrange — use an AtomicEventStore for multi-stream saves.
      final atomicStore = MockAtomicEventStore();
      final store = EventSourcingStore(
        eventStore: atomicStore,
        aggregates: [buildGeneratedCounterAggregate()],
      );

      final streamA = const StreamId('counter-a');
      final streamB = const StreamId('counter-b');

      final createdA = CounterCreated(eventId: const EventId('e-a1'), initial: 0);
      final createdB = CounterCreated(eventId: const EventId('e-b1'), initial: 0);
      final eventsA = buildStoredEvents(streamA, [createdA]);
      final eventsB = buildStoredEvents(streamB, [createdB]);

      // After conflict, stream A has a new event from a competing session.
      final competingEvent = CounterIncremented(
        eventId: const EventId('e-a2'),
        amount: 99,
      );
      final updatedEventsA = buildStoredEvents(streamA, [createdA, competingEvent]);

      var loadCountA = 0;
      when(atomicStore.loadStreamAsync(streamA)).thenAnswer((_) async {
        loadCountA++;
        if (loadCountA == 1) return eventsA;
        return updatedEventsA;
      });
      when(atomicStore.loadStreamAsync(streamB)).thenAnswer((_) async => eventsB);

      var atomicCallCount = 0;
      when(atomicStore.appendEventsToStreamsAsync(any)).thenAnswer((_) async {
        atomicCallCount++;
        if (atomicCallCount == 1) {
          throw ConcurrencyException(
            streamId: streamA,
            expectedVersion: 0,
            actualVersion: 1,
          );
        }
        // Second call succeeds.
      });

      final session = store.openSession();
      await session.loadAsync<Counter>(streamA);
      await session.loadAsync<Counter>(streamB);

      // Mutate via applyAsync.
      await session.applyAsync<Counter>(
        streamA,
        CounterIncremented(amount: 1),
      );
      await session.applyAsync<Counter>(
        streamB,
        CounterIncremented(amount: 2),
      );

      // Act
      await expectLater(session.saveChangesAsync(maxRetries: 1), completes);

      // Assert — atomic append should have been called twice.
      verify(atomicStore.appendEventsToStreamsAsync(any)).called(2);

      // Stream A should have been reloaded once for the retry.
      verify(atomicStore.loadStreamAsync(streamA)).called(2);

      // Stream B should also have been reloaded once for consistency, since
      // the atomic save is all-or-nothing and both streams had pending events.
      verify(atomicStore.loadStreamAsync(streamB)).called(2);
    });
  });

  // --------------------------------------------------------------------------
  // Mixed: loaded stream + new stream in one session
  // --------------------------------------------------------------------------
  group('mixed loaded and new streams', () {
    test('retry reloads only the existing stream, not the new one', () async {
      // Arrange — one loaded stream at v0 and one new stream.
      final existingStreamId = const StreamId('counter-existing');
      final newStreamId = const StreamId('counter-new');

      final created = CounterCreated(eventId: const EventId('e-1'), initial: 0);
      final initialEvents = buildStoredEvents(existingStreamId, [created]);

      final competingEvent = CounterIncremented(
        eventId: const EventId('e-2'),
        amount: 50,
      );
      final updatedEvents = buildStoredEvents(
        existingStreamId,
        [created, competingEvent],
      );

      var loadCallCount = 0;
      when(eventStore.loadStreamAsync(existingStreamId)).thenAnswer((_) async {
        loadCallCount++;
        if (loadCallCount == 1) return initialEvents;
        return updatedEvents;
      });

      // The save falls back to per-stream when the store is not atomic.
      // We make the existing stream conflict on the first attempt.
      var appendCallCount = 0;
      when(eventStore.appendEventsAsync(any, any, any)).thenAnswer(
        (invocation) async {
          appendCallCount++;
          final appendStreamId = invocation.positionalArguments[0] as StreamId;

          // Conflict only on the existing stream's first attempt.
          if (appendStreamId == existingStreamId && appendCallCount <= 2) {
            throw ConcurrencyException(
              streamId: existingStreamId,
              expectedVersion: 0,
              actualVersion: 1,
            );
          }
          // Everything else succeeds.
        },
      );

      final session = store.openSession();
      await session.loadAsync<Counter>(existingStreamId);

      // Create new stream via applyAsync.
      await session.applyAsync<Counter>(
        newStreamId,
        CounterCreated(eventId: const EventId('e-n1'), initial: 0),
      );

      // Mutate the existing stream via applyAsync.
      await session.applyAsync<Counter>(
        existingStreamId,
        CounterIncremented(amount: 5),
      );

      // Act
      await session.saveChangesAsync(maxRetries: 2);

      // Assert — the new stream should NOT have been reloaded via
      // loadStreamAsync (it was created, not loaded).
      verify(eventStore.loadStreamAsync(existingStreamId)).called(greaterThanOrEqualTo(2));
      verifyNever(eventStore.loadStreamAsync(newStreamId));
    });
  });
}
