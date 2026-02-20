import 'package:continuum/continuum.dart';
import 'package:test/test.dart';

void main() {
  group('OperationTarget', () {
    test('should be const-constructible', () {
      // Arrange & Act
      const annotation = OperationTarget();

      // Assert
      expect(annotation, isA<OperationTarget>());
    });
  });
}
