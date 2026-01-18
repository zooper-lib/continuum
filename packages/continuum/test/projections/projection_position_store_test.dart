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
      await store.savePositionAsync('projection-1', 42);

      final position = await store.loadPositionAsync('projection-1');

      expect(position, equals(42));
    });

    test('savePositionAsync overwrites existing position', () async {
      await store.savePositionAsync('projection-1', 10);
      await store.savePositionAsync('projection-1', 50);

      final position = await store.loadPositionAsync('projection-1');

      expect(position, equals(50));
    });

    test('stores positions for multiple projections independently', () async {
      await store.savePositionAsync('projection-a', 100);
      await store.savePositionAsync('projection-b', 200);
      await store.savePositionAsync('projection-c', 300);

      expect(await store.loadPositionAsync('projection-a'), equals(100));
      expect(await store.loadPositionAsync('projection-b'), equals(200));
      expect(await store.loadPositionAsync('projection-c'), equals(300));
    });

    test('length returns number of tracked projections', () async {
      expect(store.length, equals(0));

      await store.savePositionAsync('p1', 1);
      expect(store.length, equals(1));

      await store.savePositionAsync('p2', 2);
      expect(store.length, equals(2));

      // Overwrite doesn't increase length
      await store.savePositionAsync('p1', 10);
      expect(store.length, equals(2));
    });

    test('clear removes all positions', () async {
      await store.savePositionAsync('p1', 1);
      await store.savePositionAsync('p2', 2);

      store.clear();

      expect(store.length, equals(0));
      expect(await store.loadPositionAsync('p1'), isNull);
      expect(await store.loadPositionAsync('p2'), isNull);
    });

    test('remove removes specific projection position', () async {
      await store.savePositionAsync('p1', 1);
      await store.savePositionAsync('p2', 2);

      store.remove('p1');

      expect(await store.loadPositionAsync('p1'), isNull);
      expect(await store.loadPositionAsync('p2'), equals(2));
      expect(store.length, equals(1));
    });

    test('handles position value of zero', () async {
      await store.savePositionAsync('projection-1', 0);

      final position = await store.loadPositionAsync('projection-1');

      expect(position, equals(0));
    });

    test('handles large position values', () async {
      const largePosition = 9223372036854775807; // Max int64
      await store.savePositionAsync('projection-1', largePosition);

      final position = await store.loadPositionAsync('projection-1');

      expect(position, equals(largePosition));
    });
  });
}
