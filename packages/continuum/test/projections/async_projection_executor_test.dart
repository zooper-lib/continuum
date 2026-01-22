import 'package:continuum/continuum.dart';
import 'package:test/test.dart';

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
      // Arrange: No projections are registered.
      executor = AsyncProjectionExecutor(
        registry: registry,
        positionStore: positionStore,
      );

      final event = _createEvent(streamId: 'stream-1', globalSequence: 1);

      // Act.
      final result = await executor.processEventsAsync([event]);

      // Assert: No projections means no work.
      // This matters because projections are optional infrastructure.
      expect(result.processed, equals(0));
      expect(result.failed, equals(0));
      expect(result.isSuccess, isTrue);
    });

    test('processEventsAsync does nothing with empty event list', () async {
      // Arrange.
      final projection = _CounterProjection();
      registry.registerAsync(projection, readModelStore);
      executor = AsyncProjectionExecutor(
        registry: registry,
        positionStore: positionStore,
      );

      // Act.
      final result = await executor.processEventsAsync([]);

      // Assert: Empty input should be a no-op.
      expect(result.processed, equals(0));
      expect(result.total, equals(0));
    });

    test('processEventsAsync creates initial read model', () async {
      // Arrange.
      final projection = _CounterProjection();
      registry.registerAsync(projection, readModelStore);
      executor = AsyncProjectionExecutor(
        registry: registry,
        positionStore: positionStore,
      );

      final event = _createEvent(streamId: 'stream-1', globalSequence: 1);

      // Act.
      await executor.processEventsAsync([event]);

      // Assert: Missing read model should be created via createInitial.
      final readModel = await readModelStore.loadAsync(const StreamId('stream-1'));
      expect(readModel, isNotNull);
      expect(readModel!.count, equals(1));
    });

    test('processEventsAsync updates existing read model', () async {
      // Arrange.
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

      // Act.
      await executor.processEventsAsync([event]);

      // Assert: Existing models should be updated, not replaced incorrectly.
      final readModel = await readModelStore.loadAsync(const StreamId('stream-1'));
      expect(readModel!.count, equals(11));
    });

    test('processEventsAsync tracks position after success', () async {
      // Arrange.
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

      // Assert: Position should reflect the last successfully processed event.
      final position = await positionStore.loadPositionAsync('counter');
      expect(position?.lastProcessedSequence, equals(12));
    });

    test('processEventsAsync skips inline projections', () async {
      // Arrange.
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

      // Act.
      await executor.processEventsAsync([event]);

      // Assert: Inline projections are not executed by the async executor.
      expect(inlineStore.length, equals(0));
      expect(readModelStore.length, equals(1));
    });

    test('processEventsAsync continues after projection failure', () async {
      // Arrange.
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

      // Act.
      final result = await executor.processEventsAsync([event]);

      // Failing projection failed, working projection succeeded.
      expect(result.failed, equals(1));
      expect(result.processed, equals(1));
      expect(result.isSuccess, isFalse);

      // Working projection should have updated.
      expect(workingStore.length, equals(1));
    });

    test('processEventsAsync routes events only to matching projections', () async {
      // Arrange: Two projections with disjoint handled event types.
      final storeA = InMemoryReadModelStore<int, StreamId>();
      final storeB = InMemoryReadModelStore<int, StreamId>();
      registry.registerAsync(_CounterProjectionForA(), storeA);
      registry.registerAsync(_CounterProjectionForB(), storeB);
      executor = AsyncProjectionExecutor(
        registry: registry,
        positionStore: positionStore,
      );

      final eventA = _createStoredEvent(
        streamId: const StreamId('s1'),
        globalSequence: 0,
        continuumEvent: _TestEventA(eventId: EventId.fromUlid()),
      );

      // Act.
      final result = await executor.processEventsAsync([eventA]);

      // Assert: Only the matching projection should be updated.
      // This matters because unrelated projections must not mutate read models.
      expect(result.processed, equals(1));
      expect(result.failed, equals(0));
      expect(await storeA.loadAsync(const StreamId('s1')), equals(1));
      expect(await storeB.loadAsync(const StreamId('s1')), isNull);
    });

    test('processEventsAsync saves schemaHash in position on success', () async {
      // Arrange.
      final store = InMemoryReadModelStore<int, StreamId>();
      final projection = _CounterProjectionForA();
      const schemaHash = 'schema-1';
      registry.registerAsync(projection, store);
      executor = AsyncProjectionExecutor(
        registry: registry,
        positionStore: positionStore,
      );

      final eventA = _createStoredEvent(
        streamId: const StreamId('s1'),
        globalSequence: 5,
        continuumEvent: _TestEventA(eventId: EventId.fromUlid()),
      );

      // Act.
      final result = await executor.processEventsAsync(
        [eventA],
        schemaHash: schemaHash,
      );

      // Assert: The position must include schema hash for rebuild detection.
      expect(result.isSuccess, isTrue);
      final position = await positionStore.loadPositionAsync(
        projection.projectionName,
      );
      expect(position?.schemaHash, equals(schemaHash));
    });

    test('processEventsAsync does not advance position for failing projection', () async {
      // Arrange: One successful and one failing projection.
      final storeOk = InMemoryReadModelStore<int, StreamId>();
      final storeFail = InMemoryReadModelStore<int, StreamId>();
      final okProjection = _CounterProjectionForA();
      final failingProjection = _FailingProjectionForA();
      registry.registerAsync(okProjection, storeOk);
      registry.registerAsync(failingProjection, storeFail);
      executor = AsyncProjectionExecutor(
        registry: registry,
        positionStore: positionStore,
      );

      final eventA = _createStoredEvent(
        streamId: const StreamId('s1'),
        globalSequence: 7,
        continuumEvent: _TestEventA(eventId: EventId.fromUlid()),
      );

      // Act.
      final result = await executor.processEventsAsync([eventA]);

      // Assert: Failures should be isolated per projection.
      // This matters because successful projections should still advance.
      expect(result.processed, equals(1));
      expect(result.failed, equals(1));

      final okPosition = await positionStore.loadPositionAsync(
        okProjection.projectionName,
      );
      final failPosition = await positionStore.loadPositionAsync(
        failingProjection.projectionName,
      );
      expect(okPosition?.lastProcessedSequence, equals(7));
      expect(failPosition, isNull);
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
  final continuumEvent = _TestEvent(eventId: EventId('evt-${_eventCounter++}'));

  return StoredEvent.fromContinuumEvent(
    continuumEvent: continuumEvent,
    streamId: StreamId(streamId),
    version: 0,
    eventType: 'test.event',
    data: const <String, dynamic>{},
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

StoredEvent _createStoredEvent({
  required StreamId streamId,
  required int globalSequence,
  required ContinuumEvent continuumEvent,
}) {
  return StoredEvent.fromContinuumEvent(
    continuumEvent: continuumEvent,
    streamId: streamId,
    version: 0,
    eventType: 'test.event',
    data: const <String, dynamic>{},
    globalSequence: globalSequence,
  );
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

final class _FailingProjectionForA extends SingleStreamProjection<int> {
  @override
  Set<Type> get handledEventTypes => const {_TestEventA};

  @override
  String get projectionName => 'failing-a';

  @override
  int createInitial(StreamId streamId) => 0;

  @override
  int apply(int current, StoredEvent event) {
    throw StateError('Intentional failure for testing');
  }
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
    throw StateError('Intentional failure');
  }
}
