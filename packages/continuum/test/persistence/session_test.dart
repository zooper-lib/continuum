import 'package:continuum/continuum.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../_fixtures/counter_fixtures.dart';

@GenerateNiceMocks([
  MockSpec<EventStore>(),
  MockSpec<AtomicEventStore>(),
])
import 'session_test.mocks.dart';

void main() {
  group('Session / EventSourcingStore integration', () {
    test('loadAsync caches within a session (one store load)', () async {
      final eventStore = MockEventStore();
      final aggregate = buildGeneratedCounterAggregate();
      final store = EventSourcingStore(eventStore: eventStore, aggregates: [aggregate]);

      final serializer = JsonEventSerializer(registry: buildCounterSerializerRegistry());
      final streamId = const StreamId('counter-1');

      final created = CounterCreated(
        eventId: const EventId('e-1'),
        initial: 10,
      );
      final incremented = CounterIncremented(
        eventId: const EventId('e-2'),
        amount: 5,
      );

      final stored = <StoredEvent>[];
      for (final (index, event) in [created, incremented].indexed) {
        final serialized = serializer.serialize(event);
        stored.add(
          StoredEvent.fromContinuumEvent(
            continuumEvent: event,
            streamId: streamId,
            version: index,
            eventType: serialized.eventType,
            data: serialized.data,
          ),
        );
      }

      // The session reconstructs the aggregate from these stored events.
      when(eventStore.loadStreamAsync(streamId)).thenAnswer((_) async => stored);

      // Ensure writes don't fail if accidentally invoked.
      when(eventStore.appendEventsAsync(any, any, any)).thenAnswer((_) async {});

      final session = store.openSession();

      final a1 = await session.loadAsync<Counter>(streamId);
      final a2 = await session.loadAsync<Counter>(streamId);

      expect(identical(a1, a2), isTrue);
      verify(eventStore.loadStreamAsync(streamId)).called(1);
      expect(a1.value, equals(15));
    });

    test('append throws if stream was not loaded/started', () {
      final eventStore = MockEventStore();
      final aggregate = buildGeneratedCounterAggregate();
      final store = EventSourcingStore(eventStore: eventStore, aggregates: [aggregate]);
      final session = store.openSession();

      expect(
        () => session.append(
          const StreamId('missing'),
          CounterIncremented(eventId: const EventId('e-1'), amount: 1),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('discardStream removes pending events but keeps mutated state', () {
      final eventStore = MockEventStore();
      final aggregate = buildGeneratedCounterAggregate();
      final store = EventSourcingStore(eventStore: eventStore, aggregates: [aggregate]);
      final session = store.openSession();

      final streamId = const StreamId('counter-2');
      final counter = session.startStream<Counter>(
        streamId,
        CounterCreated(eventId: const EventId('e-1'), initial: 1),
      );

      session.append(
        streamId,
        CounterIncremented(eventId: const EventId('e-2'), amount: 3),
      );

      expect(counter.value, equals(4));

      session.discardStream(streamId);

      expect(counter.value, equals(4));
    });

    test(
      'saveChangesAsync persists pending events for a new stream',
      () async {
        final eventStore = MockEventStore();
        final aggregate = buildGeneratedCounterAggregate();
        final store = EventSourcingStore(eventStore: eventStore, aggregates: [aggregate]);
        final session = store.openSession();

        when(eventStore.appendEventsAsync(any, any, any)).thenAnswer((_) async {});

        final streamId = const StreamId('counter-3');
        session.startStream<Counter>(
          streamId,
          CounterCreated(eventId: const EventId('e-1'), initial: 0),
        );
        session.append(
          streamId,
          CounterIncremented(eventId: const EventId('e-2'), amount: 1),
        );

        await expectLater(session.saveChangesAsync(), completes);

        final captured = verify(
          eventStore.appendEventsAsync(streamId, ExpectedVersion.noStream, captureAny),
        ).captured;

        final persistedEvents = captured.single as List<StoredEvent>;
        // Versions must start at 0 and be sequential.
        expect(persistedEvents.map((e) => e.version).toList(), equals([0, 1]));
      },
    );

    test('saveChangesAsync uses ExpectedVersion.exact for loaded streams', () async {
      final eventStore = MockEventStore();
      final aggregate = buildGeneratedCounterAggregate();
      final store = EventSourcingStore(eventStore: eventStore, aggregates: [aggregate]);

      final serializer = JsonEventSerializer(registry: buildCounterSerializerRegistry());
      final streamId = const StreamId('counter-existing');

      final created = CounterCreated(initial: 1);
      final storedCreated = StoredEvent.fromContinuumEvent(
        continuumEvent: created,
        streamId: streamId,
        version: 0,
        eventType: serializer.serialize(created).eventType,
        data: serializer.serialize(created).data,
      );

      when(eventStore.loadStreamAsync(streamId)).thenAnswer((_) async => [storedCreated]);
      when(eventStore.appendEventsAsync(any, any, any)).thenAnswer((_) async {});

      final session = store.openSession();
      final counter = await session.loadAsync<Counter>(streamId);
      expect(counter.value, equals(1));

      session.append(
        streamId,
        CounterIncremented(amount: 2),
      );

      await session.saveChangesAsync();

      final captured = verify(
        eventStore.appendEventsAsync(streamId, ExpectedVersion.exact(0), captureAny),
      ).captured;

      final persistedEvents = captured.single as List<StoredEvent>;
      // Existing stream at version 0 should get next event at version 1.
      expect(persistedEvents, hasLength(1));
      expect(persistedEvents.single.version, equals(1));
    });

    test(
      'BUG: saveChangesAsync should be atomic across streams (all-or-nothing)',
      () async {
        final eventStore = MockAtomicEventStore();
        var atomicAppendCalled = false;

        when(eventStore.appendEventsToStreamsAsync(any)).thenAnswer((_) async {
          atomicAppendCalled = true;
          // Simulate a transactional failure (no partial persistence).
          throw StateError('Injected atomic append failure');
        });

        final aggregate = buildGeneratedCounterAggregate();
        final store = EventSourcingStore(eventStore: eventStore, aggregates: [aggregate]);
        final session = store.openSession();

        final s1 = const StreamId('counter-a');
        final s2 = const StreamId('counter-b');

        session.startStream<Counter>(
          s1,
          CounterCreated(eventId: const EventId('e-a1'), initial: 0),
        );
        session.startStream<Counter>(
          s2,
          CounterCreated(eventId: const EventId('e-b1'), initial: 0),
        );

        await expectLater(session.saveChangesAsync(), throwsA(isA<StateError>()));

        expect(atomicAppendCalled, isTrue);
        verifyNever(eventStore.appendEventsAsync(any, any, any));
      },
    );
  });
}
