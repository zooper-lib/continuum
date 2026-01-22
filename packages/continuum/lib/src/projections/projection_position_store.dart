import 'projection_position.dart';

/// Abstraction for tracking async projection processing positions.
///
/// Each async projection tracks the global sequence number of the last
/// event it successfully processed along with the schema hash. This enables
/// resumption after restarts, ensures no events are missed or processed twice,
/// and detects schema changes that require rebuilding.
abstract interface class ProjectionPositionStore {
  /// Loads the position for a projection.
  ///
  /// Returns the [ProjectionPosition] containing the last processed sequence
  /// and schema hash, or `null` if the projection has never been tracked.
  Future<ProjectionPosition?> loadPositionAsync(String projectionName);

  /// Saves the current position for a projection.
  ///
  /// Should be called after successfully processing an event to record
  /// progress. The [position] contains the global sequence number and
  /// the current schema hash.
  Future<void> savePositionAsync(String projectionName, ProjectionPosition position);

  /// Resets the position for a projection, clearing all tracking data.
  ///
  /// Called when the projection schema changes and needs a full rebuild.
  Future<void> resetPositionAsync(String projectionName);
}

/// In-memory implementation of [ProjectionPositionStore] for testing.
///
/// Stores positions in a simple map. Data is lost when the store
/// instance is garbage collected.
final class InMemoryProjectionPositionStore implements ProjectionPositionStore {
  /// Internal storage map.
  final Map<String, ProjectionPosition> _positions = {};

  @override
  Future<ProjectionPosition?> loadPositionAsync(String projectionName) async {
    return _positions[projectionName];
  }

  @override
  Future<void> savePositionAsync(String projectionName, ProjectionPosition position) async {
    _positions[projectionName] = position;
  }

  @override
  Future<void> resetPositionAsync(String projectionName) async {
    _positions.remove(projectionName);
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
