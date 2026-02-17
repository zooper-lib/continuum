import 'package:continuum/continuum.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../_fixtures/counter_fixtures.dart';

@GenerateNiceMocks([MockSpec<EventStore>()])
import 'session_apply_async_test.mocks.dart';

void main() {
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

  /// Builds a list of [StoredEvent]s for a counter stream.
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
  // 10.1 — Creation path: factory probe, aggregate creation, stream tracking
  // --------------------------------------------------------------------------
  group('applyAsync creation path', () {
    test('creates aggregate when a creation event is applied to a new stream', () async {
      // Arrange
      final streamId = const StreamId('counter-new');
      final session = store.openSession();

      // Act — apply a creation event to a stream that has never been loaded.
      final counter = await session.applyAsync<Counter>(
        streamId,
        CounterCreated(eventId: const EventId('e-1'), initial: 42),
      );

      // Assert — aggregate is created with the correct initial state.
      expect(counter, isA<Counter>());
      expect(
        counter.value,
        equals(42),
        reason: 'Creation event must set the initial counter value.',
      );

      // The store should NOT have been consulted — creation is local.
      verifyNever(eventStore.loadStreamAsync(any));
    });

    test('tracks the created aggregate for later retrieval via loadAsync', () async {
      // Arrange
      final streamId = const StreamId('counter-tracked');
      final session = store.openSession();

      // Act — create and then immediately load the same stream.
      await session.applyAsync<Counter>(
        streamId,
        CounterCreated(eventId: const EventId('e-1'), initial: 10),
      );
      final loaded = await session.loadAsync<Counter>(streamId);

      // Assert — the cached instance is returned, not a new one.
      expect(
        loaded.value,
        equals(10),
        reason: 'loadAsync must return the same aggregate created via applyAsync.',
      );

      // No store load should occur because the stream is already tracked.
      verifyNever(eventStore.loadStreamAsync(any));
    });

    test('persists the creation event on saveChangesAsync', () async {
      // Arrange
      final streamId = const StreamId('counter-persist');
      final session = store.openSession();

      when(eventStore.appendEventsAsync(any, any, any, aggregateType: anyNamed('aggregateType'))).thenAnswer((_) async {});

      await session.applyAsync<Counter>(
        streamId,
        CounterCreated(eventId: const EventId('e-1'), initial: 0),
      );

      // Act
      final committed = await session.saveChangesAsync();

      // Assert — one creation event persisted with noStream expected version.
      expect(committed, hasLength(1));
      expect(committed.first, isA<CounterCreated>());

      final captured = verify(
        eventStore.appendEventsAsync(streamId, captureAny, captureAny, aggregateType: anyNamed('aggregateType')),
      ).captured;

      // First capture is the expected version.
      final expectedVersion = captured[0] as ExpectedVersion;
      expect(
        expectedVersion,
        equals(ExpectedVersion.noStream),
        reason: 'New streams must use ExpectedVersion.noStream.',
      );
    });
  });

  // --------------------------------------------------------------------------
  // 10.2 — Mutation path: load from store, apply event
  // --------------------------------------------------------------------------
  group('applyAsync mutation path', () {
    test('loads aggregate from store and applies mutation event', () async {
      // Arrange — an existing stream in the store.
      final streamId = const StreamId('counter-existing');
      final created = CounterCreated(eventId: const EventId('e-1'), initial: 5);
      final stored = buildStoredEvents(streamId, [created]);

      when(eventStore.loadStreamAsync(streamId)).thenAnswer((_) async => stored);

      final session = store.openSession();

      // Act — apply a mutation event to a stream that hasn't been loaded yet.
      // applyAsync should automatically load the stream first.
      final counter = await session.applyAsync<Counter>(
        streamId,
        CounterIncremented(amount: 3),
      );

      // Assert — the aggregate was loaded from the store and the event applied.
      expect(
        counter.value,
        equals(8),
        reason: 'Initial 5 + increment 3 = 8.',
      );

      // The store was consulted to load the stream.
      verify(eventStore.loadStreamAsync(streamId)).called(1);
    });

    test('throws InvalidOperationException for mutation on non-existent stream', () async {
      // Arrange — empty stream (no events stored).
      final streamId = const StreamId('counter-missing');

      when(eventStore.loadStreamAsync(streamId)).thenAnswer((_) async => []);

      final session = store.openSession();

      // Act & Assert — mutation on a stream with no persisted events
      // must throw InvalidOperationException with guidance about the
      // missing creation factory.
      await expectLater(
        session.applyAsync<Counter>(
          streamId,
          CounterIncremented(amount: 1),
        ),
        throwsA(isA<InvalidOperationException>()),
      );
    });
  });

  // --------------------------------------------------------------------------
  // 10.3 — Already-tracked fast path
  // --------------------------------------------------------------------------
  group('applyAsync already-tracked fast path', () {
    test('applies mutation to a previously loaded aggregate without reloading', () async {
      // Arrange — load the aggregate explicitly first.
      final streamId = const StreamId('counter-fast');
      final created = CounterCreated(eventId: const EventId('e-1'), initial: 10);
      final stored = buildStoredEvents(streamId, [created]);

      when(eventStore.loadStreamAsync(streamId)).thenAnswer((_) async => stored);

      final session = store.openSession();
      await session.loadAsync<Counter>(streamId);

      // Act — apply mutation to already-tracked stream.
      final counter = await session.applyAsync<Counter>(
        streamId,
        CounterIncremented(amount: 7),
      );

      // Assert — event applied, aggregate state updated.
      expect(counter.value, equals(17));

      // Only one load: the initial explicit load. The applyAsync did not
      // trigger a second load.
      verify(eventStore.loadStreamAsync(streamId)).called(1);
    });

    test('applies multiple mutations to a tracked stream cumulatively', () async {
      // Arrange
      final streamId = const StreamId('counter-multi');
      final session = store.openSession();

      await session.applyAsync<Counter>(
        streamId,
        CounterCreated(eventId: const EventId('e-1'), initial: 0),
      );

      // Act — apply several mutation events sequentially.
      await session.applyAsync<Counter>(streamId, CounterIncremented(amount: 1));
      await session.applyAsync<Counter>(streamId, CounterIncremented(amount: 2));
      final counter = await session.applyAsync<Counter>(
        streamId,
        CounterIncremented(amount: 3),
      );

      // Assert — all mutations applied: 0 + 1 + 2 + 3 = 6.
      expect(
        counter.value,
        equals(6),
        reason: 'All sequential mutations must accumulate.',
      );
    });
  });

  // --------------------------------------------------------------------------
  // 10.4 — Strict creation guard: InvalidOperationException
  // --------------------------------------------------------------------------
  group('applyAsync strict creation guard', () {
    test('throws InvalidOperationException when creation event applied to tracked stream', () async {
      // Arrange — create a stream first.
      final streamId = const StreamId('counter-guard');
      final session = store.openSession();

      await session.applyAsync<Counter>(
        streamId,
        CounterCreated(eventId: const EventId('e-1'), initial: 0),
      );

      // Act & Assert — a second creation event on the same stream
      // is a programming error.
      await expectLater(
        session.applyAsync<Counter>(
          streamId,
          CounterCreated(eventId: const EventId('e-2'), initial: 99),
        ),
        throwsA(isA<InvalidOperationException>()),
      );
    });

    test('throws InvalidOperationException when creation event applied to loaded stream', () async {
      // Arrange — load an existing stream from the store.
      final streamId = const StreamId('counter-loaded-guard');
      final created = CounterCreated(eventId: const EventId('e-1'), initial: 5);
      final stored = buildStoredEvents(streamId, [created]);

      when(eventStore.loadStreamAsync(streamId)).thenAnswer((_) async => stored);

      final session = store.openSession();
      await session.loadAsync<Counter>(streamId);

      // Act & Assert — applying a creation event to a loaded (existing)
      // aggregate must throw.
      await expectLater(
        session.applyAsync<Counter>(
          streamId,
          CounterCreated(eventId: const EventId('e-2'), initial: 0),
        ),
        throwsA(isA<InvalidOperationException>()),
      );
    });
  });

  // --------------------------------------------------------------------------
  // 10.5 — Non-existent stream + mutation event
  // --------------------------------------------------------------------------
  group('applyAsync with non-existent stream and mutation event', () {
    test('throws InvalidOperationException when mutation event targets empty stream', () async {
      // Arrange — the store returns an empty event list (stream doesn't exist).
      final streamId = const StreamId('counter-phantom');

      when(eventStore.loadStreamAsync(streamId)).thenAnswer((_) async => []);

      final session = store.openSession();

      // Act & Assert
      await expectLater(
        session.applyAsync<Counter>(
          streamId,
          CounterIncremented(amount: 1),
        ),
        throwsA(isA<InvalidOperationException>()),
      );
    });
  });

  // --------------------------------------------------------------------------
  // 10.5b — Omitted type parameter (dynamic TAggregate) fallback
  // --------------------------------------------------------------------------
  group('applyAsync with omitted type parameter', () {
    test('creates aggregate via event-type-only factory scan when TAggregate is dynamic', () async {
      // Arrange — the user calls applyAsync without <Counter>.
      final streamId = const StreamId('counter-dynamic');
      final session = store.openSession();

      // Act — no generic type parameter, Dart infers dynamic.
      final result = await session.applyAsync(
        streamId,
        CounterCreated(eventId: const EventId('e-1'), initial: 99),
      );

      // Assert — the aggregate is created correctly despite dynamic.
      expect(result, isA<Counter>());
      expect(
        (result as Counter).value,
        equals(99),
        reason: 'Fallback event-type scan must find the Counter factory.',
      );

      // The store should NOT be consulted — creation is local.
      verifyNever(eventStore.loadStreamAsync(any));
    });

    test('strict creation guard works for omitted type parameter', () async {
      // Arrange — create an aggregate first, then try applying a
      // creation event to the same stream without a type parameter.
      final streamId = const StreamId('counter-guard-dynamic');
      final session = store.openSession();

      await session.applyAsync(
        streamId,
        CounterCreated(eventId: const EventId('e-1'), initial: 10),
      );

      // Act & Assert — second creation event on tracked stream must throw.
      await expectLater(
        session.applyAsync(
          streamId,
          CounterCreated(eventId: const EventId('e-2'), initial: 20),
        ),
        throwsA(isA<InvalidOperationException>()),
      );
    });
  });

  // --------------------------------------------------------------------------
  // 10.6 — saveChangesAsync returns committed events
  // --------------------------------------------------------------------------
  group('saveChangesAsync returns committed events', () {
    test('returns events from a single stream', () async {
      // Arrange
      final streamId = const StreamId('counter-single');
      final session = store.openSession();

      when(eventStore.appendEventsAsync(any, any, any, aggregateType: anyNamed('aggregateType'))).thenAnswer((_) async {});

      await session.applyAsync<Counter>(
        streamId,
        CounterCreated(eventId: const EventId('e-1'), initial: 0),
      );
      await session.applyAsync<Counter>(
        streamId,
        CounterIncremented(amount: 5),
      );

      // Act
      final committed = await session.saveChangesAsync();

      // Assert — both events returned in order.
      expect(committed, hasLength(2));
      expect(committed[0], isA<CounterCreated>());
      expect(committed[1], isA<CounterIncremented>());
    });

    test('returns empty list when no events are pending', () async {
      // Arrange — session with nothing staged.
      final session = store.openSession();

      // Act
      final committed = await session.saveChangesAsync();

      // Assert
      expect(
        committed,
        isEmpty,
        reason: 'No pending events → empty committed list.',
      );
    });

    test('returns events from multiple streams', () async {
      // Arrange — create two streams with one event each.
      final streamA = const StreamId('counter-a');
      final streamB = const StreamId('counter-b');
      final session = store.openSession();

      when(eventStore.appendEventsAsync(any, any, any, aggregateType: anyNamed('aggregateType'))).thenAnswer((_) async {});

      await session.applyAsync<Counter>(
        streamA,
        CounterCreated(eventId: const EventId('e-a'), initial: 0),
      );
      await session.applyAsync<Counter>(
        streamB,
        CounterCreated(eventId: const EventId('e-b'), initial: 0),
      );

      // Act
      final committed = await session.saveChangesAsync();

      // Assert — one event per stream.
      expect(
        committed,
        hasLength(2),
        reason: 'Two streams with one event each → two committed events.',
      );
    });
  });
}
