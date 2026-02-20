import 'package:continuum/continuum.dart';
import 'package:test/test.dart';

final class _TargetType {
  const _TargetType();
}

void main() {
  group('OperationFor', () {
    test('should store type, key, and creation flag', () {
      // Arrange
      const key = 'my.operation.key';

      // Act
      const annotation = OperationFor(
        type: _TargetType,
        key: key,
        creation: true,
      );

      // Assert
      expect(annotation.type, equals(_TargetType));
      expect(annotation.key, equals(key));
      expect(annotation.creation, isTrue);
    });

    test('should default key to null and creation to false', () {
      // Arrange & Act
      const annotation = OperationFor(type: _TargetType);

      // Assert
      expect(annotation.key, isNull);
      expect(annotation.creation, isFalse);
    });
  });
}
