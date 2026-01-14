import 'package:continuum_lints/src/continuum_missing_creation_factories_rule.dart';
import 'package:test/test.dart';

void main() {
  group('ContinuumMissingCreationFactoriesRule', () {
    test('exposes stable lint code name', () {
      // Arrange
      const ContinuumMissingCreationFactoriesRule rule = ContinuumMissingCreationFactoriesRule();

      // Act
      final String name = rule.code.name;

      // Assert
      expect(name, 'continuum_missing_creation_factories');
    });
  });
}
