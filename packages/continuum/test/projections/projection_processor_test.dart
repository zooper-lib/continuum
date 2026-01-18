import 'package:continuum/continuum.dart';
import 'package:test/test.dart';
import 'package:zooper_flutter_core/zooper_flutter_core.dart';

void main() {
  group('PollingProjectionProcessor', () {
    late ProjectionRegistry registry;
    late InMemoryProjectionPositionStore positionStore;
    late InMemoryReadModelStore<_CounterReadModel, StreamId> readModelStore;
    late AsyncProjectionExecutor executor;
    late List<StoredEvent> eventStore;
    late PollingProjectionProcessor processor;

    setUp(() {
      registry = ProjectionRegistry();
      positionStore = InMemoryProjectionPositionStore();
      readModelStore = InMemoryReadModelStore<_CounterReadModel, StreamId>();
      eventStore = [];

      final projection = _CounterProjection();
      registry.registerAsync(projection, readModelStore);

      executor = AsyncProjectionExecutor(
        registry: registry,
        positionStore: positionStore,
      );
    });

    /// Creates a processor with the current test fixtures.
    PollingProjectionProcessor createProcessor({
      int batchSize = 100,
      Duration pollingInterval = const Duration(milliseconds: 50),
    }) {
      return PollingProjectionProcessor(
        executor: executor,
        positionStore: positionStore,
        eventLoader: (fromPosition, limit) async {
          // Simulate loading events from position.
          return eventStore.where((e) => (e.globalSequence ?? 0) >= fromPosition).take(limit).toList();
        },
        batchSize: batchSize,
        pollingInterval: pollingInterval,
      );
    }

    test('processBatchAsync processes events from event loader', () async {
      eventStore = [
        _createEvent('s1', globalSequence: 0),
        _createEvent('s1', globalSequence: 1),
        _createEvent('s2', globalSequence: 2),
      ];
      processor = createProcessor();

      final result = await processor.processBatchAsync();

      expect(result.processed, equals(3));
      expect(readModelStore.length, equals(2)); // s1 and s2
    });

    test('processBatchAsync updates processor position', () async {
      eventStore = [
        _createEvent('s1', globalSequence: 10),
        _createEvent('s1', globalSequence: 11),
      ];
      processor = createProcessor();

      await processor.processBatchAsync();

      final position = await positionStore.loadPositionAsync('_processor_position');
      expect(position, equals(11));
    });

    test('processBatchAsync resumes from last position', () async {
      eventStore = [
        _createEvent('s1', globalSequence: 0),
        _createEvent('s1', globalSequence: 1),
        _createEvent('s1', globalSequence: 2),
        _createEvent('s1', globalSequence: 3),
      ];

      // Set position to 1, so we should start from 2.
      await positionStore.savePositionAsync('_processor_position', 1);

      processor = createProcessor();
      final result = await processor.processBatchAsync();

      // Should only process events 2 and 3.
      expect(result.processed, equals(2));
    });

    test('processBatchAsync returns empty result when no events', () async {
      eventStore = [];
      processor = createProcessor();

      final result = await processor.processBatchAsync();

      expect(result.processed, equals(0));
      expect(result.failed, equals(0));
    });

    test('processBatchAsync respects batch size', () async {
      eventStore = List.generate(
        10,
        (i) => _createEvent('s$i', globalSequence: i),
      );
      processor = createProcessor(batchSize: 3);

      final result = await processor.processBatchAsync();

      // Should only process first 3 events.
      expect(result.processed, equals(3));

      final position = await positionStore.loadPositionAsync('_processor_position');
      expect(position, equals(2)); // Last processed was index 2.
    });

    test('startAsync and stopAsync control processor lifecycle', () async {
      eventStore = [];
      processor = createProcessor(pollingInterval: const Duration(milliseconds: 10));

      expect(processor.isRunning, isFalse);

      await processor.startAsync();
      expect(processor.isRunning, isTrue);

      await processor.stopAsync();
      expect(processor.isRunning, isFalse);
    });

    test('startAsync processes events immediately', () async {
      eventStore = [
        _createEvent('s1', globalSequence: 0),
      ];
      processor = createProcessor();

      await processor.startAsync();
      await processor.stopAsync();

      expect(readModelStore.length, equals(1));
    });

    test('startAsync is idempotent', () async {
      eventStore = [];
      processor = createProcessor();

      await processor.startAsync();
      await processor.startAsync(); // Should not throw or duplicate.

      expect(processor.isRunning, isTrue);

      await processor.stopAsync();
    });

    test('stopAsync waits for in-progress processing', () async {
      // Create a slow event loader.
      processor = PollingProjectionProcessor(
        executor: executor,
        positionStore: positionStore,
        eventLoader: (fromPosition, limit) async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return <StoredEvent>[];
        },
        batchSize: 100,
        pollingInterval: const Duration(milliseconds: 100),
      );

      await processor.startAsync();

      // Start stop while processing is happening.
      final stopFuture = processor.stopAsync();

      await stopFuture;

      expect(processor.isRunning, isFalse);
    });
  });
}

// --- Test Fixtures ---

int _eventCounter = 0;

StoredEvent _createEvent(String streamId, {required int globalSequence}) {
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
  @override
  Set<Type> get handledEventTypes => {_TestEvent};

  @override
  String get projectionName => 'counter';

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
