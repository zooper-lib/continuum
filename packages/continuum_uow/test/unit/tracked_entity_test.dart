import 'package:continuum/continuum.dart';
import 'package:continuum_uow/continuum_uow.dart';
import 'package:test/test.dart';

/// A plain operation for testing that the UoW layer works with
/// non-ContinuumEvent types.
final class _TestOperation implements Operation {
  final String action;

  const _TestOperation(this.action);
}

void main() {
  group('TrackedEntity', () {
    test('should store all fields correctly', () {
      // Arrange
      const entity = 'test-aggregate';
      const entityType = String;
      const loadedVersion = 5;
      final operations = <Operation>[const _TestOperation('action-1')];

      // Act
      final tracked = TrackedEntity(
        entity: entity,
        entityType: entityType,
        loadedVersion: loadedVersion,
        pendingOperations: operations,
      );

      // Assert — all fields should be accessible and correct
      expect(tracked.entity, equals(entity));
      expect(tracked.entityType, equals(entityType));
      expect(tracked.loadedVersion, equals(loadedVersion));
      expect(tracked.pendingOperations, equals(operations));
    });

    test('should default pendingOperations to empty list', () {
      // Arrange & Act
      final tracked = TrackedEntity(
        entity: 'aggregate',
        entityType: String,
        loadedVersion: 0,
      );

      // Assert — pendingOperations should be an empty list, not null
      expect(tracked.pendingOperations, isEmpty);
    });

    test('should accumulate operations in the pendingOperations list', () {
      // Arrange
      final tracked = TrackedEntity(
        entity: 'aggregate',
        entityType: String,
        loadedVersion: 0,
      );

      // Act — add operations to the mutable list
      tracked.pendingOperations.add(const _TestOperation('op-1'));
      tracked.pendingOperations.add(const _TestOperation('op-2'));

      // Assert — operations should accumulate in order
      expect(tracked.pendingOperations, hasLength(2));
      expect(
        (tracked.pendingOperations[0] as _TestOperation).action,
        equals('op-1'),
      );
      expect(
        (tracked.pendingOperations[1] as _TestOperation).action,
        equals('op-2'),
      );
    });

    test('withClearedPendingOperations should return copy with empty operations', () {
      // Arrange
      final operations = <Operation>[
        const _TestOperation('op-1'),
        const _TestOperation('op-2'),
      ];
      final tracked = TrackedEntity(
        entity: 'aggregate',
        entityType: String,
        loadedVersion: 3,
        pendingOperations: operations,
      );

      // Act
      final cleared = tracked.withClearedPendingOperations();

      // Assert — cleared copy has empty operations but same identity fields
      expect(cleared.entity, equals('aggregate'));
      expect(cleared.entityType, equals(String));
      expect(cleared.loadedVersion, equals(3));
      expect(cleared.pendingOperations, isEmpty);
    });

    test('withClearedPendingOperations should not mutate original', () {
      // Arrange
      final operations = <Operation>[const _TestOperation('op-1')];
      final tracked = TrackedEntity(
        entity: 'aggregate',
        entityType: String,
        loadedVersion: 1,
        pendingOperations: operations,
      );

      // Act
      tracked.withClearedPendingOperations();

      // Assert — original should still have its operations
      expect(tracked.pendingOperations, hasLength(1));
    });

    test('should track new entity with loadedVersion -1', () {
      // Arrange & Act
      final tracked = TrackedEntity(
        entity: 'new-aggregate',
        entityType: String,
        loadedVersion: -1,
      );

      // Assert — loadedVersion of -1 indicates a new entity
      expect(tracked.loadedVersion, equals(-1));
    });
  });
}
