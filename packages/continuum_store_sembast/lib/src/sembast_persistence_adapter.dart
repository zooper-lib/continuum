import 'dart:convert';

import 'package:continuum/continuum.dart';
import 'package:continuum_state/continuum_state.dart';
import 'package:sembast/sembast.dart';

/// Sembast-backed implementation of [TargetPersistenceAdapter].
///
/// Stores targets as JSON strings in a Sembast [StoreRef].
/// Targets survive app restarts and device reboots.
///
/// The caller provides [toJson] and [fromJson] callbacks for
/// target serialization. The adapter stores the full entity
/// state on every persist — pending operations are ignored.
final class SembastPersistenceAdapter<TAggregate> implements TargetPersistenceAdapter<TAggregate> {
  /// The Sembast database instance.
  final Database _database;

  /// The Sembast store for JSON-encoded targets, keyed by string.
  final StoreRef<String, String> _store;

  /// Serializes a target to a JSON-compatible map.
  final Map<String, Object?> Function(TAggregate target) _toJson;

  /// Deserializes a target from a JSON-compatible map.
  final TAggregate Function(Map<String, Object?> json) _fromJson;

  /// Creates a Sembast-backed persistence adapter.
  ///
  /// The [database] must already be opened by the caller. The
  /// [storeName] identifies the Sembast store within the database —
  /// use a unique name per target type to prevent collisions.
  ///
  /// The [toJson] and [fromJson] callbacks handle target
  /// serialization. Both callbacks are responsible for mapping all
  /// mutable state — not just the creation fields.
  SembastPersistenceAdapter({
    required Database database,
    required String storeName,
    required Map<String, Object?> Function(TAggregate aggregate) toJson,
    required TAggregate Function(Map<String, Object?> json) fromJson,
  }) : _database = database,
       _store = StoreRef<String, String>(storeName),
       _toJson = toJson,
       _fromJson = fromJson;

  @override
  Future<TAggregate> fetchAsync(StreamId streamId) async {
    final json = await _store.record(streamId.value).get(_database);
    if (json == null) {
      throw StateError(
        'Target not found in Sembast store: ${streamId.value}',
      );
    }

    // Decode the stored JSON string back into a target.
    final decoded = jsonDecode(json) as Map<String, Object?>;
    return _fromJson(decoded);
  }

  @override
  Future<void> persistAsync(
    StreamId streamId,
    TAggregate target,
    List<Operation> pendingOperations,
  ) async {
    // Encode the full target state to a JSON string and store it.
    // Pending operations are ignored — we always write the complete
    // entity.
    final json = jsonEncode(_toJson(target));
    await _store.record(streamId.value).put(_database, json);
  }

  @override
  Future<void> deleteAsync(StreamId streamId) async {
    // Remove the target from the Sembast store. Idempotent — deleting
    // a non-existent record is a no-op in Sembast.
    await _store.record(streamId.value).delete(_database);
  }

  /// Returns the number of stored targets.
  Future<int> countAsync() async {
    return _store.count(_database);
  }
}
