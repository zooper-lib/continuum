import 'package:continuum/continuum.dart';
import 'package:test/test.dart';

void main() {
  group('InlineProjectionExecutor', () {
    late ProjectionRegistry registry;
    late InMemoryReadModelStore<_CounterReadModel, StreamId> store;
    late InlineProjectionExecutor executor;

    setUp(() {
      registry = ProjectionRegistry();
      store = InMemoryReadModelStore<_CounterReadModel, StreamId>();
    });

    test('executeAsync does nothing when no projections registered', () async {
      executor = InlineProjectionExecutor(registry: registry);
      final event = _createEvent(streamId: 'stream-1');

      // Should not throw
      await executor.executeAsync([event]);

      expect(store.length, equals(0));
    });

    test('executeAsync creates initial read model for new stream', () async {
      final projection = _CounterProjection();
      registry.registerInline(projection, store);
      executor = InlineProjectionExecutor(registry: registry);

      final event = _createEvent(streamId: 'stream-1');
      await executor.executeAsync([event]);

      final readModel = await store.loadAsync(const StreamId('stream-1'));
      expect(readModel, isNotNull);
      expect(readModel!.count, equals(1));
    });

    test('executeAsync updates existing read model', () async {
      final projection = _CounterProjection();
      registry.registerInline(projection, store);
      executor = InlineProjectionExecutor(registry: registry);

      // Pre-populate read model
      await store.saveAsync(
        const StreamId('stream-1'),
        _CounterReadModel(streamId: 'stream-1', count: 5),
      );

      final event = _createEvent(streamId: 'stream-1');
      await executor.executeAsync([event]);

      final readModel = await store.loadAsync(const StreamId('stream-1'));
      expect(readModel!.count, equals(6));
    });

    test('executeAsync processes multiple events in order', () async {
      final projection = _CounterProjection();
      registry.registerInline(projection, store);
      executor = InlineProjectionExecutor(registry: registry);

      final events = [
        _createEvent(streamId: 'stream-1', version: 0),
        _createEvent(streamId: 'stream-1', version: 1),
        _createEvent(streamId: 'stream-1', version: 2),
      ];

      await executor.executeAsync(events);

      final readModel = await store.loadAsync(const StreamId('stream-1'));
      expect(readModel!.count, equals(3));
    });

    test('executeAsync processes events for multiple streams', () async {
      final projection = _CounterProjection();
      registry.registerInline(projection, store);
      executor = InlineProjectionExecutor(registry: registry);

      final events = [
        _createEvent(streamId: 'stream-1'),
        _createEvent(streamId: 'stream-2'),
        _createEvent(streamId: 'stream-1'),
      ];

      await executor.executeAsync(events);

      final readModel1 = await store.loadAsync(const StreamId('stream-1'));
      final readModel2 = await store.loadAsync(const StreamId('stream-2'));

      expect(readModel1!.count, equals(2));
      expect(readModel2!.count, equals(1));
    });

    test('executeAsync applies to multiple projections', () async {
      final projection1 = _CounterProjection('counter-1');
      final projection2 = _CounterProjection('counter-2');
      final store1 = InMemoryReadModelStore<_CounterReadModel, StreamId>();
      final store2 = InMemoryReadModelStore<_CounterReadModel, StreamId>();

      registry.registerInline(projection1, store1);
      registry.registerInline(projection2, store2);
      executor = InlineProjectionExecutor(registry: registry);

      final event = _createEvent(streamId: 'stream-1');
      await executor.executeAsync([event]);

      final readModel1 = await store1.loadAsync(const StreamId('stream-1'));
      final readModel2 = await store2.loadAsync(const StreamId('stream-1'));

      expect(readModel1!.count, equals(1));
      expect(readModel2!.count, equals(1));
    });

    test('executeAsync skips async projections', () async {
      final inlineProjection = _CounterProjection('inline');
      final asyncProjection = _CounterProjection('async');
      final inlineStore = InMemoryReadModelStore<_CounterReadModel, StreamId>();
      final asyncStore = InMemoryReadModelStore<_CounterReadModel, StreamId>();

      registry.registerInline(inlineProjection, inlineStore);
      registry.registerAsync(asyncProjection, asyncStore);
      executor = InlineProjectionExecutor(registry: registry);

      final event = _createEvent(streamId: 'stream-1');
      await executor.executeAsync([event]);

      expect(inlineStore.length, equals(1));
      expect(asyncStore.length, equals(0));
    });

    test('executeAsync propagates projection errors', () async {
      final failingProjection = _FailingProjection();
      final failingStore = InMemoryReadModelStore<int, StreamId>();

      registry.registerInline(failingProjection, failingStore);
      executor = InlineProjectionExecutor(registry: registry);

      final event = _createEvent(streamId: 'stream-1');

      await expectLater(
        executor.executeAsync([event]),
        throwsA(isA<StateError>()),
      );
    });

    test('executeAsync routes events only to matching projections', () async {
      // Arrange: Two projections that handle different event types.
      final storeA = InMemoryReadModelStore<int, StreamId>();
      final storeB = InMemoryReadModelStore<int, StreamId>();
      registry.registerInline(_CounterProjectionForA(), storeA);
      registry.registerInline(_CounterProjectionForB(), storeB);
      executor = InlineProjectionExecutor(registry: registry);

      final storedEventA = StoredEvent.fromContinuumEvent(
        continuumEvent: _TestEventA(eventId: EventId.fromUlid()),
        streamId: const StreamId('stream-1'),
        version: 0,
        eventType: 'test.a',
        data: const <String, dynamic>{},
      );

      // Act.
      await executor.executeAsync([storedEventA]);

      // Assert: Only the matching projection should be updated.
      // This matters because unrelated projections must not mutate read models.
      expect(await storeA.loadAsync(const StreamId('stream-1')), equals(1));
      expect(await storeB.loadAsync(const StreamId('stream-1')), isNull);
    });
  });
}

// --- Test Fixtures ---

int _eventCounter = 0;

StoredEvent _createEvent({
  required String streamId,
  int version = 0,
}) {
  final continuumEvent = _TestEvent(eventId: EventId('evt-${_eventCounter++}'));

  return StoredEvent.fromContinuumEvent(
    continuumEvent: continuumEvent,
    streamId: StreamId(streamId),
    version: version,
    eventType: 'test.counter_incremented',
    data: const <String, dynamic>{},
  );
}

class _CounterReadModel {
  final String streamId;
  final int count;

  _CounterReadModel({required this.streamId, required this.count});
}

class _CounterProjection extends SingleStreamProjection<_CounterReadModel> {
  final String _name;

  _CounterProjection([this._name = 'counter']);

  @override
  Set<Type> get handledEventTypes => {_TestEvent};

  @override
  String get projectionName => _name;

  @override
  _CounterReadModel createInitial(StreamId streamId) {
    return _CounterReadModel(streamId: streamId.value, count: 0);
  }

  @override
  _CounterReadModel apply(_CounterReadModel current, StoredEvent event) {
    return _CounterReadModel(
      streamId: current.streamId,
      count: current.count + 1,
    );
  }
}

final class _TestEvent implements ContinuumEvent {
  _TestEvent({
    required EventId eventId,
    DateTime? occurredOn,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : id = eventId,
       occurredOn = occurredOn ?? DateTime.now(),
       metadata = Map<String, Object?>.unmodifiable(metadata);

  @override
  final EventId id;

  @override
  final DateTime occurredOn;

  @override
  final Map<String, Object?> metadata;
}

final class _TestEventA implements ContinuumEvent {
  _TestEventA({required EventId eventId}) : id = eventId;

  @override
  final EventId id;

  @override
  DateTime get occurredOn => DateTime.now();

  @override
  Map<String, Object?> get metadata => const <String, Object?>{};
}

final class _TestEventB implements ContinuumEvent {
  _TestEventB({required EventId eventId}) : id = eventId;

  @override
  final EventId id;

  @override
  DateTime get occurredOn => DateTime.now();

  @override
  Map<String, Object?> get metadata => const <String, Object?>{};
}

final class _CounterProjectionForA extends SingleStreamProjection<int> {
  @override
  Set<Type> get handledEventTypes => const {_TestEventA};

  @override
  String get projectionName => 'counter-a';

  @override
  int createInitial(StreamId streamId) => 0;

  @override
  int apply(int current, StoredEvent event) => current + 1;
}

final class _CounterProjectionForB extends SingleStreamProjection<int> {
  @override
  Set<Type> get handledEventTypes => const {_TestEventB};

  @override
  String get projectionName => 'counter-b';

  @override
  int createInitial(StreamId streamId) => 0;

  @override
  int apply(int current, StoredEvent event) => current + 1;
}

class _FailingProjection extends SingleStreamProjection<int> {
  @override
  Set<Type> get handledEventTypes => {_TestEvent};

  @override
  String get projectionName => 'failing';

  @override
  int createInitial(StreamId streamId) => 0;

  @override
  int apply(int current, StoredEvent event) {
    throw StateError('Intentional failure for testing');
  }
}
