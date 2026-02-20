import 'package:continuum/continuum.dart';
import 'package:continuum_event_sourcing/continuum_event_sourcing.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../_fixtures/counter_fixtures.dart';

@GenerateNiceMocks([
  MockSpec<EventStore>(),
  MockSpec<AtomicEventStore>(),
])
import 'session_load_all_async_test.mocks.dart';

void main() {
  late MockEventStore eventStore;
  late EventSourcingStore store;
  late JsonEventSerializer serializer;

  setUp(() {
    eventStore = MockEventStore();
    store = EventSourcingStore(
      eventStore: eventStore,
      targets: [buildGeneratedCounterAggregate()],
    );
    serializer = JsonEventSerializer(
      registry: buildCounterSerializerRegistry(),
    );
  });

  /// Builds a list of [StoredEvent]s from domain events.
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
  // loadAllAsync — core behavior
  // --------------------------------------------------------------------------
  group('loadAllAsync', () {
    test('returns empty list when no streams of that type exist', () async {
      // Arrange — the store has no streams tagged with 'Counter'.
      when(eventStore.getStreamIdsByAggregateTypeAsync(any)).thenAnswer((_) async => []);

      final session = store.openSession();

      // Act
      final result = await session.loadAllAsync<Counter>();

      // Assert — no aggregates should be returned.
      expect(result, isEmpty);

      // Verify the correct type string was passed to the store.
      verify(eventStore.getStreamIdsByAggregateTypeAsync('Counter')).called(1);
    });

    test('loads all aggregates of the requested type', () async {
      // Arrange — two counter streams exist in the store.
      final streamId1 = const StreamId('counter-1');
      final streamId2 = const StreamId('counter-2');

      final stored1 = buildStoredEvents(streamId1, [
        CounterCreated(eventId: const EventId('e-1'), initial: 10),
      ]);
      final stored2 = buildStoredEvents(streamId2, [
        CounterCreated(eventId: const EventId('e-2'), initial: 20),
        CounterIncremented(eventId: const EventId('e-3'), amount: 5),
      ]);

      when(eventStore.getStreamIdsByAggregateTypeAsync('Counter')).thenAnswer((_) async => [streamId1, streamId2]);
      when(eventStore.loadStreamAsync(streamId1)).thenAnswer((_) async => stored1);
      when(eventStore.loadStreamAsync(streamId2)).thenAnswer((_) async => stored2);

      final session = store.openSession();

      // Act
      final counters = await session.loadAllAsync<Counter>();

      // Assert — both counters should be loaded with correct state.
      expect(counters, hasLength(2));

      // Sort by value for deterministic assertion order.
      counters.sort((a, b) => a.value.compareTo(b.value));
      expect(
        counters[0].value,
        equals(10),
        reason: 'First counter was created with initial=10.',
      );
      expect(
        counters[1].value,
        equals(25),
        reason: 'Second counter: initial=20 + increment=5 = 25.',
      );
    });

    test('returns cached aggregates for already-tracked streams', () async {
      // Arrange — load a counter explicitly, then call loadAllAsync.
      final streamId = const StreamId('counter-cached');

      final stored = buildStoredEvents(streamId, [
        CounterCreated(eventId: const EventId('e-1'), initial: 42),
      ]);

      when(eventStore.getStreamIdsByAggregateTypeAsync('Counter')).thenAnswer((_) async => [streamId]);
      when(eventStore.loadStreamAsync(streamId)).thenAnswer((_) async => stored);

      final session = store.openSession();

      // Load explicitly first — this puts the aggregate in the identity map.
      final preloaded = await session.loadAsync<Counter>(streamId);

      // Act — loadAllAsync should use the cached instance.
      final allCounters = await session.loadAllAsync<Counter>();

      // Assert — same identity, no second store load.
      expect(allCounters, hasLength(1));
      expect(
        identical(allCounters.first, preloaded),
        isTrue,
        reason: 'loadAllAsync must return the cached instance, not a new one.',
      );

      // The store was loaded only once (the explicit loadAsync call).
      verify(eventStore.loadStreamAsync(streamId)).called(1);
    });

    test('returns aggregates created via applyAsync that are still in-session', () async {
      // Arrange — create a counter via applyAsync (not yet saved).
      final streamId = const StreamId('counter-unsaved');

      // The store returns the unsaved stream ID when queried. In a real
      // scenario the store wouldn't know about it until save, but the
      // session should still return in-memory tracked aggregates.
      // However, the store is what drives the list — so if the store
      // doesn't have it, loadAllAsync won't find it either.
      // This test verifies that if the store DOES return a stream ID
      // that is already tracked in-session, the cached version is used.
      when(eventStore.getStreamIdsByAggregateTypeAsync('Counter')).thenAnswer((_) async => [streamId]);

      final session = store.openSession();

      // Create via applyAsync — now tracked in session.
      final created = await session.applyAsync<Counter>(
        streamId,
        CounterCreated(eventId: const EventId('e-1'), initial: 77),
      );

      // Act
      final allCounters = await session.loadAllAsync<Counter>();

      // Assert — the in-session aggregate should be returned.
      expect(allCounters, hasLength(1));
      expect(
        identical(allCounters.first, created),
        isTrue,
        reason: 'In-session aggregate should be returned, not re-loaded.',
      );

      // No store load should have occurred — the aggregate was tracked.
      verifyNever(eventStore.loadStreamAsync(any));
    });

    test('passes the correct type string derived from TAggregate', () async {
      // Arrange — this test explicitly verifies the string that
      // loadAllAsync sends to getStreamIdsByAggregateTypeAsync.
      when(eventStore.getStreamIdsByAggregateTypeAsync(any)).thenAnswer((_) async => []);

      final session = store.openSession();

      // Act
      await session.loadAllAsync<Counter>();

      // Assert — must call with 'Counter', not some mangled or empty string.
      verify(eventStore.getStreamIdsByAggregateTypeAsync('Counter')).called(1);
      verifyNever(
        eventStore.getStreamIdsByAggregateTypeAsync(
          argThat(isNot(equals('Counter'))),
        ),
      );
    });
  });

  // --------------------------------------------------------------------------
  // aggregateType persistence — verifying the correct string reaches the store
  // --------------------------------------------------------------------------
  group('aggregateType persistence on saveChangesAsync', () {
    test('passes the correct aggregateType when saving a single new stream', () async {
      // Arrange
      final streamId = const StreamId('counter-new');
      final session = store.openSession();

      when(
        eventStore.appendEventsAsync(
          any,
          any,
          any,
          aggregateType: anyNamed('aggregateType'),
        ),
      ).thenAnswer((_) async {});

      await session.applyAsync<Counter>(
        streamId,
        CounterCreated(eventId: const EventId('e-1'), initial: 0),
      );

      // Act
      await session.saveChangesAsync(maxRetries: 0);

      // Assert — aggregateType must be 'Counter' (the Type.toString() value).
      final captured = verify(
        eventStore.appendEventsAsync(
          streamId,
          any,
          any,
          aggregateType: captureAnyNamed('aggregateType'),
        ),
      ).captured;

      expect(
        captured.single,
        equals('Counter'),
        reason:
            'aggregateType passed to the store must be the Dart Type.toString() '
            'of the aggregate — "Counter", not something else.',
      );
    });

    test('passes the correct aggregateType for a loaded-then-mutated stream', () async {
      // Arrange — load an existing stream, mutate it, save.
      final streamId = const StreamId('counter-loaded');

      final stored = buildStoredEvents(streamId, [
        CounterCreated(eventId: const EventId('e-1'), initial: 5),
      ]);

      when(eventStore.loadStreamAsync(streamId)).thenAnswer((_) async => stored);
      when(
        eventStore.appendEventsAsync(
          any,
          any,
          any,
          aggregateType: anyNamed('aggregateType'),
        ),
      ).thenAnswer((_) async {});

      final session = store.openSession();
      await session.loadAsync<Counter>(streamId);
      await session.applyAsync<Counter>(
        streamId,
        CounterIncremented(amount: 3),
      );

      // Act
      await session.saveChangesAsync(maxRetries: 0);

      // Assert
      final captured = verify(
        eventStore.appendEventsAsync(
          streamId,
          any,
          any,
          aggregateType: captureAnyNamed('aggregateType'),
        ),
      ).captured;

      expect(
        captured.single,
        equals('Counter'),
        reason: 'Loaded streams must preserve their aggregateType through to persistence.',
      );
    });

    test('passes the correct aggregateType when saving via atomic multi-stream path', () async {
      // Arrange — use AtomicEventStore so the multi-stream code path is taken.
      final atomicStore = MockAtomicEventStore();
      final eventSourcingStore = EventSourcingStore(
        eventStore: atomicStore,
        targets: [buildGeneratedCounterAggregate()],
      );

      when(atomicStore.appendEventsToStreamsAsync(any)).thenAnswer((_) async {});

      final session = eventSourcingStore.openSession();

      final stream1 = const StreamId('counter-a');
      final stream2 = const StreamId('counter-b');

      await session.applyAsync<Counter>(
        stream1,
        CounterCreated(eventId: const EventId('e-a'), initial: 1),
      );
      await session.applyAsync<Counter>(
        stream2,
        CounterCreated(eventId: const EventId('e-b'), initial: 2),
      );

      // Act
      await session.saveChangesAsync(maxRetries: 0);

      // Assert — both batches should carry 'Counter' as their aggregateType.
      final captured = verify(
        atomicStore.appendEventsToStreamsAsync(captureAny),
      ).captured;

      final batches = captured.single as Map<StreamId, StreamAppendBatch>;

      for (final entry in batches.entries) {
        expect(
          entry.value.aggregateType,
          equals('Counter'),
          reason:
              'Each batch in atomic writes must carry the correct aggregateType. '
              'Stream ${entry.key.value} had "${entry.value.aggregateType}".',
        );
      }
    });

    test('passes the correct aggregateType when type was inferred via event-only scan', () async {
      // Arrange — call applyAsync WITHOUT explicit type parameter.
      // The session scans by event type and resolves the aggregate type.
      final streamId = const StreamId('counter-inferred');
      final session = store.openSession();

      when(
        eventStore.appendEventsAsync(
          any,
          any,
          any,
          aggregateType: anyNamed('aggregateType'),
        ),
      ).thenAnswer((_) async {});

      // No explicit <Counter> — Dart infers dynamic.
      // ignore: inference_failure_on_function_invocation
      await session.applyAsync(
        streamId,
        CounterCreated(eventId: const EventId('e-1'), initial: 0),
      );

      // Act
      await session.saveChangesAsync(maxRetries: 0);

      // Assert — even with inferred type, the persisted aggregateType
      // must be 'Counter', not 'dynamic' or 'Object'.
      final captured = verify(
        eventStore.appendEventsAsync(
          streamId,
          any,
          any,
          aggregateType: captureAnyNamed('aggregateType'),
        ),
      ).captured;

      expect(
        captured.single,
        equals('Counter'),
        reason:
            'When type parameter is omitted, the session must still persist '
            'the resolved aggregate type (Counter), not dynamic or Object.',
      );
    });
  });
}
