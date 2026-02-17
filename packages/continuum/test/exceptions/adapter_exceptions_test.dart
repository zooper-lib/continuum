import 'package:continuum/continuum.dart';
import 'package:test/test.dart';

void main() {
  group('TransientAdapterException', () {
    test('should store message and cause', () {
      // Arrange
      final cause = Exception('socket closed');

      // Act
      final exception = TransientAdapterException(
        message: 'Connection timed out',
        cause: cause,
      );

      // Assert - both fields should be stored
      expect(exception.message, equals('Connection timed out'));
      expect(exception.cause, same(cause));
    });

    test('should allow null cause', () {
      // Arrange & Act
      const exception = TransientAdapterException(
        message: 'Rate limited',
      );

      // Assert - cause defaults to null
      expect(exception.message, equals('Rate limited'));
      expect(exception.cause, isNull);
    });

    test('should implement Exception', () {
      // Arrange & Act
      const exception = TransientAdapterException(
        message: 'Timeout',
      );

      // Assert - must implement Exception, not Error
      expect(exception, isA<Exception>());
    });

    test('should have meaningful toString', () {
      // Arrange
      const exception = TransientAdapterException(
        message: 'Connection timed out',
      );

      // Act
      final message = exception.toString();

      // Assert - message should include the description
      expect(message, contains('TransientAdapterException'));
      expect(message, contains('Connection timed out'));
    });
  });

  group('PermanentAdapterException', () {
    test('should store message and cause', () {
      // Arrange
      final cause = Exception('HTTP 400');

      // Act
      final exception = PermanentAdapterException(
        message: 'Validation failed: email format invalid',
        cause: cause,
      );

      // Assert - both fields should be stored
      expect(
        exception.message,
        equals('Validation failed: email format invalid'),
      );
      expect(exception.cause, same(cause));
    });

    test('should allow null cause', () {
      // Arrange & Act
      const exception = PermanentAdapterException(
        message: 'Forbidden',
      );

      // Assert - cause defaults to null
      expect(exception.message, equals('Forbidden'));
      expect(exception.cause, isNull);
    });

    test('should implement Exception', () {
      // Arrange & Act
      const exception = PermanentAdapterException(
        message: 'Bad request',
      );

      // Assert - must implement Exception, not Error
      expect(exception, isA<Exception>());
    });

    test('should have meaningful toString', () {
      // Arrange
      const exception = PermanentAdapterException(
        message: 'Validation failed: email format invalid',
      );

      // Act
      final message = exception.toString();

      // Assert - message should include the description
      expect(message, contains('PermanentAdapterException'));
      expect(message, contains('Validation failed: email format invalid'));
    });
  });

  group('PartialSaveException', () {
    test('should store saved streams, failed streams, and cause', () {
      // Arrange
      const savedStream = StreamId('user-1');
      const failedStream = StreamId('playlist-1');
      final cause = Exception('network error');

      // Act
      final exception = PartialSaveException(
        savedStreams: [savedStream],
        failedStreams: [failedStream],
        cause: cause,
      );

      // Assert - all fields should be stored
      expect(exception.savedStreams, equals([savedStream]));
      expect(exception.failedStreams, equals([failedStream]));
      expect(exception.cause, same(cause));
    });

    test('should implement Exception', () {
      // Arrange & Act
      final exception = PartialSaveException(
        savedStreams: const [StreamId('s-1')],
        failedStreams: const [StreamId('s-2')],
        cause: Exception('fail'),
      );

      // Assert - must implement Exception, not Error
      expect(exception, isA<Exception>());
    });

    test('should have meaningful toString', () {
      // Arrange
      final exception = PartialSaveException(
        savedStreams: const [StreamId('user-1')],
        failedStreams: const [StreamId('playlist-1'), StreamId('order-1')],
        cause: Exception('backend error'),
      );

      // Act
      final message = exception.toString();

      // Assert - message should include counts and cause
      expect(message, contains('PartialSaveException'));
      expect(message, contains('1'));
      expect(message, contains('2'));
    });

    test('should support multiple saved and failed streams', () {
      // Arrange
      const saved1 = StreamId('s-1');
      const saved2 = StreamId('s-2');
      const failed1 = StreamId('s-3');
      const failed2 = StreamId('s-4');
      const failed3 = StreamId('s-5');

      // Act
      final exception = PartialSaveException(
        savedStreams: [saved1, saved2],
        failedStreams: [failed1, failed2, failed3],
        cause: Exception('partial failure'),
      );

      // Assert - lists should preserve all entries
      expect(exception.savedStreams, hasLength(2));
      expect(exception.failedStreams, hasLength(3));
      expect(exception.savedStreams, contains(saved1));
      expect(exception.savedStreams, contains(saved2));
      expect(exception.failedStreams, contains(failed1));
      expect(exception.failedStreams, contains(failed2));
      expect(exception.failedStreams, contains(failed3));
    });
  });
}
