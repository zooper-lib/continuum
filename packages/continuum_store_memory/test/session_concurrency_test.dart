import 'package:continuum/continuum.dart';
import 'package:continuum_store_memory/continuum_store_memory.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Minimal Counter aggregate and events for concurrency testing.
// ---------------------------------------------------------------------------

final class _Counter {
  int value;
  _Counter(this.value);
}

final class _CounterCreated implements ContinuumEvent {
  _CounterCreated({required this.initial, EventId? eventId}) : id = eventId ?? EventId.fromUlid(), occurredOn = DateTime.now(), metadata = const {};

  final int initial;

  @override
  final EventId id;

  @override
  final DateTime occurredOn;

  @override
  final Map<String, Object?> metadata;

  factory _CounterCreated.fromJson(Map<String, dynamic> json) {
    return _CounterCreated(
      eventId: EventId(json['eventId'] as String),
      initial: json['initial'] as int,
    );
  }
}

final class _CounterIncremented implements ContinuumEvent {
  _CounterIncremented({required this.amount, EventId? eventId}) : id = eventId ?? EventId.fromUlid(), occurredOn = DateTime.now(), metadata = const {};

  final int amount;

  @override
  final EventId id;

  @override
  final DateTime occurredOn;

  @override
  final Map<String, Object?> metadata;

  factory _CounterIncremented.fromJson(Map<String, dynamic> json) {
    return _CounterIncremented(
      eventId: EventId(json['eventId'] as String),
      amount: json['amount'] as int,
    );
  }
}

GeneratedAggregate _buildCounterAggregate() {
  return GeneratedAggregate(
    serializerRegistry: EventSerializerRegistry({
      _CounterCreated: EventSerializerEntry(
        eventType: 'counter.created',
        toJson: (event) {
          final created = event as _CounterCreated;
          return {'initial': created.initial};
        },
        fromJson: _CounterCreated.fromJson,
      ),
      _CounterIncremented: EventSerializerEntry(
        eventType: 'counter.incremented',
        toJson: (event) {
          final incremented = event as _CounterIncremented;
          return {'amount': incremented.amount};
        },
        fromJson: _CounterIncremented.fromJson,
      ),
    }),
    aggregateFactories: AggregateFactoryRegistry({
      _Counter: {
        _CounterCreated: (event) {
          final created = event as _CounterCreated;
          return _Counter(created.initial);
        },
      },
    }),
    eventAppliers: EventApplierRegistry({
      _Counter: {
        _CounterIncremented: (aggregate, event) {
          final counter = aggregate as _Counter;
          final incremented = event as _CounterIncremented;
          counter.value += incremented.amount;
        },
      },
    }),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('Session concurrency', () {
    late InMemoryEventStore eventStore;
    late EventSourcingStore store;

    setUp(() {
      eventStore = InMemoryEventStore();
      store = EventSourcingStore(
        eventStore: eventStore,
        aggregates: [_buildCounterAggregate()],
      );
    });

    test(
      'parallel load-append-save on the same stream loses no events '
      'when using maxRetries',
      () async {
        // Arrange — create a counter stream at version 0.
        final streamId = const StreamId('counter-concurrent');
        final seedSession = store.openSession();
        await seedSession.applyAsync<_Counter>(
          streamId,
          _CounterCreated(initial: 0),
        );
        await seedSession.saveChangesAsync(maxRetries: 0);

        // Two independent sessions load the same aggregate concurrently.
        final sessionA = store.openSession();
        final sessionB = store.openSession();

        // Both sessions load the aggregate — they each see version 0.
        final counterA = await sessionA.loadAsync<_Counter>(streamId);
        final counterB = await sessionB.loadAsync<_Counter>(streamId);

        // Each session applies one event to its own in-memory copy.
        await sessionA.applyAsync<_Counter>(streamId, _CounterIncremented(amount: 1));
        await sessionB.applyAsync<_Counter>(streamId, _CounterIncremented(amount: 10));

        // Sanity check — each session mutated its own copy independently.
        expect(counterA.value, equals(1));
        expect(counterB.value, equals(10));

        // Act — save both sessions.
        //
        // Session A saves first and succeeds.
        await sessionA.saveChangesAsync(maxRetries: 0);

        // Session B uses maxRetries to automatically handle the conflict.
        // It will detect the version mismatch, reload the stream with the
        // latest events (including Session A's event), re-apply its own
        // pending event, and retry the save.
        await sessionB.saveChangesAsync(maxRetries: 3);

        // Assert — both events must be present in the stream.
        //   version 0: CounterCreated(initial: 0)
        //   version 1: CounterIncremented(amount: 1)   — from session A
        //   version 2: CounterIncremented(amount: 10)  — from session B
        final events = await eventStore.loadStreamAsync(streamId);

        // All three events must be persisted — no event may be lost.
        expect(
          events,
          hasLength(3),
          reason:
              'Expected 3 events (1 creation + 2 increments) but got '
              '${events.length}. An event was silently lost.',
        );

        // The final counter value must reflect both increments.
        final verifySession = store.openSession();
        final counter = await verifySession.loadAsync<_Counter>(streamId);
        expect(
          counter.value,
          equals(11),
          reason:
              'Final counter should be 0 + 1 + 10 = 11, '
              'meaning both events were applied.',
        );
      },
    );

    test(
      'second save must throw ConcurrencyException on version conflict',
      () async {
        // Arrange — create a counter stream at version 0.
        final streamId = const StreamId('counter-conflict');
        final seedSession = store.openSession();
        await seedSession.applyAsync<_Counter>(
          streamId,
          _CounterCreated(initial: 0),
        );
        await seedSession.saveChangesAsync(maxRetries: 0);

        // Two sessions load the same stream — both see version 0.
        final sessionA = store.openSession();
        final sessionB = store.openSession();

        await sessionA.loadAsync<_Counter>(streamId);
        await sessionB.loadAsync<_Counter>(streamId);

        // Each session applies an event against the same stale version.
        await sessionA.applyAsync<_Counter>(streamId, _CounterIncremented(amount: 1));
        await sessionB.applyAsync<_Counter>(streamId, _CounterIncremented(amount: 10));

        // Act — session A saves first (succeeds, stream advances to v1).
        await sessionA.saveChangesAsync(maxRetries: 0);

        // Assert — session B must detect the conflict and throw.
        await expectLater(
          sessionB.saveChangesAsync(maxRetries: 0),
          throwsA(isA<ConcurrencyException>()),
        );
      },
    );

    test(
      'caller can retry after ConcurrencyException to preserve all events',
      () async {
        // Arrange — create a counter stream at version 0.
        final streamId = const StreamId('counter-retry');
        final seedSession = store.openSession();
        await seedSession.applyAsync<_Counter>(
          streamId,
          _CounterCreated(initial: 0),
        );
        await seedSession.saveChangesAsync(maxRetries: 0);

        // Two sessions load the same stream concurrently.
        final sessionA = store.openSession();
        final sessionB = store.openSession();

        await sessionA.loadAsync<_Counter>(streamId);
        await sessionB.loadAsync<_Counter>(streamId);

        await sessionA.applyAsync<_Counter>(streamId, _CounterIncremented(amount: 1));
        await sessionB.applyAsync<_Counter>(streamId, _CounterIncremented(amount: 10));

        // Session A saves first — succeeds.
        await sessionA.saveChangesAsync(maxRetries: 0);

        // Session B fails because of the version conflict.
        try {
          await sessionB.saveChangesAsync(maxRetries: 0);
          fail('Expected ConcurrencyException to be thrown');
        } on ConcurrencyException {
          // Caller must manually retry: open a new session, reload the
          // aggregate at the latest version, re-append the event, and save.
        }

        // Act — manual retry in a fresh session.
        final retrySession = store.openSession();
        final retryCounter = await retrySession.loadAsync<_Counter>(streamId);

        // Re-apply the event that was lost due to the conflict.
        await retrySession.applyAsync<_Counter>(streamId, _CounterIncremented(amount: 10));
        await retrySession.saveChangesAsync(maxRetries: 0);

        // Assert — all events are now present.
        final events = await eventStore.loadStreamAsync(streamId);
        expect(
          events,
          hasLength(3),
          reason: 'Expected 3 events after retry: creation + 2 increments.',
        );

        // The counter must reflect both increments.
        expect(retryCounter.value, equals(11));
      },
    );
  });
}
