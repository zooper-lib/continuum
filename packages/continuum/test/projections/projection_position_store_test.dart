import 'package:continuum/src/projections/projection_position.dart';
import 'package:continuum/src/projections/projection_position_store.dart';
import 'package:test/test.dart';

void main() {
  group('InMemoryProjectionPositionStore', () {
    late InMemoryProjectionPositionStore store;

    setUp(() {
      store = InMemoryProjectionPositionStore();
    });

    test('loadPositionAsync returns null for new projection', () async {
      final position = await store.loadPositionAsync('new-projection');

      expect(position, isNull);
    });

    test('savePositionAsync stores position', () async {
      await store.savePositionAsync(
        'projection-1',
        const ProjectionPosition(lastProcessedSequence: 42, schemaHash: 'abc'),
      );

      final position = await store.loadPositionAsync('projection-1');

      expect(position?.lastProcessedSequence, equals(42));
      expect(position?.schemaHash, equals('abc'));
    });

    test('savePositionAsync overwrites existing position', () async {
      await store.savePositionAsync(
        'projection-1',
        const ProjectionPosition(lastProcessedSequence: 10, schemaHash: 'v1'),
      );
      await store.savePositionAsync(
        'projection-1',
        const ProjectionPosition(lastProcessedSequence: 50, schemaHash: 'v2'),
      );

      final position = await store.loadPositionAsync('projection-1');

      expect(position?.lastProcessedSequence, equals(50));
      expect(position?.schemaHash, equals('v2'));
    });

    test('stores positions for multiple projections independently', () async {
      await store.savePositionAsync(
        'projection-a',
        const ProjectionPosition(lastProcessedSequence: 100, schemaHash: 'a'),
      );
      await store.savePositionAsync(
        'projection-b',
        const ProjectionPosition(lastProcessedSequence: 200, schemaHash: 'b'),
      );
      await store.savePositionAsync(
        'projection-c',
        const ProjectionPosition(lastProcessedSequence: 300, schemaHash: 'c'),
      );

      final posA = await store.loadPositionAsync('projection-a');
      final posB = await store.loadPositionAsync('projection-b');
      final posC = await store.loadPositionAsync('projection-c');

      expect(posA?.lastProcessedSequence, equals(100));
      expect(posB?.lastProcessedSequence, equals(200));
      expect(posC?.lastProcessedSequence, equals(300));
    });

    test('length returns number of tracked projections', () async {
      expect(store.length, equals(0));

      await store.savePositionAsync(
        'p1',
        const ProjectionPosition(lastProcessedSequence: 1, schemaHash: 'h1'),
      );
      expect(store.length, equals(1));

      await store.savePositionAsync(
        'p2',
        const ProjectionPosition(lastProcessedSequence: 2, schemaHash: 'h2'),
      );
      expect(store.length, equals(2));

      // Overwrite doesn't increase length
      await store.savePositionAsync(
        'p1',
        const ProjectionPosition(lastProcessedSequence: 10, schemaHash: 'h1'),
      );
      expect(store.length, equals(2));
    });

    test('clear removes all positions', () async {
      await store.savePositionAsync(
        'p1',
        const ProjectionPosition(lastProcessedSequence: 1, schemaHash: 'h'),
      );
      await store.savePositionAsync(
        'p2',
        const ProjectionPosition(lastProcessedSequence: 2, schemaHash: 'h'),
      );

      store.clear();

      expect(store.length, equals(0));
      expect(await store.loadPositionAsync('p1'), isNull);
      expect(await store.loadPositionAsync('p2'), isNull);
    });

    test('remove removes specific projection position', () async {
      await store.savePositionAsync(
        'p1',
        const ProjectionPosition(lastProcessedSequence: 1, schemaHash: 'h'),
      );
      await store.savePositionAsync(
        'p2',
        const ProjectionPosition(lastProcessedSequence: 2, schemaHash: 'h'),
      );

      store.remove('p1');

      expect(await store.loadPositionAsync('p1'), isNull);
      expect((await store.loadPositionAsync('p2'))?.lastProcessedSequence, equals(2));
      expect(store.length, equals(1));
    });

    test('handles position value of zero', () async {
      await store.savePositionAsync(
        'projection-1',
        const ProjectionPosition(lastProcessedSequence: 0, schemaHash: 'h'),
      );

      final position = await store.loadPositionAsync('projection-1');

      expect(position?.lastProcessedSequence, equals(0));
    });

    test('handles large position values', () async {
      const largePosition = 9223372036854775807; // Max int64
      await store.savePositionAsync(
        'projection-1',
        const ProjectionPosition(lastProcessedSequence: largePosition, schemaHash: 'h'),
      );

      final position = await store.loadPositionAsync('projection-1');

      expect(position?.lastProcessedSequence, equals(largePosition));
    });

    test('resetPositionAsync removes projection position', () async {
      await store.savePositionAsync(
        'projection-1',
        const ProjectionPosition(lastProcessedSequence: 42, schemaHash: 'h'),
      );

      await store.resetPositionAsync('projection-1');

      expect(await store.loadPositionAsync('projection-1'), isNull);
    });

    test('schema hash tracking works correctly', () async {
      await store.savePositionAsync(
        'projection-1',
        const ProjectionPosition(lastProcessedSequence: 10, schemaHash: 'schema-v1'),
      );

      final position = await store.loadPositionAsync('projection-1');

      expect(position?.schemaHash, equals('schema-v1'));
      expect(position?.hasSchemaChangedFrom('schema-v1'), isFalse);
      expect(position?.hasSchemaChangedFrom('schema-v2'), isTrue);
    });
  });
}
