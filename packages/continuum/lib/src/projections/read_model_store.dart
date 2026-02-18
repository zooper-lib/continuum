/// Abstraction for read model storage.
///
/// Implementations persist the projected read models produced by
/// projections. The store is parameterized by read model type
/// and key type.
abstract interface class ReadModelStore<TReadModel, TKey> {
  /// Loads a read model by its key.
  ///
  /// Returns null if no read model exists for the key.
  Future<TReadModel?> loadAsync(TKey key);

  /// Saves a read model under the given key.
  Future<void> saveAsync(TKey key, TReadModel readModel);

  /// Deletes the read model under the given key.
  Future<void> deleteAsync(TKey key);
}

/// In-memory implementation of [ReadModelStore] for testing.
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
