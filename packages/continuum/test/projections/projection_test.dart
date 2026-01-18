import 'package:continuum/continuum.dart';
import 'package:test/test.dart';
import 'package:zooper_flutter_core/zooper_flutter_core.dart';

void main() {
  group('Projection', () {
    test('handles() returns true for registered event types', () {
      final projection = _TestSingleStreamProjection();

      expect(projection.handles(_TestEventA), isTrue);
      expect(projection.handles(_TestEventB), isTrue);
    });

    test('handles() returns false for unregistered event types', () {
      final projection = _TestSingleStreamProjection();

      expect(projection.handles(_TestEventC), isFalse);
      expect(projection.handles(String), isFalse);
    });
  });

  group('SingleStreamProjection', () {
    test('extractKey returns the event stream ID', () {
      final projection = _TestSingleStreamProjection();
      final event = _createStoredEvent(
        streamId: const StreamId('stream-123'),
        eventType: 'test.event_a',
      );

      final key = projection.extractKey(event);

      expect(key, equals(const StreamId('stream-123')));
    });

    test('createInitial creates read model for stream ID', () {
      final projection = _TestSingleStreamProjection();

      final readModel = projection.createInitial(const StreamId('stream-456'));

      expect(readModel.streamId, equals('stream-456'));
      expect(readModel.eventCount, equals(0));
    });

    test('apply updates read model with event', () {
      final projection = _TestSingleStreamProjection();
      final initial = _TestReadModel(streamId: 'stream-1', eventCount: 0);
      final event = _createStoredEvent(
        streamId: const StreamId('stream-1'),
        eventType: 'test.event_a',
      );

      final updated = projection.apply(initial, event);

      expect(updated.eventCount, equals(1));
    });

    test('handledEventTypes returns declared types', () {
      final projection = _TestSingleStreamProjection();

      expect(projection.handledEventTypes, contains(_TestEventA));
      expect(projection.handledEventTypes, contains(_TestEventB));
      expect(projection.handledEventTypes.length, equals(2));
    });

    test('projectionName returns unique identifier', () {
      final projection = _TestSingleStreamProjection();

      expect(projection.projectionName, equals('test-single-stream'));
    });
  });

  group('MultiStreamProjection', () {
    test('extractKey returns key from event data', () {
      final projection = _TestMultiStreamProjection();
      final event = _createStoredEvent(
        streamId: const StreamId('stream-1'),
        eventType: 'test.event_a',
        data: {'categoryId': 'category-abc'},
      );

      final key = projection.extractKey(event);

      expect(key, equals('category-abc'));
    });

    test('createInitial creates read model for key', () {
      final projection = _TestMultiStreamProjection();

      final readModel = projection.createInitial('category-xyz');

      expect(readModel.categoryId, equals('category-xyz'));
      expect(readModel.totalEvents, equals(0));
    });

    test('apply updates read model with event from any stream', () {
      final projection = _TestMultiStreamProjection();
      final initial = _CategoryStats(categoryId: 'cat-1', totalEvents: 5);
      final event = _createStoredEvent(
        streamId: const StreamId('different-stream'),
        eventType: 'test.event_a',
        data: {'categoryId': 'cat-1'},
      );

      final updated = projection.apply(initial, event);

      expect(updated.totalEvents, equals(6));
    });

    test('handledEventTypes returns declared types', () {
      final projection = _TestMultiStreamProjection();

      expect(projection.handledEventTypes, contains(_TestEventA));
      expect(projection.handledEventTypes.length, equals(1));
    });

    test('projectionName returns unique identifier', () {
      final projection = _TestMultiStreamProjection();

      expect(projection.projectionName, equals('test-multi-stream'));
    });
  });
}

// --- Test Fixtures ---

/// Marker class for test event type A.
class _TestEventA {}

/// Marker class for test event type B.
class _TestEventB {}

/// Marker class for test event type C (not handled).
class _TestEventC {}

/// Simple read model for single-stream projection tests.
class _TestReadModel {
  final String streamId;
  final int eventCount;

  _TestReadModel({required this.streamId, required this.eventCount});
}

/// Simple read model for multi-stream projection tests.
class _CategoryStats {
  final String categoryId;
  final int totalEvents;

  _CategoryStats({required this.categoryId, required this.totalEvents});
}

/// Test implementation of SingleStreamProjection.
class _TestSingleStreamProjection extends SingleStreamProjection<_TestReadModel> {
  @override
  Set<Type> get handledEventTypes => {_TestEventA, _TestEventB};

  @override
  String get projectionName => 'test-single-stream';

  @override
  _TestReadModel createInitial(StreamId streamId) {
    return _TestReadModel(streamId: streamId.value, eventCount: 0);
  }

  @override
  _TestReadModel apply(_TestReadModel current, StoredEvent event) {
    return _TestReadModel(
      streamId: current.streamId,
      eventCount: current.eventCount + 1,
    );
  }
}

/// Test implementation of MultiStreamProjection.
class _TestMultiStreamProjection extends MultiStreamProjection<_CategoryStats, String> {
  @override
  Set<Type> get handledEventTypes => {_TestEventA};

  @override
  String get projectionName => 'test-multi-stream';

  @override
  String extractKey(StoredEvent event) {
    return event.data['categoryId'] as String;
  }

  @override
  _CategoryStats createInitial(String key) {
    return _CategoryStats(categoryId: key, totalEvents: 0);
  }

  @override
  _CategoryStats apply(_CategoryStats current, StoredEvent event) {
    return _CategoryStats(
      categoryId: current.categoryId,
      totalEvents: current.totalEvents + 1,
    );
  }
}

/// Counter for generating unique event IDs in tests.
int _eventIdCounter = 0;

/// Helper to create a stored event for testing.
StoredEvent _createStoredEvent({
  required StreamId streamId,
  required String eventType,
  Map<String, dynamic> data = const {},
}) {
  return StoredEvent(
    eventId: EventId('test-event-${_eventIdCounter++}'),
    streamId: streamId,
    version: 0,
    eventType: eventType,
    data: data,
    occurredOn: DateTime.now(),
    metadata: const {},
  );
}
