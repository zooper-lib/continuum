import 'package:continuum/continuum.dart';
import 'package:continuum_uow/continuum_uow.dart';
import 'package:test/test.dart';

void main() {
  group('ConcurrencyException', () {
    test('should store all fields correctly', () {
      // Arrange & Act
      final exception = ConcurrencyException(
        streamId: const StreamId('stream-1'),
        expectedVersion: 5,
        actualVersion: 7,
      );

      // Assert — all fields should be accessible
      expect(exception.streamId, equals(const StreamId('stream-1')));
      expect(exception.expectedVersion, equals(5));
      expect(exception.actualVersion, equals(7));
    });

    test('should generate default message from fields', () {
      // Arrange & Act
      final exception = ConcurrencyException(
        streamId: const StreamId('order-42'),
        expectedVersion: 3,
        actualVersion: 5,
      );

      // Assert — default message should include stream and versions
      expect(exception.message, contains('order-42'));
      expect(exception.message, contains('3'));
      expect(exception.message, contains('5'));
    });

    test('should use custom message when provided', () {
      // Arrange & Act
      final exception = ConcurrencyException(
        streamId: const StreamId('stream-1'),
        expectedVersion: 1,
        actualVersion: 2,
        message: 'custom conflict message',
      );

      // Assert — custom message should be used
      expect(exception.message, equals('custom conflict message'));
    });

    test('should implement Exception', () {
      // Arrange & Act
      final exception = ConcurrencyException(
        streamId: const StreamId('s'),
        expectedVersion: 0,
        actualVersion: 1,
      );

      // Assert — should be an Exception
      expect(exception, isA<Exception>());
    });

    test('should have meaningful toString', () {
      // Arrange & Act
      final exception = ConcurrencyException(
        streamId: const StreamId('abc'),
        expectedVersion: 2,
        actualVersion: 4,
      );
      final message = exception.toString();

      // Assert — toString should include the class name and message
      expect(message, contains('ConcurrencyException'));
    });
  });

  group('InvalidOperationException', () {
    test('should store message', () {
      // Arrange & Act
      const exception = InvalidOperationException(
        message: 'Cannot apply creation to tracked stream',
      );

      // Assert
      expect(
        exception.message,
        equals('Cannot apply creation to tracked stream'),
      );
    });

    test('should implement Exception', () {
      // Assert
      expect(
        const InvalidOperationException(message: 'test'),
        isA<Exception>(),
      );
    });

    test('should have meaningful toString', () {
      // Arrange
      const exception = InvalidOperationException(message: 'test error');

      // Assert
      expect(exception.toString(), contains('InvalidOperationException'));
      expect(exception.toString(), contains('test error'));
    });
  });

  group('UnsupportedOperationException', () {
    test('should store operationType and aggregateType', () {
      // Arrange & Act
      const exception = UnsupportedOperationException(
        operationType: String,
        aggregateType: int,
      );

      // Assert
      expect(exception.operationType, equals(String));
      expect(exception.aggregateType, equals(int));
    });

    test('should implement Exception', () {
      // Assert
      expect(
        const UnsupportedOperationException(
          operationType: String,
          aggregateType: int,
        ),
        isA<Exception>(),
      );
    });

    test('should have meaningful toString', () {
      // Arrange
      const exception = UnsupportedOperationException(
        operationType: String,
        aggregateType: int,
      );

      // Assert
      final message = exception.toString();
      expect(message, contains('UnsupportedOperationException'));
      expect(message, contains('String'));
      expect(message, contains('int'));
    });
  });

  group('PartialSaveException', () {
    test('should store savedStreams, failedStreams, and cause', () {
      // Arrange
      final saved = [const StreamId('s1'), const StreamId('s2')];
      final failed = [const StreamId('s3')];
      final cause = StateError('adapter failure');

      // Act
      final exception = PartialSaveException(
        savedStreams: saved,
        failedStreams: failed,
        cause: cause,
      );

      // Assert
      expect(exception.savedStreams, equals(saved));
      expect(exception.failedStreams, equals(failed));
      expect(exception.cause, equals(cause));
    });

    test('should implement Exception', () {
      // Assert
      expect(
        const PartialSaveException(
          savedStreams: [],
          failedStreams: [],
          cause: 'error',
        ),
        isA<Exception>(),
      );
    });

    test('should have meaningful toString', () {
      // Arrange
      const exception = PartialSaveException(
        savedStreams: [StreamId('s1')],
        failedStreams: [StreamId('s2'), StreamId('s3')],
        cause: 'some error',
      );

      // Assert
      final message = exception.toString();
      expect(message, contains('PartialSaveException'));
      expect(message, contains('1 streams saved'));
      expect(message, contains('2 streams failed'));
    });
  });
}
