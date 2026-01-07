import 'package:continuum/continuum.dart';
import 'package:test/test.dart';

void main() {
  group('ExpectedVersion', () {
    group('noStream', () {
      test('should have value of -1', () {
        // Assert - noStream is a special value indicating new stream
        expect(ExpectedVersion.noStream.value, equals(-1));
      });

      test('should return true for isNoStream', () {
        // Assert
        expect(ExpectedVersion.noStream.isNoStream, isTrue);
      });
    });

    group('exact', () {
      test('should store the specified version', () {
        // Arrange & Act
        final version = ExpectedVersion.exact(5);

        // Assert - version should be stored correctly
        expect(version.value, equals(5));
      });

      test('should accept zero as a valid version', () {
        // Arrange & Act
        final version = ExpectedVersion.exact(0);

        // Assert - zero is the first event's version
        expect(version.value, equals(0));
      });

      test('should throw for negative versions', () {
        // Act & Assert - negative versions are invalid
        expect(() => ExpectedVersion.exact(-1), throwsA(isA<ArgumentError>()));
      });

      test('should return false for isNoStream', () {
        // Arrange & Act
        final version = ExpectedVersion.exact(3);

        // Assert
        expect(version.isNoStream, isFalse);
      });
    });

    group('equality', () {
      test('should be equal when values match', () {
        // Arrange & Act
        final version1 = ExpectedVersion.exact(5);
        final version2 = ExpectedVersion.exact(5);

        // Assert
        expect(version1, equals(version2));
        expect(version1.hashCode, equals(version2.hashCode));
      });

      test('should not be equal when values differ', () {
        // Arrange & Act
        final version1 = ExpectedVersion.exact(5);
        final version2 = ExpectedVersion.exact(6);

        // Assert
        expect(version1, isNot(equals(version2)));
      });
    });

    group('toString', () {
      test('should have meaningful representation for noStream', () {
        // Act
        final str = ExpectedVersion.noStream.toString();

        // Assert
        expect(str.toLowerCase(), contains('nostream'));
      });

      test('should have meaningful representation for exact', () {
        // Arrange
        final version = ExpectedVersion.exact(42);

        // Act
        final str = version.toString();

        // Assert
        expect(str, contains('42'));
      });
    });
  });
}
