import 'package:continuum/continuum.dart';

/// In-memory implementation of [ReadModelStore].
///
/// Stores read models in a plain [Map], suitable for testing and
/// development. Data is lost when the instance is garbage collected.
final class InMemoryReadModelStore<TReadModel, TKey> implements ReadModelStore<TReadModel, TKey> {
  /// Internal storage of read models.
  final Map<TKey, TReadModel> _storage = {};

  @override
  Future<TReadModel?> loadAsync(TKey key) async {
    return _storage[key];
  }

  @override
  Future<void> saveAsync(TKey key, TReadModel readModel) async {
    _storage[key] = readModel;
  }

  @override
  Future<void> deleteAsync(TKey key) async {
    _storage.remove(key);
  }

  /// The number of stored read models.
  int get length => _storage.length;

  /// Clears all stored read models.
  void clear() => _storage.clear();
}
