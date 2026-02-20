import 'dart:convert';

import 'package:continuum/continuum.dart';
import 'package:continuum_state/continuum_state.dart';
import 'package:hive/hive.dart';

/// Hive-backed implementation of [TargetPersistenceAdapter].
///
/// Stores targets as JSON strings in a Hive [Box].
/// Targets survive app restarts and device reboots.
///
/// The caller provides [toJson] and [fromJson] callbacks for
/// target serialization. The adapter stores the full entity
/// state on every persist — pending operations are ignored.
final class HivePersistenceAdapter<TAggregate> implements TargetPersistenceAdapter<TAggregate> {
  /// The Hive box storing JSON-encoded targets.
  final Box<String> _box;

  /// Serializes a target to a JSON-compatible map.
  final Map<String, Object?> Function(TAggregate target) _toJson;

  /// Deserializes a target from a JSON-compatible map.
  final TAggregate Function(Map<String, Object?> json) _fromJson;

  /// Private constructor — use [openAsync] factory.
  HivePersistenceAdapter._({
    required Box<String> box,
    required Map<String, Object?> Function(TAggregate aggregate) toJson,
    required TAggregate Function(Map<String, Object?> json) fromJson,
  }) : _box = box,
       _toJson = toJson,
       _fromJson = fromJson;

  /// Opens a Hive-backed persistence adapter with the given [boxName].
  ///
  /// If the box already exists, it is reopened with existing data.
  ///
  /// The [toJson] and [fromJson] callbacks handle target
  /// serialization. Both callbacks are responsible for mapping all
  /// mutable state — not just the creation fields.
  static Future<HivePersistenceAdapter<TAggregate>> openAsync<TAggregate>({
    required String boxName,
    required Map<String, Object?> Function(TAggregate aggregate) toJson,
    required TAggregate Function(Map<String, Object?> json) fromJson,
  }) async {
    final box = await Hive.openBox<String>(boxName);
    return HivePersistenceAdapter._(
      box: box,
      toJson: toJson,
      fromJson: fromJson,
    );
  }

  @override
  Future<TAggregate> fetchAsync(StreamId streamId) async {
    final json = _box.get(streamId.value);
    if (json == null) {
      throw StateError(
        'Target not found in Hive store: ${streamId.value}',
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
    await _box.put(streamId.value, json);
  }

  /// Closes the underlying Hive box.
  ///
  /// Call this when the adapter is no longer needed to release resources.
  Future<void> closeAsync() async {
    await _box.close();
  }

  /// The number of stored targets.
  int get length => _box.length;
}
