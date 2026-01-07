import 'package:continuum/continuum.dart';
import 'package:test/test.dart';

void main() {
  group('UnsupportedEventException', () {
    test('should store event type and aggregate type', () {
      // Arrange & Act
      final exception = const UnsupportedEventException(
        eventType: String,
        aggregateType: int,
      );

      // Assert - types should be stored
      expect(exception.eventType, equals(String));
      expect(exception.aggregateType, equals(int));
    });

    test('should have meaningful toString', () {
      // Arrange
      final exception = const UnsupportedEventException(
        eventType: String,
        aggregateType: int,
      );

      // Act
      final message = exception.toString();

      // Assert - message should include both types
      expect(message, contains('String'));
      expect(message, contains('int'));
    });
  });

  group('InvalidCreationEventException', () {
    test('should store event type and aggregate type', () {
      // Arrange & Act
      final exception = const InvalidCreationEventException(
        eventType: String,
        aggregateType: int,
      );

      // Assert - types should be stored
      expect(exception.eventType, equals(String));
      expect(exception.aggregateType, equals(int));
    });

    test('should have meaningful toString', () {
      // Arrange
      final exception = const InvalidCreationEventException(
        eventType: String,
        aggregateType: int,
      );

      // Act
      final message = exception.toString();

      // Assert - message should indicate creation event issue
      expect(message, contains('creation'));
      expect(message.toLowerCase(), contains('string'));
    });
  });

  group('UnknownEventTypeException', () {
    test('should store event type string', () {
      // Arrange
      const eventType = 'some.unknown.event';

      // Act
      final exception = const UnknownEventTypeException(eventType: eventType);

      // Assert - event type should be stored
      expect(exception.eventType, equals(eventType));
    });

    test('should have meaningful toString', () {
      // Arrange
      const eventType = 'missing.event.type';
      final exception = const UnknownEventTypeException(eventType: eventType);

      // Act
      final message = exception.toString();

      // Assert - message should include the event type
      expect(message, contains(eventType));
    });
  });

  group('ConcurrencyException', () {
    test('should store stream ID and version information', () {
      // Arrange
      final streamId = const StreamId('stream_123');

      // Act
      final exception = ConcurrencyException(
        streamId: streamId,
        expectedVersion: 5,
        actualVersion: 7,
      );

      // Assert - all fields should be stored
      expect(exception.streamId, equals(streamId));
      expect(exception.expectedVersion, equals(5));
      expect(exception.actualVersion, equals(7));
    });

    test('should have meaningful toString', () {
      // Arrange
      final exception = const ConcurrencyException(
        streamId: StreamId('cart_456'),
        expectedVersion: 3,
        actualVersion: 5,
      );

      // Act
      final message = exception.toString();

      // Assert - message should include relevant information
      expect(message, contains('cart_456'));
      expect(message, contains('3'));
      expect(message, contains('5'));
    });
  });

  group('StreamNotFoundException', () {
    test('should store stream ID', () {
      // Arrange
      final streamId = const StreamId('missing_stream');

      // Act
      final exception = StreamNotFoundException(streamId: streamId);

      // Assert - stream ID should be stored
      expect(exception.streamId, equals(streamId));
    });

    test('should have meaningful toString', () {
      // Arrange
      final exception = const StreamNotFoundException(
        streamId: StreamId('not_found_123'),
      );

      // Act
      final message = exception.toString();

      // Assert - message should include the stream ID
      expect(message, contains('not_found_123'));
    });
  });
}
