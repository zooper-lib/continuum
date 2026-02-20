import 'package:continuum/continuum.dart';
import 'package:continuum_state/continuum_state.dart';

/// In-memory implementation of [AggregatePersistenceAdapter].
///
/// Stores aggregates as JSON maps in a plain [Map], suitable for
/// testing and development. Data is lost when the instance is
/// garbage collected.
///
/// The caller provides [toJson] and [fromJson] callbacks for
/// aggregate serialization. The [toJson] callback converts the
/// aggregate to a JSON-compatible map, and [fromJson] reconstructs
/// it from the stored map.
final class InMemoryPersistenceAdapter<TAggregate> implements AggregatePersistenceAdapter<TAggregate> {
  /// Internal storage keyed by stream ID value.
  final Map<String, Map<String, Object?>> _storage = {};

  /// Serializes an aggregate to a JSON-compatible map.
  final Map<String, Object?> Function(TAggregate aggregate) _toJson;

  /// Deserializes an aggregate from a JSON-compatible map.
  final TAggregate Function(Map<String, Object?> json) _fromJson;

  /// Creates an in-memory persistence adapter.
  ///
  /// The [toJson] callback converts the aggregate to a JSON map for
  /// storage. The [fromJson] callback reconstructs the aggregate from
  /// the stored JSON map. Both callbacks are responsible for mapping
  /// all mutable aggregate state — not just the creation fields.
  InMemoryPersistenceAdapter({
    required Map<String, Object?> Function(TAggregate aggregate) toJson,
    required TAggregate Function(Map<String, Object?> json) fromJson,
  }) : _toJson = toJson,
       _fromJson = fromJson;

  @override
  Future<TAggregate> fetchAsync(StreamId streamId) async {
    final json = _storage[streamId.value];
    if (json == null) {
      throw StateError(
        'Aggregate not found in in-memory store: ${streamId.value}',
      );
    }

    // Reconstruct the aggregate from the stored JSON map.
    return _fromJson(json);
  }

  @override
  Future<void> persistAsync(
    StreamId streamId,
    TAggregate aggregate,
    List<Operation> pendingOperations,
  ) async {
    // Store the full aggregate state as a JSON map. The pending
    // operations are ignored — we always write the complete entity.
    _storage[streamId.value] = _toJson(aggregate);
  }

  /// The number of stored aggregates.
  int get length => _storage.length;

  /// Clears all stored aggregates.
  void clear() => _storage.clear();
}
