import 'package:continuum/continuum.dart';
import 'package:test/test.dart';
import 'package:zooper_flutter_core/zooper_flutter_core.dart';

void main() {
  group('AsyncProjectionExecutor', () {
    late ProjectionRegistry registry;
    late InMemoryProjectionPositionStore positionStore;
    late InMemoryReadModelStore<_CounterReadModel, StreamId> readModelStore;
    late AsyncProjectionExecutor executor;

    setUp(() {
      registry = ProjectionRegistry();
      positionStore = InMemoryProjectionPositionStore();
      readModelStore = InMemoryReadModelStore<_CounterReadModel, StreamId>();
    });

    test('processEventsAsync does nothing when no projections registered', () async {
      executor = AsyncProjectionExecutor(
        registry: registry,
        positionStore: positionStore,
      );

      final event = _createEvent(streamId: 'stream-1', globalSequence: 1);
      final result = await executor.processEventsAsync([event]);

      expect(result.processed, equals(0));
      expect(result.failed, equals(0));
      expect(result.isSuccess, isTrue);
    });

    test('processEventsAsync does nothing with empty event list', () async {
      final projection = _CounterProjection();
      registry.registerAsync(projection, readModelStore);
      executor = AsyncProjectionExecutor(
        registry: registry,
        positionStore: positionStore,
      );

      final result = await executor.processEventsAsync([]);

      expect(result.processed, equals(0));
      expect(result.total, equals(0));
    });

    test('processEventsAsync creates initial read model', () async {
      final projection = _CounterProjection();
      registry.registerAsync(projection, readModelStore);
      executor = AsyncProjectionExecutor(
        registry: registry,
        positionStore: positionStore,
      );

      final event = _createEvent(streamId: 'stream-1', globalSequence: 1);
      await executor.processEventsAsync([event]);

      final readModel = await readModelStore.loadAsync(const StreamId('stream-1'));
      expect(readModel, isNotNull);
      expect(readModel!.count, equals(1));
    });

    test('processEventsAsync updates existing read model', () async {
      final projection = _CounterProjection();
      registry.registerAsync(projection, readModelStore);
      executor = AsyncProjectionExecutor(
        registry: registry,
        positionStore: positionStore,
      );

      // Pre-populate
      await readModelStore.saveAsync(
        const StreamId('stream-1'),
        _CounterReadModel(streamId: 'stream-1', count: 10),
      );

      final event = _createEvent(streamId: 'stream-1', globalSequence: 5);
      await executor.processEventsAsync([event]);

      final readModel = await readModelStore.loadAsync(const StreamId('stream-1'));
      expect(readModel!.count, equals(11));
    });

    test('processEventsAsync tracks position after success', () async {
      final projection = _CounterProjection();
      registry.registerAsync(projection, readModelStore);
      executor = AsyncProjectionExecutor(
        registry: registry,
        positionStore: positionStore,
      );

      final events = [
        _createEvent(streamId: 'stream-1', globalSequence: 10),
        _createEvent(streamId: 'stream-1', globalSequence: 11),
        _createEvent(streamId: 'stream-1', globalSequence: 12),
      ];

      await executor.processEventsAsync(events);

      final position = await positionStore.loadPositionAsync('counter');
      expect(position?.lastProcessedSequence, equals(12));
    });

    test('processEventsAsync skips inline projections', () async {
      final inlineProjection = _CounterProjection('inline');
      final asyncProjection = _CounterProjection('async');
      final inlineStore = InMemoryReadModelStore<_CounterReadModel, StreamId>();

      registry.registerInline(inlineProjection, inlineStore);
      registry.registerAsync(asyncProjection, readModelStore);
      executor = AsyncProjectionExecutor(
        registry: registry,
        positionStore: positionStore,
      );

      final event = _createEvent(streamId: 'stream-1', globalSequence: 1);
      await executor.processEventsAsync([event]);

      expect(inlineStore.length, equals(0));
      expect(readModelStore.length, equals(1));
    });

    test('processEventsAsync continues after projection failure', () async {
      final failingProjection = _FailingProjection();
      final workingProjection = _CounterProjection('working');
      final failingStore = InMemoryReadModelStore<int, StreamId>();
      final workingStore = InMemoryReadModelStore<_CounterReadModel, StreamId>();

      registry.registerAsync(failingProjection, failingStore);
      registry.registerAsync(workingProjection, workingStore);
      executor = AsyncProjectionExecutor(
        registry: registry,
        positionStore: positionStore,
      );

      final event = _createEvent(streamId: 'stream-1', globalSequence: 1);
      final result = await executor.processEventsAsync([event]);

      // Failing projection failed, working projection succeeded.
      expect(result.failed, equals(1));
      expect(result.processed, equals(1));
      expect(result.isSuccess, isFalse);

      // Working projection should have updated.
      expect(workingStore.length, equals(1));
    });

    test('processEventsAsync returns correct counts for multiple events', () async {
      final projection = _CounterProjection();
      registry.registerAsync(projection, readModelStore);
      executor = AsyncProjectionExecutor(
        registry: registry,
        positionStore: positionStore,
      );

      final events = [
        _createEvent(streamId: 's1', globalSequence: 1),
        _createEvent(streamId: 's2', globalSequence: 2),
        _createEvent(streamId: 's3', globalSequence: 3),
      ];

      final result = await executor.processEventsAsync(events);

      expect(result.processed, equals(3));
      expect(result.failed, equals(0));
      expect(result.total, equals(3));
    });

    test('getPositionAsync returns last processed position', () async {
      final projection = _CounterProjection();
      registry.registerAsync(projection, readModelStore);
      executor = AsyncProjectionExecutor(
        registry: registry,
        positionStore: positionStore,
      );

      final event = _createEvent(streamId: 'stream-1', globalSequence: 42);
      await executor.processEventsAsync([event]);

      final position = await executor.getPositionAsync('counter');
      expect(position?.lastProcessedSequence, equals(42));
    });

    test('getPositionAsync returns null for unprocessed projection', () async {
      executor = AsyncProjectionExecutor(
        registry: registry,
        positionStore: positionStore,
      );

      final position = await executor.getPositionAsync('unknown');
      expect(position, isNull);
    });

    test('resetPositionAsync clears projection position', () async {
      await positionStore.savePositionAsync(
        'counter',
        const ProjectionPosition(lastProcessedSequence: 100, schemaHash: 'test'),
      );
      executor = AsyncProjectionExecutor(
        registry: registry,
        positionStore: positionStore,
      );

      await executor.resetPositionAsync('counter');

      final position = await positionStore.loadPositionAsync('counter');
      expect(position, isNull);
    });
  });

  group('ProcessingResult', () {
    test('isSuccess returns true when no failures', () {
      const result = ProcessingResult(processed: 5, failed: 0);
      expect(result.isSuccess, isTrue);
    });

    test('isSuccess returns false when any failures', () {
      const result = ProcessingResult(processed: 3, failed: 2);
      expect(result.isSuccess, isFalse);
    });

    test('total returns sum of processed and failed', () {
      const result = ProcessingResult(processed: 7, failed: 3);
      expect(result.total, equals(10));
    });
  });
}

// --- Test Fixtures ---

int _eventCounter = 0;

StoredEvent _createEvent({
  required String streamId,
  int? globalSequence,
}) {
  return StoredEvent(
    eventId: EventId('evt-${_eventCounter++}'),
    streamId: StreamId(streamId),
    version: 0,
    eventType: 'test.event',
    data: const {},
    occurredOn: DateTime.now(),
    metadata: const {},
    globalSequence: globalSequence,
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
    throw StateError('Intentional failure');
  }
}
