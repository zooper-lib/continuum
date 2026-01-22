/// Abstraction for persisting projection read models.
///
/// Implementations provide the storage mechanism for read models,
/// whether in-memory, file-based, or database-backed.
///
/// The type parameters define:
/// - [TReadModel]: The read model type being stored
/// - [TKey]: The key type used to identify read model instances
abstract interface class ReadModelStore<TReadModel, TKey> {
  /// Loads a read model by its key.
  ///
  /// Returns the read model if found, or `null` if no read model exists
  /// for the given key.
  Future<TReadModel?> loadAsync(TKey key);

  /// Saves a read model for the given key.
  ///
  /// If a read model already exists for the key, it is replaced.
  Future<void> saveAsync(TKey key, TReadModel readModel);

  /// Deletes the read model for the given key.
  ///
  /// If no read model exists for the key, this is a no-op.
  Future<void> deleteAsync(TKey key);
}

/// In-memory implementation of [ReadModelStore] for testing.
///
/// Stores read models in a simple map. Data is lost when the
/// store instance is garbage collected.
final class InMemoryReadModelStore<TReadModel, TKey> implements ReadModelStore<TReadModel, TKey> {
  /// Internal storage map.
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

  /// Returns the number of stored read models.
  ///
  /// Useful for testing to verify storage state.
  int get length => _storage.length;

  /// Clears all stored read models.
  ///
  /// Useful for testing to reset state between tests.
  void clear() => _storage.clear();
}
