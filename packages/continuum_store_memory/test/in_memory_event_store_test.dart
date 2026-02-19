import 'package:continuum/continuum.dart' hide EventFromJsonFactory, EventSerializerEntry, EventSerializerRegistry, EventToJsonFactory, GeneratedAggregate;
import 'package:continuum_event_sourcing/continuum_event_sourcing.dart';
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
        await store.appendEventsAsync(streamId, ExpectedVersion.noStream, [_createStoredEvent(streamId, 0, 'first')], aggregateType: 'TestAggregate');

        // Act - append second event
        await store.appendEventsAsync(streamId, ExpectedVersion.exact(0), [_createStoredEvent(streamId, 1, 'second')], aggregateType: 'TestAggregate');

        // Assert - versions should be 0 and 1
        final loaded = await store.loadStreamAsync(streamId);
        expect(loaded[0].version, equals(0));
        expect(loaded[1].version, equals(1));
      });

      test('should throw ConcurrencyException when expected version mismatches', () async {
        // Arrange
        final streamId = const StreamId('concurrent_stream');
        await store.appendEventsAsync(streamId, ExpectedVersion.noStream, [_createStoredEvent(streamId, 0, 'first')], aggregateType: 'TestAggregate');

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
        await store.appendEventsAsync(streamId, ExpectedVersion.noStream, [_createStoredEvent(streamId, 0, 'first')], aggregateType: 'TestAggregate');

        // Act & Assert - noStream on existing stream should throw
        expect(
          () => store.appendEventsAsync(streamId, ExpectedVersion.noStream, [_createStoredEvent(streamId, 1, 'duplicate')], aggregateType: 'TestAggregate'),
          throwsA(isA<ConcurrencyException>()),
        );
      });

      test('should handle multiple events in single append', () async {
        // Arrange
        final streamId = const StreamId('batch_stream');
        final events = [_createStoredEvent(streamId, 0, 'event_1'), _createStoredEvent(streamId, 1, 'event_2'), _createStoredEvent(streamId, 2, 'event_3')];

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
        await store.appendEventsAsync(stream1, ExpectedVersion.noStream, [_createStoredEvent(stream1, 0, 'first')], aggregateType: 'TestAggregate');
        await store.appendEventsAsync(stream2, ExpectedVersion.noStream, [_createStoredEvent(stream2, 0, 'second')], aggregateType: 'TestAggregate');

        // Assert - global sequences should be ordered across streams
        final events1 = await store.loadStreamAsync(stream1);
        final events2 = await store.loadStreamAsync(stream2);
        expect(events1[0].globalSequence, equals(0));
        expect(events2[0].globalSequence, equals(1));
      });

      test('preserves StoredEvent.domainEvent when appending', () async {
        final streamId = const StreamId('domain_event_stream');
        final domainEvent = _TestDomainEvent(eventId: EventId.fromUlid());

        final stored = StoredEvent.fromContinuumEvent(
          continuumEvent: domainEvent,
          streamId: streamId,
          version: 0,
          eventType: 'domain.test',
          data: const {'k': 'v'},
        );

        await store.appendEventsAsync(streamId, ExpectedVersion.noStream, [stored], aggregateType: 'TestAggregate');

        final loaded = await store.loadStreamAsync(streamId);
        expect(loaded, hasLength(1));
        expect(loaded.single.domainEvent, same(domainEvent));
      });
    });

    group('appendEventsToStreamsAsync', () {
      test('should append events to multiple streams atomically', () async {
        // Arrange
        final StreamId stream1 = const StreamId('atomic_stream_1');
        final StreamId stream2 = const StreamId('atomic_stream_2');

        final Map<StreamId, StreamAppendBatch> batches = <StreamId, StreamAppendBatch>{
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
          aggregateType: 'TestAggregate',
        );

        final Map<StreamId, StreamAppendBatch> batches = <StreamId, StreamAppendBatch>{
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
        await store.appendEventsAsync(streamId, ExpectedVersion.noStream, [_createStoredEvent(streamId, 0, 'event')], aggregateType: 'TestAggregate');

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
        await store.appendEventsAsync(const StreamId('stream_1'), ExpectedVersion.noStream, [
          _createStoredEvent(const StreamId('stream_1'), 0, 'event'),
        ], aggregateType: 'TestAggregate');
        await store.appendEventsAsync(const StreamId('stream_2'), ExpectedVersion.noStream, [
          _createStoredEvent(const StreamId('stream_2'), 0, 'event'),
        ], aggregateType: 'TestAggregate');

        // Assert
        expect(store.streamCount, equals(2));
      });

      test('should track total event count', () async {
        // Arrange
        final streamId = const StreamId('counted');
        await store.appendEventsAsync(streamId, ExpectedVersion.noStream, [
          _createStoredEvent(streamId, 0, 'event_1'),
          _createStoredEvent(streamId, 1, 'event_2'),
        ], aggregateType: 'TestAggregate');

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
        ], aggregateType: 'TestAggregate');
        await store.appendEventsAsync(s2, ExpectedVersion.noStream, [
          _createStoredEvent(s2, 0, 'e2'),
        ], aggregateType: 'TestAggregate');

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
        ], aggregateType: 'TestAggregate');

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
        ], aggregateType: 'TestAggregate');
        await store.appendEventsAsync(s2, ExpectedVersion.noStream, [
          _createStoredEvent(s2, 0, 'e2'),
        ], aggregateType: 'TestAggregate');
        await store.appendEventsAsync(s1, ExpectedVersion.exact(0), [
          _createStoredEvent(s1, 1, 'e3'),
        ], aggregateType: 'TestAggregate');

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
        ], aggregateType: 'TestAggregate');

        final maxSeq = await store.getMaxGlobalSequenceAsync();

        expect(maxSeq, equals(2));
      });
    });

    group('getStreamIdsByAggregateTypeAsync', () {
      test('should return empty list when no streams exist', () async {
        // Act
        final result = await store.getStreamIdsByAggregateTypeAsync('Counter');

        // Assert — no streams have been persisted, so nothing should match.
        expect(result, isEmpty);
      });

      test('should return empty list when no streams match the type', () async {
        // Arrange — persist a stream tagged with a different aggregate type.
        final streamId = const StreamId('stream-1');
        await store.appendEventsAsync(
          streamId,
          ExpectedVersion.noStream,
          [_createStoredEvent(streamId, 0, 'created')],
          aggregateType: 'Counter',
        );

        // Act — query for a type that was never stored.
        final result = await store.getStreamIdsByAggregateTypeAsync('Invoice');

        // Assert — mismatched type should return no results.
        expect(result, isEmpty);
      });

      test('should return stream IDs that match the given type', () async {
        // Arrange — persist two streams with the same aggregate type.
        final stream1 = const StreamId('counter-1');
        final stream2 = const StreamId('counter-2');

        await store.appendEventsAsync(
          stream1,
          ExpectedVersion.noStream,
          [_createStoredEvent(stream1, 0, 'created')],
          aggregateType: 'Counter',
        );
        await store.appendEventsAsync(
          stream2,
          ExpectedVersion.noStream,
          [_createStoredEvent(stream2, 0, 'created')],
          aggregateType: 'Counter',
        );

        // Act
        final result = await store.getStreamIdsByAggregateTypeAsync('Counter');

        // Assert — both streams should be returned.
        expect(result, hasLength(2));
        expect(
          result.map((id) => id.value).toSet(),
          equals({'counter-1', 'counter-2'}),
        );
      });

      test('should filter correctly between different aggregate types', () async {
        // Arrange — persist streams tagged with two different aggregate types.
        final counterStream = const StreamId('counter-1');
        final invoiceStream = const StreamId('invoice-1');

        await store.appendEventsAsync(
          counterStream,
          ExpectedVersion.noStream,
          [_createStoredEvent(counterStream, 0, 'created')],
          aggregateType: 'Counter',
        );
        await store.appendEventsAsync(
          invoiceStream,
          ExpectedVersion.noStream,
          [_createStoredEvent(invoiceStream, 0, 'created')],
          aggregateType: 'Invoice',
        );

        // Act
        final counters = await store.getStreamIdsByAggregateTypeAsync('Counter');
        final invoices = await store.getStreamIdsByAggregateTypeAsync('Invoice');

        // Assert — each query should return only its own type's streams.
        expect(counters, hasLength(1));
        expect(counters.single.value, equals('counter-1'));
        expect(invoices, hasLength(1));
        expect(invoices.single.value, equals('invoice-1'));
      });

      test('should return IDs for streams created via atomic batch writes', () async {
        // Arrange — persist via the atomic multi-stream API.
        final stream1 = const StreamId('atomic-1');
        final stream2 = const StreamId('atomic-2');

        await store.appendEventsToStreamsAsync({
          stream1: StreamAppendBatch(
            expectedVersion: ExpectedVersion.noStream,
            events: [_createStoredEvent(stream1, 0, 'created')],
            aggregateType: 'Counter',
          ),
          stream2: StreamAppendBatch(
            expectedVersion: ExpectedVersion.noStream,
            events: [_createStoredEvent(stream2, 0, 'created')],
            aggregateType: 'Counter',
          ),
        });

        // Act
        final result = await store.getStreamIdsByAggregateTypeAsync('Counter');

        // Assert — both streams from the atomic batch should be found.
        expect(result, hasLength(2));
      });

      test('should preserve aggregate type when appending more events to existing stream', () async {
        // Arrange — create a stream, then append more events to it.
        final streamId = const StreamId('counter-append');

        await store.appendEventsAsync(
          streamId,
          ExpectedVersion.noStream,
          [_createStoredEvent(streamId, 0, 'created')],
          aggregateType: 'Counter',
        );
        await store.appendEventsAsync(
          streamId,
          ExpectedVersion.exact(0),
          [_createStoredEvent(streamId, 1, 'incremented')],
          aggregateType: 'Counter',
        );

        // Act
        final result = await store.getStreamIdsByAggregateTypeAsync('Counter');

        // Assert — stream should still appear exactly once (not duplicated).
        expect(result, hasLength(1));
        expect(result.single.value, equals('counter-append'));
      });

      test('should return empty list after clear()', () async {
        // Arrange — persist and then clear.
        final streamId = const StreamId('counter-cleared');
        await store.appendEventsAsync(
          streamId,
          ExpectedVersion.noStream,
          [_createStoredEvent(streamId, 0, 'created')],
          aggregateType: 'Counter',
        );

        store.clear();

        // Act
        final result = await store.getStreamIdsByAggregateTypeAsync('Counter');

        // Assert — clear must also remove aggregate type metadata.
        expect(result, isEmpty);
      });
    });
  });
}

final class _TestDomainEvent implements ContinuumEvent {
  _TestDomainEvent({
    required EventId eventId,
    DateTime? occurredOn,
    Map<String, Object?> metadata = const {},
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
