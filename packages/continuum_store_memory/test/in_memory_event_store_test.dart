import 'package:continuum/continuum.dart';
import 'package:continuum_store_memory/continuum_store_memory.dart';
import 'package:test/test.dart';

void main() {
  group('InMemoryEventStore', () {
    late InMemoryEventStore store;

    setUp(() {
      store = InMemoryEventStore();
    });

    group('loadStreamAsync', () {
      test('should return empty list for non-existent stream', () async {
        // Arrange
        final streamId = StreamId('non_existent');

        // Act
        final events = await store.loadStreamAsync(streamId);

        // Assert - missing streams return empty list per spec
        expect(events, isEmpty);
      });

      test('should return events in order after append', () async {
        // Arrange
        final streamId = StreamId('test_stream');
        final storedEvents = [_createStoredEvent(streamId, 0, 'event_1'), _createStoredEvent(streamId, 1, 'event_2')];

        await store.appendEventsAsync(streamId, ExpectedVersion.noStream, storedEvents);

        // Act
        final loadedEvents = await store.loadStreamAsync(streamId);

        // Assert - events should be returned in order
        expect(loadedEvents.length, equals(2));
        expect(loadedEvents[0].eventType, equals('event_1'));
        expect(loadedEvents[1].eventType, equals('event_2'));
      });
    });

    group('appendEventsAsync', () {
      test('should append to new stream with noStream expected version', () async {
        // Arrange
        final streamId = StreamId('new_stream');
        final events = [_createStoredEvent(streamId, 0, 'created')];

        // Act
        await store.appendEventsAsync(streamId, ExpectedVersion.noStream, events);

        // Assert - event should be stored
        final loaded = await store.loadStreamAsync(streamId);
        expect(loaded.length, equals(1));
      });

      test('should assign sequential versions starting at 0', () async {
        // Arrange
        final streamId = StreamId('versioned_stream');

        // Act - append first event
        await store.appendEventsAsync(streamId, ExpectedVersion.noStream, [_createStoredEvent(streamId, 0, 'first')]);

        // Act - append second event
        await store.appendEventsAsync(streamId, ExpectedVersion.exact(0), [_createStoredEvent(streamId, 1, 'second')]);

        // Assert - versions should be 0 and 1
        final loaded = await store.loadStreamAsync(streamId);
        expect(loaded[0].version, equals(0));
        expect(loaded[1].version, equals(1));
      });

      test('should throw ConcurrencyException when expected version mismatches', () async {
        // Arrange
        final streamId = StreamId('concurrent_stream');
        await store.appendEventsAsync(streamId, ExpectedVersion.noStream, [_createStoredEvent(streamId, 0, 'first')]);

        // Act & Assert - wrong expected version should throw
        expect(
          () => store.appendEventsAsync(
            streamId,
            ExpectedVersion.exact(5), // Wrong - should be 0
            [_createStoredEvent(streamId, 1, 'second')],
          ),
          throwsA(isA<ConcurrencyException>()),
        );
      });

      test('should throw ConcurrencyException when expecting noStream but stream exists', () async {
        // Arrange
        final streamId = StreamId('existing_stream');
        await store.appendEventsAsync(streamId, ExpectedVersion.noStream, [_createStoredEvent(streamId, 0, 'first')]);

        // Act & Assert - noStream on existing stream should throw
        expect(
          () => store.appendEventsAsync(streamId, ExpectedVersion.noStream, [_createStoredEvent(streamId, 1, 'duplicate')]),
          throwsA(isA<ConcurrencyException>()),
        );
      });

      test('should handle multiple events in single append', () async {
        // Arrange
        final streamId = StreamId('batch_stream');
        final events = [_createStoredEvent(streamId, 0, 'event_1'), _createStoredEvent(streamId, 1, 'event_2'), _createStoredEvent(streamId, 2, 'event_3')];

        // Act
        await store.appendEventsAsync(streamId, ExpectedVersion.noStream, events);

        // Assert - all events stored with sequential versions
        final loaded = await store.loadStreamAsync(streamId);
        expect(loaded.length, equals(3));
        expect(loaded.map((e) => e.version), equals([0, 1, 2]));
      });

      test('should assign global sequence numbers', () async {
        // Arrange
        final stream1 = StreamId('stream_1');
        final stream2 = StreamId('stream_2');

        // Act - append to two different streams
        await store.appendEventsAsync(stream1, ExpectedVersion.noStream, [_createStoredEvent(stream1, 0, 'first')]);
        await store.appendEventsAsync(stream2, ExpectedVersion.noStream, [_createStoredEvent(stream2, 0, 'second')]);

        // Assert - global sequences should be ordered across streams
        final events1 = await store.loadStreamAsync(stream1);
        final events2 = await store.loadStreamAsync(stream2);
        expect(events1[0].globalSequence, equals(0));
        expect(events2[0].globalSequence, equals(1));
      });
    });

    group('clear', () {
      test('should remove all events', () async {
        // Arrange
        final streamId = StreamId('to_clear');
        await store.appendEventsAsync(streamId, ExpectedVersion.noStream, [_createStoredEvent(streamId, 0, 'event')]);

        // Act
        store.clear();

        // Assert
        expect(store.streamCount, equals(0));
        expect(store.eventCount, equals(0));
      });
    });

    group('statistics', () {
      test('should track stream count', () async {
        // Arrange
        await store.appendEventsAsync(StreamId('stream_1'), ExpectedVersion.noStream, [_createStoredEvent(StreamId('stream_1'), 0, 'event')]);
        await store.appendEventsAsync(StreamId('stream_2'), ExpectedVersion.noStream, [_createStoredEvent(StreamId('stream_2'), 0, 'event')]);

        // Assert
        expect(store.streamCount, equals(2));
      });

      test('should track total event count', () async {
        // Arrange
        final streamId = StreamId('counted');
        await store.appendEventsAsync(streamId, ExpectedVersion.noStream, [
          _createStoredEvent(streamId, 0, 'event_1'),
          _createStoredEvent(streamId, 1, 'event_2'),
        ]);

        // Assert
        expect(store.eventCount, equals(2));
      });
    });
  });
}

/// Helper to create a stored event for testing.
StoredEvent _createStoredEvent(StreamId streamId, int version, String eventType) {
  return StoredEvent(
    eventId: EventId('evt_$version'),
    streamId: streamId,
    version: version,
    eventType: eventType,
    data: {'version': version},
    occurredOn: DateTime.now().toUtc(),
    metadata: {},
  );
}
