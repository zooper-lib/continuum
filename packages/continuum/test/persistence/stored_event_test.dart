import 'package:continuum/continuum.dart';
import 'package:test/test.dart';

/// Test event for stored event testing.
final class TestStoredEvent extends ContinuumEvent {
  final String payload;

  TestStoredEvent({
    required super.eventId,
    required this.payload,
    super.occurredOn,
    super.metadata,
  });
}

void main() {
  group('StoredEvent', () {
    test('should store all fields correctly', () {
      // Arrange
      final eventId = const EventId('evt_123');
      final streamId = const StreamId('stream_456');
      final occurredOn = DateTime.utc(2025, 6, 15);
      final metadata = {'key': 'value'};
      final data = {'payload': 'test data'};

      // Act
      final stored = StoredEvent(
        eventId: eventId,
        streamId: streamId,
        version: 5,
        eventType: 'test.event',
        data: data,
        occurredOn: occurredOn,
        metadata: metadata,
        globalSequence: 100,
      );

      // Assert - all fields should be accessible
      expect(stored.eventId, equals(eventId));
      expect(stored.streamId, equals(streamId));
      expect(stored.version, equals(5));
      expect(stored.eventType, equals('test.event'));
      expect(stored.data, equals(data));
      expect(stored.occurredOn, equals(occurredOn));
      expect(stored.metadata, equals(metadata));
      expect(stored.globalSequence, equals(100));
    });

    test('should allow null globalSequence', () {
      // Arrange & Act
      final stored = StoredEvent(
        eventId: const EventId('evt_1'),
        streamId: const StreamId('stream_1'),
        version: 0,
        eventType: 'test.event',
        data: {},
        occurredOn: DateTime.now(),
        metadata: {},
        globalSequence: null,
      );

      // Assert
      expect(stored.globalSequence, isNull);
    });

    group('fromContinuumEvent', () {
      test('should create stored event from continuum event', () {
        // Arrange
        final eventId = const EventId('evt_789');
        final occurredOn = DateTime.utc(2025, 3, 20);
        final metadata = {'correlationId': 'corr_123'};

        final continuumEvent = TestStoredEvent(
          eventId: eventId,
          payload: 'test payload',
          occurredOn: occurredOn,
          metadata: metadata,
        );

        final streamId = const StreamId('stream_abc');
        final data = {'payload': 'test payload'};

        // Act
        final stored = StoredEvent.fromContinuumEvent(
          continuumEvent: continuumEvent,
          streamId: streamId,
          version: 3,
          eventType: 'test.stored.event',
          data: data,
          globalSequence: 50,
        );

        // Assert - should copy domain event fields and add storage metadata
        expect(stored.eventId, equals(eventId));
        expect(stored.streamId, equals(streamId));
        expect(stored.version, equals(3));
        expect(stored.eventType, equals('test.stored.event'));
        expect(stored.data, equals(data));
        expect(stored.occurredOn, equals(occurredOn));
        expect(stored.metadata, equals(metadata));
        expect(stored.globalSequence, equals(50));
      });

      test('should work without globalSequence', () {
        // Arrange
        final continuumEvent = TestStoredEvent(
          eventId: const EventId('evt_1'),
          payload: 'test',
        );

        // Act
        final stored = StoredEvent.fromContinuumEvent(
          continuumEvent: continuumEvent,
          streamId: const StreamId('stream_1'),
          version: 0,
          eventType: 'test.event',
          data: {'payload': 'test'},
        );

        // Assert
        expect(stored.globalSequence, isNull);
      });
    });
  });
}
