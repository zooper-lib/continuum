import 'package:continuum/continuum.dart';
import 'package:test/test.dart';
import 'package:zooper_flutter_core/zooper_flutter_core.dart';

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
  });
}

// --- Test Fixtures ---

int _eventCounter = 0;

StoredEvent _createEvent({
  required String streamId,
  int version = 0,
}) {
  return StoredEvent(
    eventId: EventId('evt-${_eventCounter++}'),
    streamId: StreamId(streamId),
    version: version,
    eventType: 'test.counter_incremented',
    data: const {},
    occurredOn: DateTime.now(),
    metadata: const {},
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

class _TestEvent {}

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
