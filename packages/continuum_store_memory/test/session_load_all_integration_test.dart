import 'package:continuum/continuum.dart' hide EventFromJsonFactory, EventSerializerEntry, EventSerializerRegistry, EventToJsonFactory, GeneratedAggregate;
import 'package:continuum_event_sourcing/continuum_event_sourcing.dart';
import 'package:continuum_store_memory/continuum_store_memory.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Minimal aggregate and event types for integration testing.
//
// Two separate aggregate types are defined to verify that
// loadAllAsync and getStreamIdsByAggregateTypeAsync correctly
// differentiate between aggregate types.
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

/// A second, independent aggregate type to test type-based filtering.
final class _Wallet {
  double balance;
  _Wallet(this.balance);
}

final class _WalletOpened implements ContinuumEvent {
  _WalletOpened({required this.initialBalance, EventId? eventId}) : id = eventId ?? EventId.fromUlid(), occurredOn = DateTime.now(), metadata = const {};

  final double initialBalance;

  @override
  final EventId id;

  @override
  final DateTime occurredOn;

  @override
  final Map<String, Object?> metadata;

  factory _WalletOpened.fromJson(Map<String, dynamic> json) {
    return _WalletOpened(
      eventId: EventId(json['eventId'] as String),
      initialBalance: (json['initialBalance'] as num).toDouble(),
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

GeneratedAggregate _buildWalletAggregate() {
  return GeneratedAggregate(
    serializerRegistry: EventSerializerRegistry({
      _WalletOpened: EventSerializerEntry(
        eventType: 'wallet.opened',
        toJson: (event) {
          final opened = event as _WalletOpened;
          return {'initialBalance': opened.initialBalance};
        },
        fromJson: _WalletOpened.fromJson,
      ),
    }),
    aggregateFactories: AggregateFactoryRegistry({
      _Wallet: {
        _WalletOpened: (event) {
          final opened = event as _WalletOpened;
          return _Wallet(opened.initialBalance);
        },
      },
    }),
    eventAppliers: const EventApplierRegistry.empty(),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late InMemoryEventStore eventStore;
  late EventSourcingStore store;

  setUp(() {
    eventStore = InMemoryEventStore();
    store = EventSourcingStore(
      eventStore: eventStore,
      aggregates: [_buildCounterAggregate(), _buildWalletAggregate()],
    );
  });

  group('loadAllAsync integration (real InMemoryEventStore)', () {
    test('full round-trip: create via applyAsync, save, reload in new session', () async {
      // Arrange — create two counters in session 1.
      final session1 = store.openSession();

      await session1.applyAsync<_Counter>(
        const StreamId('counter-1'),
        _CounterCreated(initial: 10),
      );
      await session1.applyAsync<_Counter>(
        const StreamId('counter-2'),
        _CounterCreated(initial: 20),
      );

      await session1.saveChangesAsync();

      // Act — open a new session and load all counters.
      final session2 = store.openSession();
      final counters = await session2.loadAllAsync<_Counter>();

      // Assert — both counters should be loaded with correct initial values.
      expect(counters, hasLength(2));

      final values = counters.map((c) => c.value).toList()..sort();
      expect(
        values,
        equals([10, 20]),
        reason: 'Both counters must be loaded with their creation values.',
      );
    });

    test('loadAllAsync returns mutated state after save', () async {
      // Arrange — create and mutate a counter.
      final session1 = store.openSession();

      await session1.applyAsync<_Counter>(
        const StreamId('counter-mutated'),
        _CounterCreated(initial: 5),
      );
      await session1.applyAsync<_Counter>(
        const StreamId('counter-mutated'),
        _CounterIncremented(amount: 7),
      );

      await session1.saveChangesAsync();

      // Act — load all in a fresh session.
      final session2 = store.openSession();
      final counters = await session2.loadAllAsync<_Counter>();

      // Assert — the counter should reflect both creation and mutation.
      expect(counters, hasLength(1));
      expect(
        counters.single.value,
        equals(12),
        reason: 'initial=5 + increment=7 = 12',
      );
    });

    test('loadAllAsync filters by aggregate type — does not return other types', () async {
      // Arrange — create a counter AND a wallet.
      final session1 = store.openSession();

      await session1.applyAsync<_Counter>(
        const StreamId('counter-only'),
        _CounterCreated(initial: 42),
      );
      await session1.applyAsync<_Wallet>(
        const StreamId('wallet-only'),
        _WalletOpened(initialBalance: 100.0),
      );

      await session1.saveChangesAsync();

      // Act — load only counters.
      final session2 = store.openSession();
      final counters = await session2.loadAllAsync<_Counter>();

      // Assert — only the counter should be returned, not the wallet.
      expect(counters, hasLength(1));
      expect(counters.single.value, equals(42));

      // Act — load only wallets.
      final session3 = store.openSession();
      final wallets = await session3.loadAllAsync<_Wallet>();

      // Assert — only the wallet should be returned.
      expect(wallets, hasLength(1));
      expect(wallets.single.balance, equals(100.0));
    });

    test('loadAllAsync returns empty list when no streams of that type exist', () async {
      // Arrange — only create wallets, no counters.
      final session1 = store.openSession();

      await session1.applyAsync<_Wallet>(
        const StreamId('wallet-1'),
        _WalletOpened(initialBalance: 50.0),
      );

      await session1.saveChangesAsync();

      // Act — try to load counters.
      final session2 = store.openSession();
      final counters = await session2.loadAllAsync<_Counter>();

      // Assert — no counters should be returned.
      expect(counters, isEmpty);
    });

    test('loadAllAsync returns empty list from a completely empty store', () async {
      // Act — nothing has been persisted.
      final session = store.openSession();
      final counters = await session.loadAllAsync<_Counter>();

      // Assert
      expect(counters, isEmpty);
    });

    test('aggregateType is preserved across multiple save operations', () async {
      // Arrange — create a counter, save, then mutate and save again.
      final session1 = store.openSession();
      await session1.applyAsync<_Counter>(
        const StreamId('counter-multi-save'),
        _CounterCreated(initial: 1),
      );
      await session1.saveChangesAsync();

      // Mutate in a second session.
      final session2 = store.openSession();
      await session2.loadAsync<_Counter>(const StreamId('counter-multi-save'));
      await session2.applyAsync<_Counter>(
        const StreamId('counter-multi-save'),
        _CounterIncremented(amount: 9),
      );
      await session2.saveChangesAsync();

      // Act — load all in a third session.
      final session3 = store.openSession();
      final counters = await session3.loadAllAsync<_Counter>();

      // Assert — the aggregate type tag must survive multiple writes.
      expect(counters, hasLength(1));
      expect(
        counters.single.value,
        equals(10),
        reason: 'initial=1 + increment=9 = 10',
      );
    });

    test('verifies the aggregateType string stored in the event store matches Type.toString()', () async {
      // Arrange — create a counter and save.
      final session = store.openSession();
      await session.applyAsync<_Counter>(
        const StreamId('counter-type-check'),
        _CounterCreated(initial: 0),
      );
      await session.saveChangesAsync();

      // Act — directly query the store with the expected type string.
      final streamIds = await eventStore.getStreamIdsByAggregateTypeAsync(
        (_Counter).toString(),
      );

      // Assert — the stored string must match the Dart Type.toString().
      expect(
        streamIds,
        hasLength(1),
        reason:
            'The store must find the stream when queried with the exact '
            'Type.toString() value. The stored aggregate type string must '
            'match "${(_Counter).toString()}".',
      );
      expect(streamIds.single.value, equals('counter-type-check'));
    });

    test('loadAllAsync combined with applyAsync in same session uses identity map', () async {
      // Arrange — create and save a counter.
      final session1 = store.openSession();
      await session1.applyAsync<_Counter>(
        const StreamId('counter-identity'),
        _CounterCreated(initial: 0),
      );
      await session1.saveChangesAsync();

      // Act — in a new session, load all, then mutate one of the loaded
      // aggregates, then load all again.
      final session2 = store.openSession();
      final firstLoad = await session2.loadAllAsync<_Counter>();
      expect(firstLoad, hasLength(1));

      // Mutate the loaded aggregate.
      await session2.applyAsync<_Counter>(
        const StreamId('counter-identity'),
        _CounterIncremented(amount: 5),
      );

      // Load all again — should return the same mutated instance.
      final secondLoad = await session2.loadAllAsync<_Counter>();

      // Assert — same identity, mutation reflected.
      expect(secondLoad, hasLength(1));
      expect(
        identical(firstLoad.single, secondLoad.single),
        isTrue,
        reason: 'The identity map must return the same instance.',
      );
      expect(
        secondLoad.single.value,
        equals(5),
        reason: 'Mutation must be reflected in the cached instance.',
      );
    });
  });
}
