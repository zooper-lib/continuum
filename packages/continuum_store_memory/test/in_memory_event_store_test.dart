import 'package:continuum/continuum.dart';
import 'package:continuum_store_memory/continuum_store_memory.dart';
import 'package:test/test.dart';
import 'package:zooper_flutter_core/zooper_flutter_core.dart';

void main() {
  group('InMemoryEventStore', () {
    late InMemoryEventStore store;

    setUp(() {
      store = InMemoryEventStore();
    });

    group('loadStreamAsync', () {
      test('should return empty list for non-existent stream', () async {
        // Arrange
        final streamId = const StreamId('non_existent');

        // Act
        final events = await store.loadStreamAsync(streamId);

        // Assert - missing streams return empty list per spec
        expect(events, isEmpty);
      });

      test('should return events in order after append', () async {
        // Arrange
        final streamId = const StreamId('test_stream');
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
        final streamId = const StreamId('new_stream');
        final events = [_createStoredEvent(streamId, 0, 'created')];

        // Act
        await store.appendEventsAsync(streamId, ExpectedVersion.noStream, events);

        // Assert - event should be stored
        final loaded = await store.loadStreamAsync(streamId);
        expect(loaded.length, equals(1));
      });

      test('should assign sequential versions starting at 0', () async {
        // Arrange
        final streamId = const StreamId('versioned_stream');

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
        final streamId = const StreamId('concurrent_stream');
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
        final streamId = const StreamId('existing_stream');
        await store.appendEventsAsync(streamId, ExpectedVersion.noStream, [_createStoredEvent(streamId, 0, 'first')]);

        // Act & Assert - noStream on existing stream should throw
        expect(
          () => store.appendEventsAsync(streamId, ExpectedVersion.noStream, [_createStoredEvent(streamId, 1, 'duplicate')]),
          throwsA(isA<ConcurrencyException>()),
        );
      });

      test('should handle multiple events in single append', () async {
        // Arrange
        final streamId = const StreamId('batch_stream');
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
        final stream1 = const StreamId('stream_1');
        final stream2 = const StreamId('stream_2');

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

    group('appendEventsToStreamsAsync', () {
      test('should append events to multiple streams atomically', () async {
        // Arrange
        final StreamId stream1 = const StreamId('atomic_stream_1');
        final StreamId stream2 = const StreamId('atomic_stream_2');

        final Map<StreamId, StreamAppendBatch> batches = <StreamId, StreamAppendBatch>{
          stream1: StreamAppendBatch(
            expectedVersion: ExpectedVersion.noStream,
            events: <StoredEvent>[_createStoredEvent(stream1, 0, 'first')],
          ),
          stream2: StreamAppendBatch(
            expectedVersion: ExpectedVersion.noStream,
            events: <StoredEvent>[_createStoredEvent(stream2, 0, 'second')],
          ),
        };

        // Act
        await store.appendEventsToStreamsAsync(batches);

        // Assert - both streams should be updated as a single logical unit
        final List<StoredEvent> stream1Events = await store.loadStreamAsync(stream1);
        final List<StoredEvent> stream2Events = await store.loadStreamAsync(stream2);

        expect(stream1Events.single.version, equals(0));
        expect(stream2Events.single.version, equals(0));

        // Assert - global sequence should still be unique and sequential
        final List<int?> globalSequences = <int?>[
          stream1Events.single.globalSequence,
          stream2Events.single.globalSequence,
        ]..sort((int? a, int? b) => (a ?? -1).compareTo(b ?? -1));
        expect(globalSequences, equals(<int>[0, 1]));
      });

      test('should not persist any events when one stream has a version mismatch', () async {
        // Arrange
        final StreamId stream1 = const StreamId('atomic_mismatch_1');
        final StreamId stream2 = const StreamId('atomic_mismatch_2');

        await store.appendEventsAsync(
          stream1,
          ExpectedVersion.noStream,
          <StoredEvent>[_createStoredEvent(stream1, 0, 'first')],
        );

        final Map<StreamId, StreamAppendBatch> batches = <StreamId, StreamAppendBatch>{
          stream1: StreamAppendBatch(
            expectedVersion: ExpectedVersion.exact(999),
            events: <StoredEvent>[_createStoredEvent(stream1, 1, 'should_fail')],
          ),
          stream2: StreamAppendBatch(
            expectedVersion: ExpectedVersion.noStream,
            events: <StoredEvent>[_createStoredEvent(stream2, 0, 'should_not_be_written')],
          ),
        };

        // Act & Assert - the mismatch should prevent all writes
        expect(
          () => store.appendEventsToStreamsAsync(batches),
          throwsA(isA<ConcurrencyException>()),
        );

        // Assert - stream1 is unchanged and stream2 remains empty
        final List<StoredEvent> stream1EventsAfter = await store.loadStreamAsync(stream1);
        final List<StoredEvent> stream2EventsAfter = await store.loadStreamAsync(stream2);

        expect(stream1EventsAfter.length, equals(1));
        expect(stream1EventsAfter.single.eventType, equals('first'));
        expect(stream2EventsAfter, isEmpty);
      });
    });

    group('clear', () {
      test('should remove all events', () async {
        // Arrange
        final streamId = const StreamId('to_clear');
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
        await store.appendEventsAsync(const StreamId('stream_1'), ExpectedVersion.noStream, [_createStoredEvent(const StreamId('stream_1'), 0, 'event')]);
        await store.appendEventsAsync(const StreamId('stream_2'), ExpectedVersion.noStream, [_createStoredEvent(const StreamId('stream_2'), 0, 'event')]);

        // Assert
        expect(store.streamCount, equals(2));
      });

      test('should track total event count', () async {
        // Arrange
        final streamId = const StreamId('counted');
        await store.appendEventsAsync(streamId, ExpectedVersion.noStream, [
          _createStoredEvent(streamId, 0, 'event_1'),
          _createStoredEvent(streamId, 1, 'event_2'),
        ]);

        // Assert
        expect(store.eventCount, equals(2));
      });
    });

    group('loadEventsFromPositionAsync', () {
      test('should return empty list when no events exist', () async {
        final events = await store.loadEventsFromPositionAsync(0, 100);
        expect(events, isEmpty);
      });

      test('should return events from position', () async {
        final s1 = const StreamId('stream-1');
        final s2 = const StreamId('stream-2');

        await store.appendEventsAsync(s1, ExpectedVersion.noStream, [
          _createStoredEvent(s1, 0, 'e1'),
        ]);
        await store.appendEventsAsync(s2, ExpectedVersion.noStream, [
          _createStoredEvent(s2, 0, 'e2'),
        ]);

        // Load from position 1 (skip first event).
        final events = await store.loadEventsFromPositionAsync(1, 100);

        expect(events.length, equals(1));
        expect(events.first.globalSequence, equals(1));
      });

      test('should respect limit parameter', () async {
        final s1 = const StreamId('stream-1');
        await store.appendEventsAsync(s1, ExpectedVersion.noStream, [
          _createStoredEvent(s1, 0, 'e1'),
          _createStoredEvent(s1, 1, 'e2'),
          _createStoredEvent(s1, 2, 'e3'),
        ]);

        final events = await store.loadEventsFromPositionAsync(0, 2);

        expect(events.length, equals(2));
        expect(events[0].globalSequence, equals(0));
        expect(events[1].globalSequence, equals(1));
      });

      test('should order events by global sequence', () async {
        final s1 = const StreamId('stream-1');
        final s2 = const StreamId('stream-2');

        await store.appendEventsAsync(s1, ExpectedVersion.noStream, [
          _createStoredEvent(s1, 0, 'e1'),
        ]);
        await store.appendEventsAsync(s2, ExpectedVersion.noStream, [
          _createStoredEvent(s2, 0, 'e2'),
        ]);
        await store.appendEventsAsync(s1, ExpectedVersion.exact(0), [
          _createStoredEvent(s1, 1, 'e3'),
        ]);

        final events = await store.loadEventsFromPositionAsync(0, 100);

        expect(events.length, equals(3));
        expect(events[0].globalSequence, equals(0));
        expect(events[1].globalSequence, equals(1));
        expect(events[2].globalSequence, equals(2));
      });
    });

    group('getMaxGlobalSequenceAsync', () {
      test('should return null when no events', () async {
        final maxSeq = await store.getMaxGlobalSequenceAsync();
        expect(maxSeq, isNull);
      });

      test('should return max global sequence', () async {
        final s1 = const StreamId('stream-1');
        await store.appendEventsAsync(s1, ExpectedVersion.noStream, [
          _createStoredEvent(s1, 0, 'e1'),
          _createStoredEvent(s1, 1, 'e2'),
          _createStoredEvent(s1, 2, 'e3'),
        ]);

        final maxSeq = await store.getMaxGlobalSequenceAsync();

        expect(maxSeq, equals(2));
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
