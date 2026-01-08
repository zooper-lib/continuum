import 'package:continuum/continuum.dart';
import 'package:test/test.dart';

/// Test implementation of ContinuumEvent for testing purposes.
final class TestEvent extends ContinuumEvent {
  final String data;

  TestEvent({
    required super.eventId,
    required this.data,
    super.occurredOn,
    super.metadata,
  });
}

void main() {
  group('ContinuumEvent', () {
    test('should store eventId correctly', () {
      // Arrange
      final eventId = const EventId('evt_123');

      // Act
      final event = TestEvent(eventId: eventId, data: 'test');

      // Assert - eventId should be accessible
      expect(event.eventId, equals(eventId));
    });

    test('should default occurredOn to UTC now when not provided', () {
      // Arrange
      final before = DateTime.now().toUtc();

      // Act
      final event = TestEvent(eventId: const EventId('evt_123'), data: 'test');
      final after = DateTime.now().toUtc();

      // Assert - occurredOn should be between before and after
      expect(event.occurredOn.isUtc, isTrue);
      expect(
        event.occurredOn.isAfter(before.subtract(const Duration(seconds: 1))),
        isTrue,
      );
      expect(
        event.occurredOn.isBefore(after.add(const Duration(seconds: 1))),
        isTrue,
      );
    });

    test('should use provided occurredOn when specified', () {
      // Arrange
      final specificTime = DateTime.utc(2025, 1, 15, 10, 30);

      // Act
      final event = TestEvent(
        eventId: const EventId('evt_123'),
        data: 'test',
        occurredOn: specificTime,
      );

      // Assert - should use the provided time
      expect(event.occurredOn, equals(specificTime));
    });

    test('should default metadata to empty map when not provided', () {
      // Arrange & Act
      final event = TestEvent(eventId: const EventId('evt_123'), data: 'test');

      // Assert - metadata should be empty by default
      expect(event.metadata, isEmpty);
    });

    test('should use provided metadata when specified', () {
      // Arrange
      final metadata = {'correlationId': 'corr_123', 'userId': 'user_456'};

      // Act
      final event = TestEvent(
        eventId: const EventId('evt_123'),
        data: 'test',
        metadata: metadata,
      );

      // Assert - should use the provided metadata
      expect(event.metadata, equals(metadata));
    });
  });
}
