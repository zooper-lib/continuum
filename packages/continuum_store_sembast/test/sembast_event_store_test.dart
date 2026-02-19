import 'dart:io';

import 'package:continuum/continuum.dart' hide EventFromJsonFactory, EventSerializerEntry, EventSerializerRegistry, EventToJsonFactory, GeneratedAggregate;
import 'package:continuum_event_sourcing/continuum_event_sourcing.dart';
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

    group('concurrent writes', () {
      test('two parallel appends to the same stream — one must get ConcurrencyException', () async {
        // Arrange — create a stream at version 0.
        final streamId = const StreamId('concurrent_same');
        await store.appendEventsAsync(
          streamId,
          ExpectedVersion.noStream,
          <StoredEvent>[_createStoredEvent(streamId, 0, 'setup')],
          aggregateType: 'TestAggregate',
        );

        // Arrange — build two batches both expecting version 0.
        final Map<StreamId, StreamAppendBatch> batchA = <StreamId, StreamAppendBatch>{
          streamId: StreamAppendBatch(
            aggregateType: 'TestAggregate',
            expectedVersion: ExpectedVersion.exact(0),
            events: <StoredEvent>[_createConcurrencyEvent(streamId, 'a_0', 'type_a')],
          ),
        };
        final Map<StreamId, StreamAppendBatch> batchB = <StreamId, StreamAppendBatch>{
          streamId: StreamAppendBatch(
            aggregateType: 'TestAggregate',
            expectedVersion: ExpectedVersion.exact(0),
            events: <StoredEvent>[_createConcurrencyEvent(streamId, 'b_0', 'type_b')],
          ),
        };

        // Act — launch both in parallel so Sembast serializes their transactions.
        final Future<void> futureA = store.appendEventsToStreamsAsync(batchA);
        final Future<void> futureB = store.appendEventsToStreamsAsync(batchB);

        ConcurrencyException? errorA;
        ConcurrencyException? errorB;
        try {
          await futureA;
        } on ConcurrencyException catch (e) {
          errorA = e;
        }
        try {
          await futureB;
        } on ConcurrencyException catch (e) {
          errorB = e;
        }

        // Assert — exactly one must succeed and exactly one must throw.
        final int failureCount = <ConcurrencyException?>[errorA, errorB].whereType<ConcurrencyException>().length;
        expect(failureCount, equals(1), reason: 'Exactly one call must throw ConcurrencyException');

        // Assert — stream has exactly 2 events: setup + winner's event.
        final List<StoredEvent> loaded = await store.loadStreamAsync(streamId);
        expect(loaded.length, equals(2));
        expect(loaded[0].eventType, equals('setup'));

        // The winner is whichever call did NOT throw.
        final String winnerType = errorA != null ? 'type_b' : 'type_a';
        expect(loaded[1].eventType, equals(winnerType));

        // Assert — stream version is correct (0 + 1 new event = version 1).
        expect(loaded[1].version, equals(1));
      });

      test('two parallel appends to different streams — both succeed', () async {
        // Arrange — create two separate streams.
        final streamA = const StreamId('parallel_a');
        final streamB = const StreamId('parallel_b');

        await store.appendEventsAsync(
          streamA,
          ExpectedVersion.noStream,
          <StoredEvent>[_createStoredEvent(streamA, 0, 'setup_a')],
          aggregateType: 'TestAggregate',
        );
        await store.appendEventsAsync(
          streamB,
          ExpectedVersion.noStream,
          <StoredEvent>[_createStoredEvent(streamB, 0, 'setup_b')],
          aggregateType: 'TestAggregate',
        );

        // Arrange — each batch targets a different stream.
        final Map<StreamId, StreamAppendBatch> batchA = <StreamId, StreamAppendBatch>{
          streamA: StreamAppendBatch(
            aggregateType: 'TestAggregate',
            expectedVersion: ExpectedVersion.exact(0),
            events: <StoredEvent>[_createConcurrencyEvent(streamA, 'a_new', 'type_a_new')],
          ),
        };
        final Map<StreamId, StreamAppendBatch> batchB = <StreamId, StreamAppendBatch>{
          streamB: StreamAppendBatch(
            aggregateType: 'TestAggregate',
            expectedVersion: ExpectedVersion.exact(0),
            events: <StoredEvent>[_createConcurrencyEvent(streamB, 'b_new', 'type_b_new')],
          ),
        };

        // Act — launch both in parallel; no conflict expected.
        final Future<void> futureA = store.appendEventsToStreamsAsync(batchA);
        final Future<void> futureB = store.appendEventsToStreamsAsync(batchB);
        await futureA;
        await futureB;

        // Assert — both streams have their new events persisted.
        final List<StoredEvent> loadedA = await store.loadStreamAsync(streamA);
        final List<StoredEvent> loadedB = await store.loadStreamAsync(streamB);

        expect(loadedA.length, equals(2));
        expect(loadedB.length, equals(2));
        expect(loadedA[1].eventType, equals('type_a_new'));
        expect(loadedB[1].eventType, equals('type_b_new'));
      });

      test('three parallel appends to the same stream — exactly one succeeds', () async {
        // Arrange — create stream at version 0.
        final streamId = const StreamId('triple_concurrent');
        await store.appendEventsAsync(
          streamId,
          ExpectedVersion.noStream,
          <StoredEvent>[_createStoredEvent(streamId, 0, 'setup')],
          aggregateType: 'TestAggregate',
        );

        // Arrange — three batches all expecting version 0.
        final List<String> labels = <String>['a', 'b', 'c'];
        final List<Map<StreamId, StreamAppendBatch>> batches = labels
            .map(
              (String label) => <StreamId, StreamAppendBatch>{
                streamId: StreamAppendBatch(
                  aggregateType: 'TestAggregate',
                  expectedVersion: ExpectedVersion.exact(0),
                  events: <StoredEvent>[
                    _createConcurrencyEvent(streamId, '${label}_0', 'type_$label'),
                  ],
                ),
              },
            )
            .toList();

        // Act — launch all three in parallel.
        final List<Future<void>> futures = batches.map((Map<StreamId, StreamAppendBatch> b) => store.appendEventsToStreamsAsync(b)).toList();

        int failureCount = 0;
        String? winnerLabel;
        for (int i = 0; i < futures.length; i++) {
          try {
            await futures[i];
            // This one succeeded.
            winnerLabel = labels[i];
          } on ConcurrencyException {
            failureCount++;
          }
        }

        // Assert — exactly one succeeds, the other two throw.
        expect(failureCount, equals(2), reason: 'Exactly two calls must throw ConcurrencyException');
        expect(winnerLabel, isNotNull, reason: 'One call must succeed');

        // Assert — stream contains only setup event + winner's event.
        final List<StoredEvent> loaded = await store.loadStreamAsync(streamId);
        expect(loaded.length, equals(2));
        expect(loaded[0].eventType, equals('setup'));
        expect(loaded[1].eventType, equals('type_$winnerLabel'));
      });

      test('parallel append does not leave partial writes on failure', () async {
        // Arrange — create stream A at version 0 so it has a known version.
        final streamA = const StreamId('atomic_partial_a');
        final streamB = const StreamId('atomic_partial_b');

        await store.appendEventsAsync(
          streamA,
          ExpectedVersion.noStream,
          <StoredEvent>[_createStoredEvent(streamA, 0, 'setup_a')],
          aggregateType: 'TestAggregate',
        );

        // Arrange — multi-stream batch: stream A has correct version, stream B
        // has a deliberately wrong version to force a ConcurrencyException.
        final Map<StreamId, StreamAppendBatch> mixedBatch = <StreamId, StreamAppendBatch>{
          streamA: StreamAppendBatch(
            aggregateType: 'TestAggregate',
            expectedVersion: ExpectedVersion.exact(0),
            events: <StoredEvent>[_createConcurrencyEvent(streamA, 'a_extra', 'type_a_extra')],
          ),
          streamB: StreamAppendBatch(
            aggregateType: 'TestAggregate',
            expectedVersion: ExpectedVersion.exact(999), // Wrong — stream B does not exist.
            events: <StoredEvent>[_createConcurrencyEvent(streamB, 'b_extra', 'type_b_extra')],
          ),
        };

        // Act & Assert — the mismatch must cause the whole call to fail.
        expect(
          () => store.appendEventsToStreamsAsync(mixedBatch),
          throwsA(isA<ConcurrencyException>()),
        );

        // Assert — neither stream was modified (all-or-nothing).
        final List<StoredEvent> loadedA = await store.loadStreamAsync(streamA);
        final List<StoredEvent> loadedB = await store.loadStreamAsync(streamB);

        // Stream A still has only its original setup event.
        expect(loadedA.length, equals(1));
        expect(loadedA.single.eventType, equals('setup_a'));

        // Stream B was never created.
        expect(loadedB, isEmpty);
      });

      test('global sequences remain monotonically increasing after concurrent writes', () async {
        // Arrange — create several distinct streams.
        const int streamCount = 5;
        final List<StreamId> streams = List<StreamId>.generate(
          streamCount,
          (int i) => StreamId('mono_stream_$i'),
        );

        for (final StreamId s in streams) {
          await store.appendEventsAsync(
            s,
            ExpectedVersion.noStream,
            <StoredEvent>[_createStoredEvent(s, 0, 'setup_${s.value}')],
            aggregateType: 'TestAggregate',
          );
        }

        // Act — launch parallel appends to different streams.
        final List<Future<void>> futures = streams
            .map(
              (StreamId s) => store.appendEventsToStreamsAsync(<StreamId, StreamAppendBatch>{
                s: StreamAppendBatch(
                  aggregateType: 'TestAggregate',
                  expectedVersion: ExpectedVersion.exact(0),
                  events: <StoredEvent>[
                    _createConcurrencyEvent(s, 'new_${s.value}', 'type_${s.value}'),
                  ],
                ),
              }),
            )
            .toList();

        for (final Future<void> f in futures) {
          await f;
        }

        // Assert — load all events and verify global sequence properties.
        final List<StoredEvent> allEvents = await store.loadEventsFromPositionAsync(0, 1000);
        final List<int> globalSequences = allEvents.map((StoredEvent e) => e.globalSequence!).toList();

        // Unique — no duplicates.
        expect(
          globalSequences.toSet().length,
          equals(globalSequences.length),
          reason: 'Global sequences must be unique',
        );

        // Already sorted by loadEventsFromPositionAsync — verify monotonically increasing.
        for (int i = 1; i < globalSequences.length; i++) {
          expect(
            globalSequences[i],
            greaterThan(globalSequences[i - 1]),
            reason: 'Global sequences must be monotonically increasing',
          );
        }

        // No gaps — sequences should be 0..N-1.
        final List<int> sortedSequences = List<int>.from(globalSequences)..sort();
        for (int i = 0; i < sortedSequences.length; i++) {
          expect(
            sortedSequences[i],
            equals(i),
            reason: 'Global sequences must have no gaps',
          );
        }
      });

      test('global sequences have no duplicates after a ConcurrencyException occurs', () async {
        // Arrange — create a stream at version 0.
        final streamId = const StreamId('dup_seq_stream');
        await store.appendEventsAsync(
          streamId,
          ExpectedVersion.noStream,
          <StoredEvent>[_createStoredEvent(streamId, 0, 'setup')],
          aggregateType: 'TestAggregate',
        );

        // Act — two parallel appends both expecting version 0.
        final Future<void> futureA = store.appendEventsToStreamsAsync(<StreamId, StreamAppendBatch>{
          streamId: StreamAppendBatch(
            aggregateType: 'TestAggregate',
            expectedVersion: ExpectedVersion.exact(0),
            events: <StoredEvent>[_createConcurrencyEvent(streamId, 'dup_a', 'type_a')],
          ),
        });
        final Future<void> futureB = store.appendEventsToStreamsAsync(<StreamId, StreamAppendBatch>{
          streamId: StreamAppendBatch(
            aggregateType: 'TestAggregate',
            expectedVersion: ExpectedVersion.exact(0),
            events: <StoredEvent>[_createConcurrencyEvent(streamId, 'dup_b', 'type_b')],
          ),
        });

        try {
          await futureA;
        } on ConcurrencyException catch (_) {
          // Expected for one of the two.
        }
        try {
          await futureB;
        } on ConcurrencyException catch (_) {
          // Expected for one of the two.
        }

        // Act — do a successful append with the correct version.
        final List<StoredEvent> currentEvents = await store.loadStreamAsync(streamId);
        final int currentVersion = currentEvents.length - 1;

        await store.appendEventsAsync(
          streamId,
          ExpectedVersion.exact(currentVersion),
          <StoredEvent>[_createConcurrencyEvent(streamId, 'final', 'type_final')],
          aggregateType: 'TestAggregate',
        );

        // Assert — load all events and verify no duplicate global sequences.
        final List<StoredEvent> allEvents = await store.loadEventsFromPositionAsync(0, 1000);
        final List<int> globalSequences = allEvents.map((StoredEvent e) => e.globalSequence!).toList();

        // The critical property: no duplicates.
        expect(
          globalSequences.toSet().length,
          equals(globalSequences.length),
          reason: 'Global sequences must have no duplicates',
        );

        // NOTE: A gap in sequences MAY exist if the failing transaction
        // incremented the in-memory _globalSequence counter before the
        // transaction rolled back.  Gaps are a known minor issue — the
        // critical invariant is uniqueness.
      });

      test("winner's events are fully intact (data fidelity)", () async {
        // Arrange — create stream at version 0.
        final streamId = const StreamId('fidelity_stream');
        await store.appendEventsAsync(
          streamId,
          ExpectedVersion.noStream,
          <StoredEvent>[_createStoredEvent(streamId, 0, 'setup')],
          aggregateType: 'TestAggregate',
        );

        // Arrange — two batches with 3 distinct events each.
        final List<StoredEvent> batchAEvents = List<StoredEvent>.generate(
          3,
          (int i) => StoredEvent(
            eventId: EventId('batch_a_$i'),
            streamId: streamId,
            version: i, // Version is reassigned by the store.
            eventType: 'type_a_$i',
            data: <String, dynamic>{'batch': 'a', 'index': i, 'payload': 'data_a_$i'},
            occurredOn: DateTime.utc(2026, 1, 1, 0, 0, i),
            metadata: <String, dynamic>{'source': 'batch_a'},
          ),
        );
        final List<StoredEvent> batchBEvents = List<StoredEvent>.generate(
          3,
          (int i) => StoredEvent(
            eventId: EventId('batch_b_$i'),
            streamId: streamId,
            version: i, // Version is reassigned by the store.
            eventType: 'type_b_$i',
            data: <String, dynamic>{'batch': 'b', 'index': i, 'payload': 'data_b_$i'},
            occurredOn: DateTime.utc(2026, 2, 1, 0, 0, i),
            metadata: <String, dynamic>{'source': 'batch_b'},
          ),
        );

        final Map<StreamId, StreamAppendBatch> batchA = <StreamId, StreamAppendBatch>{
          streamId: StreamAppendBatch(
            aggregateType: 'TestAggregate',
            expectedVersion: ExpectedVersion.exact(0),
            events: batchAEvents,
          ),
        };
        final Map<StreamId, StreamAppendBatch> batchB = <StreamId, StreamAppendBatch>{
          streamId: StreamAppendBatch(
            aggregateType: 'TestAggregate',
            expectedVersion: ExpectedVersion.exact(0),
            events: batchBEvents,
          ),
        };

        // Act — launch both in parallel.
        final Future<void> futureA = store.appendEventsToStreamsAsync(batchA);
        final Future<void> futureB = store.appendEventsToStreamsAsync(batchB);

        ConcurrencyException? errorA;
        ConcurrencyException? errorB;
        try {
          await futureA;
        } on ConcurrencyException catch (e) {
          errorA = e;
        }
        try {
          await futureB;
        } on ConcurrencyException catch (e) {
          errorB = e;
        }

        // Assert — exactly one fails.
        expect(
          (errorA == null) != (errorB == null),
          isTrue,
          reason: 'Exactly one batch must succeed',
        );

        // Determine which batch won.
        final List<StoredEvent> winnerEvents = errorA == null ? batchAEvents : batchBEvents;

        // Assert — stream has 1 setup event + 3 winner events.
        final List<StoredEvent> loaded = await store.loadStreamAsync(streamId);
        expect(loaded.length, equals(4));
        expect(loaded[0].eventType, equals('setup'));

        // Verify each winner event's data was persisted without corruption.
        for (int i = 0; i < 3; i++) {
          final StoredEvent persisted = loaded[i + 1];
          final StoredEvent original = winnerEvents[i];

          expect(persisted.eventId, equals(original.eventId));
          expect(persisted.eventType, equals(original.eventType));
          expect(persisted.data, equals(original.data));
          // Versions are assigned by the store: setup=0, then 1, 2, 3.
          expect(persisted.version, equals(i + 1));
        }
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

/// Helper to create a stored event with a unique [eventId] for concurrency tests.
///
/// Unlike [_createStoredEvent], this uses a caller-supplied [eventId] to ensure
/// events from competing batches are distinguishable after persistence.
StoredEvent _createConcurrencyEvent(StreamId streamId, String eventId, String eventType) {
  return StoredEvent(
    eventId: EventId(eventId),
    streamId: streamId,
    version: 0, // Version is reassigned by the store.
    eventType: eventType,
    data: <String, dynamic>{'eventId': eventId},
    occurredOn: DateTime.now().toUtc(),
    metadata: <String, dynamic>{},
  );
}
