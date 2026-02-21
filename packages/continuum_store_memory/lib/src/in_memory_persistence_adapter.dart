import 'package:continuum/continuum.dart';
import 'package:continuum_state/continuum_state.dart';

/// In-memory implementation of [TargetPersistenceAdapter].
///
/// Stores targets as JSON maps in a plain [Map], suitable for
/// testing and development. Data is lost when the instance is
/// garbage collected.
///
/// The caller provides [toJson] and [fromJson] callbacks for
/// target serialization. The [toJson] callback converts the
/// target to a JSON-compatible map, and [fromJson] reconstructs
/// it from the stored map.
final class InMemoryPersistenceAdapter<TAggregate> implements TargetPersistenceAdapter<TAggregate> {
  /// Internal storage keyed by stream ID value.
  final Map<String, Map<String, Object?>> _storage = {};

  /// Serializes a target to a JSON-compatible map.
  final Map<String, Object?> Function(TAggregate target) _toJson;

  /// Deserializes a target from a JSON-compatible map.
  final TAggregate Function(Map<String, Object?> json) _fromJson;

  /// Creates an in-memory persistence adapter.
  ///
  /// The [toJson] callback converts the target to a JSON map for
  /// storage. The [fromJson] callback reconstructs the target from
  /// the stored JSON map. Both callbacks are responsible for mapping
  /// all mutable state — not just the creation fields.
  InMemoryPersistenceAdapter({
    required Map<String, Object?> Function(TAggregate target) toJson,
    required TAggregate Function(Map<String, Object?> json) fromJson,
  }) : _toJson = toJson,
       _fromJson = fromJson;

  @override
  Future<TAggregate> fetchAsync(StreamId streamId) async {
    final json = _storage[streamId.value];
    if (json == null) {
      throw StateError(
        'Target not found in in-memory store: ${streamId.value}',
      );
    }

    // Reconstruct the target from the stored JSON map.
    return _fromJson(json);
  }

  @override
  Future<void> persistAsync(
    StreamId streamId,
    TAggregate target,
    List<Operation> pendingOperations,
  ) async {
    // Store the full target state as a JSON map. The pending
    // operations are ignored — we always write the complete entity.
    _storage[streamId.value] = _toJson(target);
  }

  @override
  Future<void> deleteAsync(StreamId streamId) async {
    // Remove the target from in-memory storage. Idempotent — removing
    // a non-existent key is a no-op.
    _storage.remove(streamId.value);
  }

  /// The number of stored targets.
  int get length => _storage.length;

  /// Clears all stored targets.
  void clear() => _storage.clear();
}
