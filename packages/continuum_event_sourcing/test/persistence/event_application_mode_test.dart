import 'package:continuum/continuum.dart';
import 'package:continuum_event_sourcing/continuum_event_sourcing.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../_fixtures/counter_fixtures.dart';

@GenerateNiceMocks([MockSpec<EventStore>()])
import 'event_application_mode_test.mocks.dart';

void main() {
  late MockEventStore eventStore;
  late JsonEventSerializer serializer;

  setUp(() {
    eventStore = MockEventStore();
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
  // 10.7 — Eager mode: aggregate reflects event immediately after applyAsync
  // --------------------------------------------------------------------------
  group('EventApplicationMode.eager', () {
    late EventSourcingStore store;

    setUp(() {
      store = EventSourcingStore(
        eventStore: eventStore,
        targets: [buildGeneratedCounterAggregate()],
        applicationMode: EventApplicationMode.eager,
      );
    });

    test('aggregate state reflects creation event immediately', () async {
      // Arrange
      final streamId = const StreamId('eager-create');
      final session = store.openSession();

      // Act — apply creation event.
      final counter = await session.applyAsync<Counter>(
        streamId,
        CounterCreated(eventId: const EventId('e-1'), initial: 42),
      );

      // Assert — state is available before save.
      expect(
        counter.value,
        equals(42),
        reason: 'Eager mode: creation event must mutate aggregate immediately.',
      );
    });

    test('aggregate state reflects mutation event immediately', () async {
      // Arrange
      final streamId = const StreamId('eager-mutate');
      final session = store.openSession();

      await session.applyAsync<Counter>(
        streamId,
        CounterCreated(eventId: const EventId('e-1'), initial: 10),
      );

      // Act — apply mutation event.
      final counter = await session.applyAsync<Counter>(
        streamId,
        CounterIncremented(amount: 5),
      );

      // Assert — aggregate reflects the increment before save.
      expect(
        counter.value,
        equals(15),
        reason: 'Eager mode: mutation event must be applied before saveChangesAsync.',
      );
    });

    test('multiple mutations accumulate eagerly', () async {
      // Arrange
      final streamId = const StreamId('eager-multi');
      final session = store.openSession();

      await session.applyAsync<Counter>(
        streamId,
        CounterCreated(eventId: const EventId('e-1'), initial: 0),
      );

      // Act
      await session.applyAsync<Counter>(streamId, CounterIncremented(amount: 1));
      await session.applyAsync<Counter>(streamId, CounterIncremented(amount: 2));
      final counter = await session.applyAsync<Counter>(
        streamId,
        CounterIncremented(amount: 3),
      );

      // Assert — 0 + 1 + 2 + 3 = 6 before save.
      expect(
        counter.value,
        equals(6),
        reason: 'All eager mutations must accumulate before save.',
      );
    });
  });

  // --------------------------------------------------------------------------
  // 10.8 — Deferred mode: aggregate does not reflect event until save
  // --------------------------------------------------------------------------
  group('EventApplicationMode.deferred', () {
    late EventSourcingStore store;

    setUp(() {
      store = EventSourcingStore(
        eventStore: eventStore,
        targets: [buildGeneratedCounterAggregate()],
        applicationMode: EventApplicationMode.deferred,
      );
    });

    test('mutation event does not change aggregate state until save', () async {
      // Arrange — load an existing stream.
      final streamId = const StreamId('deferred-mutate');
      final created = CounterCreated(eventId: const EventId('e-1'), initial: 10);
      final stored = buildStoredEvents(streamId, [created]);

      when(eventStore.loadStreamAsync(streamId)).thenAnswer((_) async => stored);
      when(eventStore.appendEventsAsync(any, any, any, aggregateType: anyNamed('aggregateType'))).thenAnswer((_) async {});

      final session = store.openSession();
      final counter = await session.loadAsync<Counter>(streamId);

      // Act — apply mutation in deferred mode.
      await session.applyAsync<Counter>(
        streamId,
        CounterIncremented(amount: 5),
      );

      // Assert — aggregate should still show the old value.
      expect(
        counter.value,
        equals(10),
        reason: 'Deferred mode: aggregate must NOT reflect event before save.',
      );

      // Act — save to trigger deferred application.
      await session.saveChangesAsync();

      // Assert — after save, the aggregate should now reflect the event.
      expect(
        counter.value,
        equals(15),
        reason: 'Deferred mode: aggregate must reflect event after save.',
      );
    });

    test('multiple deferred mutations applied in order during save', () async {
      // Arrange
      final streamId = const StreamId('deferred-multi');
      final created = CounterCreated(eventId: const EventId('e-1'), initial: 0);
      final stored = buildStoredEvents(streamId, [created]);

      when(eventStore.loadStreamAsync(streamId)).thenAnswer((_) async => stored);
      when(eventStore.appendEventsAsync(any, any, any, aggregateType: anyNamed('aggregateType'))).thenAnswer((_) async {});

      final session = store.openSession();
      final counter = await session.loadAsync<Counter>(streamId);

      // Act — apply multiple mutations.
      await session.applyAsync<Counter>(streamId, CounterIncremented(amount: 1));
      await session.applyAsync<Counter>(streamId, CounterIncremented(amount: 2));
      await session.applyAsync<Counter>(streamId, CounterIncremented(amount: 3));

      // Assert — still zero before save.
      expect(
        counter.value,
        equals(0),
        reason: 'Deferred mode: no mutations visible before save.',
      );

      // Act — save.
      await session.saveChangesAsync();

      // Assert — all three mutations applied in order: 0 + 1 + 2 + 3 = 6.
      expect(
        counter.value,
        equals(6),
        reason: 'All deferred mutations must be applied in order during save.',
      );
    });

    test('creation event creates aggregate even in deferred mode', () async {
      // Arrange & Act — creation events are always applied immediately
      // because the aggregate instance must exist for tracking.
      final streamId = const StreamId('deferred-create');
      final session = store.openSession();

      final counter = await session.applyAsync<Counter>(
        streamId,
        CounterCreated(eventId: const EventId('e-1'), initial: 42),
      );

      // Assert — creation events always produce an aggregate, even in
      // deferred mode. The factory itself handles the initial state.
      expect(
        counter.value,
        equals(42),
        reason: 'Creation events are always applied immediately (factory call).',
      );
    });
  });
}
