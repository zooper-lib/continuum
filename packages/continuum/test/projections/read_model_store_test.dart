import 'package:continuum/src/projections/read_model_store.dart';
import 'package:test/test.dart';

void main() {
  group('InMemoryReadModelStore', () {
    late InMemoryReadModelStore<_TestReadModel, String> store;

    setUp(() {
      store = InMemoryReadModelStore<_TestReadModel, String>();
    });

    test('loadAsync returns null for missing key', () async {
      final result = await store.loadAsync('non-existent');

      expect(result, isNull);
    });

    test('saveAsync stores read model', () async {
      final model = _TestReadModel(id: 'test-1', value: 42);

      await store.saveAsync('test-1', model);
      final loaded = await store.loadAsync('test-1');

      expect(loaded, isNotNull);
      expect(loaded!.id, equals('test-1'));
      expect(loaded.value, equals(42));
    });

    test('saveAsync overwrites existing read model', () async {
      final model1 = _TestReadModel(id: 'test-1', value: 10);
      final model2 = _TestReadModel(id: 'test-1', value: 20);

      await store.saveAsync('test-1', model1);
      await store.saveAsync('test-1', model2);
      final loaded = await store.loadAsync('test-1');

      expect(loaded!.value, equals(20));
    });

    test('deleteAsync removes read model', () async {
      final model = _TestReadModel(id: 'test-1', value: 42);
      await store.saveAsync('test-1', model);

      await store.deleteAsync('test-1');
      final loaded = await store.loadAsync('test-1');

      expect(loaded, isNull);
    });

    test('deleteAsync is no-op for missing key', () async {
      // Should not throw
      await store.deleteAsync('non-existent');

      expect(store.length, equals(0));
    });

    test('length returns number of stored models', () async {
      expect(store.length, equals(0));

      await store.saveAsync('a', _TestReadModel(id: 'a', value: 1));
      expect(store.length, equals(1));

      await store.saveAsync('b', _TestReadModel(id: 'b', value: 2));
      expect(store.length, equals(2));

      await store.deleteAsync('a');
      expect(store.length, equals(1));
    });

    test('clear removes all stored models', () async {
      await store.saveAsync('a', _TestReadModel(id: 'a', value: 1));
      await store.saveAsync('b', _TestReadModel(id: 'b', value: 2));

      store.clear();

      expect(store.length, equals(0));
      expect(await store.loadAsync('a'), isNull);
      expect(await store.loadAsync('b'), isNull);
    });

    test('stores different keys independently', () async {
      final modelA = _TestReadModel(id: 'a', value: 100);
      final modelB = _TestReadModel(id: 'b', value: 200);

      await store.saveAsync('a', modelA);
      await store.saveAsync('b', modelB);

      final loadedA = await store.loadAsync('a');
      final loadedB = await store.loadAsync('b');

      expect(loadedA!.value, equals(100));
      expect(loadedB!.value, equals(200));
    });
  });

  group('InMemoryReadModelStore with complex keys', () {
    test('works with StreamId-like value objects', () async {
      final store = InMemoryReadModelStore<int, _StreamIdLike>();
      final key1 = _StreamIdLike('stream-1');
      final key2 = _StreamIdLike('stream-2');

      await store.saveAsync(key1, 42);
      await store.saveAsync(key2, 99);

      expect(await store.loadAsync(key1), equals(42));
      expect(await store.loadAsync(key2), equals(99));
    });
  });
}

// --- Test Fixtures ---

/// Simple read model for testing.
class _TestReadModel {
  final String id;
  final int value;

  _TestReadModel({required this.id, required this.value});
}

/// Value object to test as map key (must implement == and hashCode).
class _StreamIdLike {
  final String value;

  _StreamIdLike(this.value);

  @override
  bool operator ==(Object other) => identical(this, other) || other is _StreamIdLike && runtimeType == other.runtimeType && value == other.value;

  @override
  int get hashCode => value.hashCode;
}
