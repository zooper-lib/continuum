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
