import 'dart:convert';

import 'package:continuum/continuum.dart';
import 'package:hive/hive.dart';

/// Hive-backed implementation of [ReadModelStore].
///
/// Stores read models as JSON strings in a Hive [Box].
/// Read models survive app restarts and device reboots.
///
/// The caller provides [toJson] and [fromJson] callbacks for
/// read model serialization, and a [keyToString] callback to
/// convert the generic key type to a Hive-compatible string key.
final class HiveReadModelStore<TReadModel, TKey> implements ReadModelStore<TReadModel, TKey> {
  /// The Hive box storing JSON-encoded read models.
  final Box<String> _box;

  /// Serializes a read model to a JSON-compatible map.
  final Map<String, Object?> Function(TReadModel readModel) _toJson;

  /// Deserializes a read model from a JSON-compatible map.
  final TReadModel Function(Map<String, Object?> json) _fromJson;

  /// Converts a key to a string suitable for Hive box lookups.
  final String Function(TKey key) _keyToString;

  /// Private constructor — use [openAsync] factory.
  HiveReadModelStore._({
    required Box<String> box,
    required Map<String, Object?> Function(TReadModel readModel) toJson,
    required TReadModel Function(Map<String, Object?> json) fromJson,
    required String Function(TKey key) keyToString,
  }) : _box = box,
       _toJson = toJson,
       _fromJson = fromJson,
       _keyToString = keyToString;

  /// Opens a Hive-backed read model store with the given [boxName].
  ///
  /// If the box already exists, it is reopened with existing data.
  ///
  /// The [toJson] and [fromJson] callbacks handle read model serialization.
  /// The [keyToString] callback converts the generic key type to a string
  /// for use as Hive box keys.
  static Future<HiveReadModelStore<TReadModel, TKey>> openAsync<TReadModel, TKey>({
    required String boxName,
    required Map<String, Object?> Function(TReadModel readModel) toJson,
    required TReadModel Function(Map<String, Object?> json) fromJson,
    required String Function(TKey key) keyToString,
  }) async {
    final box = await Hive.openBox<String>(boxName);
    return HiveReadModelStore._(
      box: box,
      toJson: toJson,
      fromJson: fromJson,
      keyToString: keyToString,
    );
  }

  @override
  Future<TReadModel?> loadAsync(TKey key) async {
    final stringKey = _keyToString(key);
    final json = _box.get(stringKey);

    if (json == null) return null;

    // Decode the stored JSON string back into a read model.
    final decoded = jsonDecode(json) as Map<String, Object?>;
    return _fromJson(decoded);
  }

  @override
  Future<void> saveAsync(TKey key, TReadModel readModel) async {
    final stringKey = _keyToString(key);
    final json = jsonEncode(_toJson(readModel));
    await _box.put(stringKey, json);
  }

  @override
  Future<void> deleteAsync(TKey key) async {
    final stringKey = _keyToString(key);
    await _box.delete(stringKey);
  }

  /// Closes the underlying Hive box.
  ///
  /// Call this when the store is no longer needed to release resources.
  Future<void> closeAsync() async {
    await _box.close();
  }

  /// The number of stored read models.
  int get length => _box.length;
}
