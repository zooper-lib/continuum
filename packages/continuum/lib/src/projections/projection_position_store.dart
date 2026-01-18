/// Abstraction for tracking async projection processing positions.
///
/// Each async projection tracks the global sequence number of the last
/// event it successfully processed. This enables resumption after restarts
/// and ensures no events are missed or processed twice.
abstract interface class ProjectionPositionStore {
  /// Loads the last processed position for a projection.
  ///
  /// Returns the global sequence number of the last successfully processed
  /// event, or `null` if the projection has never processed any events
  /// (indicating it should start from the beginning).
  Future<int?> loadPositionAsync(String projectionName);

  /// Saves the current position for a projection.
  ///
  /// Should be called after successfully processing an event to record
  /// progress. The position is the global sequence number of the
  /// processed event.
  Future<void> savePositionAsync(String projectionName, int position);
}

/// In-memory implementation of [ProjectionPositionStore] for testing.
///
/// Stores positions in a simple map. Data is lost when the store
/// instance is garbage collected.
final class InMemoryProjectionPositionStore implements ProjectionPositionStore {
  /// Internal storage map.
  final Map<String, int> _positions = {};

  @override
  Future<int?> loadPositionAsync(String projectionName) async {
    return _positions[projectionName];
  }

  @override
  Future<void> savePositionAsync(String projectionName, int position) async {
    _positions[projectionName] = position;
  }

  /// Returns the number of tracked projections.
  ///
  /// Useful for testing to verify storage state.
  int get length => _positions.length;

  /// Clears all stored positions.
  ///
  /// Useful for testing to reset state between tests.
  void clear() => _positions.clear();

  /// Removes the position for a specific projection.
  ///
  /// Useful for testing projection rebuild scenarios.
  void remove(String projectionName) => _positions.remove(projectionName);
}
