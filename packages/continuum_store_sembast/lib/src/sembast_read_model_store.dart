import 'dart:convert';

import 'package:continuum/continuum.dart';
import 'package:sembast/sembast.dart';

/// Sembast-backed implementation of [ReadModelStore].
///
/// Stores read models as JSON strings in a Sembast [StoreRef].
/// Read models survive app restarts and device reboots.
///
/// The caller provides [toJson] and [fromJson] callbacks for
/// read model serialization, and a [keyToString] callback to
/// convert the generic key type to a Sembast-compatible string key.
final class SembastReadModelStore<TReadModel, TKey> implements ReadModelStore<TReadModel, TKey> {
  /// The Sembast database instance.
  final Database _database;

  /// The Sembast store for JSON-encoded read models, keyed by string.
  final StoreRef<String, String> _store;

  /// Serializes a read model to a JSON-compatible map.
  final Map<String, Object?> Function(TReadModel readModel) _toJson;

  /// Deserializes a read model from a JSON-compatible map.
  final TReadModel Function(Map<String, Object?> json) _fromJson;

  /// Converts a key to a string suitable for Sembast record lookups.
  final String Function(TKey key) _keyToString;

  /// Creates a Sembast-backed read model store.
  ///
  /// The [database] must already be opened by the caller. The [storeName]
  /// identifies the Sembast store within the database — use a unique name
  /// per read model type to prevent collisions.
  ///
  /// The [toJson] and [fromJson] callbacks handle read model serialization.
  /// The [keyToString] callback converts the generic key type to a string
  /// for use as Sembast record keys.
  SembastReadModelStore({
    required Database database,
    required String storeName,
    required Map<String, Object?> Function(TReadModel readModel) toJson,
    required TReadModel Function(Map<String, Object?> json) fromJson,
    required String Function(TKey key) keyToString,
  }) : _database = database,
       _store = StoreRef<String, String>(storeName),
       _toJson = toJson,
       _fromJson = fromJson,
       _keyToString = keyToString;

  @override
  Future<TReadModel?> loadAsync(TKey key) async {
    final stringKey = _keyToString(key);
    final json = await _store.record(stringKey).get(_database);

    if (json == null) return null;

    // Decode the stored JSON string back into a read model.
    final decoded = jsonDecode(json) as Map<String, Object?>;
    return _fromJson(decoded);
  }

  @override
  Future<void> saveAsync(TKey key, TReadModel readModel) async {
    final stringKey = _keyToString(key);
    final json = jsonEncode(_toJson(readModel));
    await _store.record(stringKey).put(_database, json);
  }

  @override
  Future<void> deleteAsync(TKey key) async {
    final stringKey = _keyToString(key);
    await _store.record(stringKey).delete(_database);
  }

  /// Returns the number of stored read models.
  Future<int> countAsync() async {
    return _store.count(_database);
  }
}
