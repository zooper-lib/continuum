import 'dart:io';

import 'package:continuum/continuum.dart';
import 'package:continuum_store_sembast/continuum_store_sembast.dart';
import 'package:sembast/sembast_io.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late SembastEventStore store;

  setUp(() async {
    // Create a temporary directory for each test to isolate database files.
    tempDir = await Directory.systemTemp.createTemp('sembast_test_');
    final dbPath = '${tempDir.path}/test.db';
    store = await SembastEventStore.openAsync(
      databaseFactory: databaseFactoryIo,
      dbPath: dbPath,
    );
  });

  tearDown(() async {
    await store.closeAsync();
    // Clean up the temporary directory.
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('SembastEventStore', () {
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
        final storedEvents = [
          _createStoredEvent(streamId, 0, 'event_1'),
          _createStoredEvent(streamId, 1, 'event_2'),
        ];

        await store.appendEventsAsync(streamId, ExpectedVersion.noStream, storedEvents, aggregateType: 'TestAggregate');

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
        await store.appendEventsAsync(streamId, ExpectedVersion.noStream, events, aggregateType: 'TestAggregate');

        // Assert - event should be stored
        final loaded = await store.loadStreamAsync(streamId);
        expect(loaded.length, equals(1));
      });

      test('should assign sequential versions starting at 0', () async {
        // Arrange
        final streamId = const StreamId('versioned_stream');

        // Act - append first event
        await store.appendEventsAsync(
          streamId,
          ExpectedVersion.noStream,
          [_createStoredEvent(streamId, 0, 'first')],
          aggregateType: 'TestAggregate',
        );

        // Act - append second event
        await store.appendEventsAsync(
          streamId,
          ExpectedVersion.exact(0),
          [_createStoredEvent(streamId, 1, 'second')],
          aggregateType: 'TestAggregate',
        );

        // Assert - versions should be 0 and 1
        final loaded = await store.loadStreamAsync(streamId);
        expect(loaded[0].version, equals(0));
        expect(loaded[1].version, equals(1));
      });

      test('should throw ConcurrencyException when expected version mismatches', () async {
        // Arrange
        final streamId = const StreamId('concurrent_stream');
        await store.appendEventsAsync(
          streamId,
          ExpectedVersion.noStream,
          [_createStoredEvent(streamId, 0, 'first')],
          aggregateType: 'TestAggregate',
        );

        // Act & Assert - wrong expected version should throw
        expect(
          () => store.appendEventsAsync(
            streamId,
            ExpectedVersion.exact(5), // Wrong - should be 0
            [_createStoredEvent(streamId, 1, 'second')],
            aggregateType: 'TestAggregate',
          ),
          throwsA(isA<ConcurrencyException>()),
        );
      });

      test('should throw ConcurrencyException when expecting noStream but stream exists', () async {
        // Arrange
        final streamId = const StreamId('existing_stream');
        await store.appendEventsAsync(
          streamId,
          ExpectedVersion.noStream,
          [_createStoredEvent(streamId, 0, 'first')],
          aggregateType: 'TestAggregate',
        );

        // Act & Assert - noStream on existing stream should throw
        expect(
          () => store.appendEventsAsync(
            streamId,
            ExpectedVersion.noStream,
            [_createStoredEvent(streamId, 1, 'duplicate')],
            aggregateType: 'TestAggregate',
          ),
          throwsA(isA<ConcurrencyException>()),
        );
      });

      test('should handle multiple events in single append', () async {
        // Arrange
        final streamId = const StreamId('batch_stream');
        final events = [
          _createStoredEvent(streamId, 0, 'event_1'),
          _createStoredEvent(streamId, 1, 'event_2'),
          _createStoredEvent(streamId, 2, 'event_3'),
        ];

        // Act
        await store.appendEventsAsync(streamId, ExpectedVersion.noStream, events, aggregateType: 'TestAggregate');

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
        await store.appendEventsAsync(
          stream1,
          ExpectedVersion.noStream,
          [_createStoredEvent(stream1, 0, 'first')],
          aggregateType: 'TestAggregate',
        );
        await store.appendEventsAsync(
          stream2,
          ExpectedVersion.noStream,
          [_createStoredEvent(stream2, 0, 'second')],
          aggregateType: 'TestAggregate',
        );

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
        final stream1 = const StreamId('atomic_stream_1');
        final stream2 = const StreamId('atomic_stream_2');

        final batches = <StreamId, StreamAppendBatch>{
          stream1: StreamAppendBatch(
            aggregateType: 'TestAggregate',
            expectedVersion: ExpectedVersion.noStream,
            events: <StoredEvent>[_createStoredEvent(stream1, 0, 'first')],
          ),
          stream2: StreamAppendBatch(
            aggregateType: 'TestAggregate',
            expectedVersion: ExpectedVersion.noStream,
            events: <StoredEvent>[_createStoredEvent(stream2, 0, 'second')],
          ),
        };

        // Act
        await store.appendEventsToStreamsAsync(batches);

        // Assert - both streams should be updated as a single logical unit
        final stream1Events = await store.loadStreamAsync(stream1);
        final stream2Events = await store.loadStreamAsync(stream2);

        expect(stream1Events.single.version, equals(0));
        expect(stream2Events.single.version, equals(0));

        // Assert - global sequence should still be unique and sequential
        final globalSequences = <int?>[
          stream1Events.single.globalSequence,
          stream2Events.single.globalSequence,
        ]..sort((int? a, int? b) => (a ?? -1).compareTo(b ?? -1));
        expect(globalSequences, equals(<int>[0, 1]));
      });

      test('should not persist any events when one stream has a version mismatch', () async {
        // Arrange
        final stream1 = const StreamId('atomic_mismatch_1');
        final stream2 = const StreamId('atomic_mismatch_2');

        await store.appendEventsAsync(
          stream1,
          ExpectedVersion.noStream,
          <StoredEvent>[_createStoredEvent(stream1, 0, 'first')],
          aggregateType: 'TestAggregate',
        );

        final batches = <StreamId, StreamAppendBatch>{
          stream1: StreamAppendBatch(
            aggregateType: 'TestAggregate',
            expectedVersion: ExpectedVersion.exact(999),
            events: <StoredEvent>[_createStoredEvent(stream1, 1, 'should_fail')],
          ),
          stream2: StreamAppendBatch(
            aggregateType: 'TestAggregate',
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
        final stream1EventsAfter = await store.loadStreamAsync(stream1);
        final stream2EventsAfter = await store.loadStreamAsync(stream2);

        expect(stream1EventsAfter.length, equals(1));
        expect(stream1EventsAfter.single.eventType, equals('first'));
        expect(stream2EventsAfter, isEmpty);
      });
    });

    group('persistence', () {
      test('should persist events across store reopening', () async {
        // Arrange
        final streamId = const StreamId('persisted_stream');
        await store.appendEventsAsync(
          streamId,
          ExpectedVersion.noStream,
          [_createStoredEvent(streamId, 0, 'persisted_event')],
          aggregateType: 'TestAggregate',
        );

        // Act - close and reopen
        final dbPath = '${tempDir.path}/test.db';
        await store.closeAsync();
        store = await SembastEventStore.openAsync(
          databaseFactory: databaseFactoryIo,
          dbPath: dbPath,
        );
        final loaded = await store.loadStreamAsync(streamId);

        // Assert - event should still be there
        expect(loaded.length, equals(1));
        expect(loaded[0].eventType, equals('persisted_event'));
      });

      test('should preserve event data after reopening', () async {
        // Arrange
        final streamId = const StreamId('data_stream');
        final originalData = {'key': 'value', 'number': 42};
        final event = StoredEvent(
          eventId: const EventId('evt_1'),
          streamId: streamId,
          version: 0,
          eventType: 'data_event',
          data: originalData,
          occurredOn: DateTime.utc(2025, 1, 1),
          metadata: {'meta': 'data'},
        );

        await store.appendEventsAsync(streamId, ExpectedVersion.noStream, [event], aggregateType: 'TestAggregate');

        // Act - close and reopen
        final dbPath = '${tempDir.path}/test.db';
        await store.closeAsync();
        store = await SembastEventStore.openAsync(
          databaseFactory: databaseFactoryIo,
          dbPath: dbPath,
        );
        final loaded = await store.loadStreamAsync(streamId);

        // Assert - data should be preserved
        expect(loaded[0].data, equals(originalData));
        expect(loaded[0].metadata, equals({'meta': 'data'}));
        expect(loaded[0].occurredOn, equals(DateTime.utc(2025, 1, 1)));
      });
    });

    group('loadEventsFromPositionAsync', () {
      test('should return empty list when no events exist', () async {
        // Act
        final events = await store.loadEventsFromPositionAsync(0, 100);

        // Assert - no events stored yet
        expect(events, isEmpty);
      });

      test('should return events from position', () async {
        // Arrange
        final s1 = const StreamId('stream-1');
        final s2 = const StreamId('stream-2');

        await store.appendEventsAsync(
          s1,
          ExpectedVersion.noStream,
          [_createStoredEvent(s1, 0, 'e1')],
          aggregateType: 'TestAggregate',
        );
        await store.appendEventsAsync(
          s2,
          ExpectedVersion.noStream,
          [_createStoredEvent(s2, 0, 'e2')],
          aggregateType: 'TestAggregate',
        );

        // Act - load from position 1 (skip first event)
        final events = await store.loadEventsFromPositionAsync(1, 100);

        // Assert - only the second event should be returned
        expect(events.length, equals(1));
        expect(events.first.globalSequence, equals(1));
      });

      test('should respect limit parameter', () async {
        // Arrange
        final s1 = const StreamId('stream-1');
        await store.appendEventsAsync(s1, ExpectedVersion.noStream, [
          _createStoredEvent(s1, 0, 'e1'),
          _createStoredEvent(s1, 1, 'e2'),
          _createStoredEvent(s1, 2, 'e3'),
        ], aggregateType: 'TestAggregate');

        // Act
        final events = await store.loadEventsFromPositionAsync(0, 2);

        // Assert - should only return the first 2 events
        expect(events.length, equals(2));
        expect(events[0].globalSequence, equals(0));
        expect(events[1].globalSequence, equals(1));
      });

      test('should order events by global sequence', () async {
        // Arrange
        final s1 = const StreamId('stream-1');
        final s2 = const StreamId('stream-2');

        await store.appendEventsAsync(
          s1,
          ExpectedVersion.noStream,
          [_createStoredEvent(s1, 0, 'e1')],
          aggregateType: 'TestAggregate',
        );
        await store.appendEventsAsync(
          s2,
          ExpectedVersion.noStream,
          [_createStoredEvent(s2, 0, 'e2')],
          aggregateType: 'TestAggregate',
        );
        await store.appendEventsAsync(
          s1,
          ExpectedVersion.exact(0),
          [_createStoredEvent(s1, 1, 'e3')],
          aggregateType: 'TestAggregate',
        );

        // Act
        final events = await store.loadEventsFromPositionAsync(0, 100);

        // Assert - events ordered by global sequence
        expect(events.length, equals(3));
        expect(events[0].globalSequence, equals(0));
        expect(events[1].globalSequence, equals(1));
        expect(events[2].globalSequence, equals(2));
      });
    });

    group('getMaxGlobalSequenceAsync', () {
      test('should return null when no events', () async {
        // Act
        final maxSeq = await store.getMaxGlobalSequenceAsync();

        // Assert - no events means null max sequence
        expect(maxSeq, isNull);
      });

      test('should return max global sequence', () async {
        // Arrange
        final s1 = const StreamId('stream-1');
        await store.appendEventsAsync(s1, ExpectedVersion.noStream, [
          _createStoredEvent(s1, 0, 'e1'),
          _createStoredEvent(s1, 1, 'e2'),
          _createStoredEvent(s1, 2, 'e3'),
        ], aggregateType: 'TestAggregate');

        // Act
        final maxSeq = await store.getMaxGlobalSequenceAsync();

        // Assert - max sequence should be 2 (0-indexed for 3 events)
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
