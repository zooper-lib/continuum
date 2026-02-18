import 'projection_position.dart';

/// Abstraction for persisting async projection positions.
///
/// Implementations store where each projection last stopped processing,
/// enabling resumption after application restarts.
abstract interface class ProjectionPositionStore {
  /// Loads the current position for the named projection.
  Future<ProjectionPosition?> loadPositionAsync(String projectionName);

  /// Saves the position for the named projection.
  Future<void> savePositionAsync(String projectionName, ProjectionPosition position);

  /// Resets the position for the named projection, triggering a full replay.
  Future<void> resetPositionAsync(String projectionName);
}

/// In-memory implementation of [ProjectionPositionStore] for testing.
final class InMemoryProjectionPositionStore implements ProjectionPositionStore {
  /// Internal storage of projection positions.
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

  /// The number of stored positions.
  int get length => _positions.length;

  /// Clears all stored positions.
  void clear() => _positions.clear();

  /// Removes the position for a specific projection.
  void remove(String projectionName) => _positions.remove(projectionName);
}
