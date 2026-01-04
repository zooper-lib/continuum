import 'dart:io';

import 'package:continuum/continuum.dart';
import 'package:continuum_store_hive/continuum_store_hive.dart';
import 'package:hive/hive.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late HiveEventStore store;

  setUp(() async {
    // Create a temporary directory for each test
    tempDir = await Directory.systemTemp.createTemp('hive_test_');
    Hive.init(tempDir.path);
    store = await HiveEventStore.openAsync(boxName: 'test');
  });

  tearDown(() async {
    await store.closeAsync();
    await Hive.close();
    // Clean up temp directory
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('HiveEventStore', () {
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
    });

    group('persistence', () {
      test('should persist events across store reopening', () async {
        // Arrange
        final streamId = const StreamId('persisted_stream');
        await store.appendEventsAsync(streamId, ExpectedVersion.noStream, [_createStoredEvent(streamId, 0, 'persisted_event')]);

        // Act - close and reopen
        await store.closeAsync();
        store = await HiveEventStore.openAsync(boxName: 'test');
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

        await store.appendEventsAsync(streamId, ExpectedVersion.noStream, [event]);

        // Act - close and reopen
        await store.closeAsync();
        store = await HiveEventStore.openAsync(boxName: 'test');
        final loaded = await store.loadStreamAsync(streamId);

        // Assert - data should be preserved
        expect(loaded[0].data, equals(originalData));
        expect(loaded[0].metadata, equals({'meta': 'data'}));
        expect(loaded[0].occurredOn, equals(DateTime.utc(2025, 1, 1)));
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
