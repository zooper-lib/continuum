import 'package:continuum_lints/continuum_lints.dart';
import 'package:continuum_lints/src/continuum_missing_apply_handlers_rule.dart';
import 'package:test/test.dart';

void main() {
  group('ContinuumMissingApplyHandlersRule', () {
    test('exposes stable lint code name', () {
      // Arrange
      const ContinuumMissingApplyHandlersRule rule = ContinuumMissingApplyHandlersRule();

      // Act
      final String name = rule.code.name;

      // Assert
      expect(name, 'continuum_missing_apply_handlers');
    });
  });

  group('continuum_lints plugin', () {
    test('creates a plugin that provides continuum lint rules', () {
      // Act
      final Object plugin = createPlugin();

      // Assert
      expect(plugin, isNotNull);
    });
  });
}
