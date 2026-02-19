import 'dart:io';

import 'package:continuum_store_sembast/continuum_store_sembast.dart';
import 'package:sembast/sembast_io.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late Database database;
  late SembastReadModelStore<_Profile, _ProfileId> store;

  setUp(() async {
    // Create a temporary directory for each test to isolate database files.
    tempDir = await Directory.systemTemp.createTemp('sembast_read_model_test_');
    final dbPath = '${tempDir.path}/test.db';
    database = await databaseFactoryIo.openDatabase(dbPath);
    store = SembastReadModelStore(
      database: database,
      storeName: 'profiles',
      toJson: (profile) => profile.toJson(),
      fromJson: _Profile.fromJson,
      keyToString: (key) => key.value,
    );
  });

  tearDown(() async {
    await database.close();
    // Clean up the temporary directory.
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('SembastReadModelStore', () {
    group('loadAsync', () {
      test('should return null for non-existent key', () async {
        // Arrange
        final key = const _ProfileId('non-existent');

        // Act
        final result = await store.loadAsync(key);

        // Assert — missing keys must return null, not throw.
        expect(result, isNull);
      });

      test('should return saved read model', () async {
        // Arrange
        final key = const _ProfileId('user-1');
        final profile = _Profile(name: 'Alice', email: 'alice@example.com');
        await store.saveAsync(key, profile);

        // Act
        final result = await store.loadAsync(key);

        // Assert — round-trip through JSON must preserve all fields.
        expect(result, isNotNull);
        expect(result!.name, equals('Alice'));
        expect(result.email, equals('alice@example.com'));
      });

      test('should return latest version after overwrite', () async {
        // Arrange
        final key = const _ProfileId('user-1');
        await store.saveAsync(key, _Profile(name: 'Alice', email: 'old@example.com'));
        await store.saveAsync(key, _Profile(name: 'Alice', email: 'new@example.com'));

        // Act
        final result = await store.loadAsync(key);

        // Assert — the second save must overwrite the first.
        expect(result!.email, equals('new@example.com'));
      });
    });

    group('saveAsync', () {
      test('should persist read model to new key', () async {
        // Arrange
        final key = const _ProfileId('user-1');
        final profile = _Profile(name: 'Bob', email: 'bob@example.com');

        // Act
        await store.saveAsync(key, profile);

        // Assert — count should reflect the stored entry.
        expect(await store.countAsync(), equals(1));
        final loaded = await store.loadAsync(key);
        expect(loaded!.name, equals('Bob'));
      });

      test('should handle multiple distinct keys', () async {
        // Arrange & Act
        await store.saveAsync(const _ProfileId('user-1'), _Profile(name: 'Alice', email: 'a@x.com'));
        await store.saveAsync(const _ProfileId('user-2'), _Profile(name: 'Bob', email: 'b@x.com'));

        // Assert — both entries should be independently retrievable.
        expect(await store.countAsync(), equals(2));
        expect((await store.loadAsync(const _ProfileId('user-1')))!.name, equals('Alice'));
        expect((await store.loadAsync(const _ProfileId('user-2')))!.name, equals('Bob'));
      });
    });

    group('deleteAsync', () {
      test('should remove existing read model', () async {
        // Arrange
        final key = const _ProfileId('user-1');
        await store.saveAsync(key, _Profile(name: 'Alice', email: 'a@x.com'));

        // Act
        await store.deleteAsync(key);

        // Assert — the key must no longer resolve.
        final result = await store.loadAsync(key);
        expect(result, isNull);
        expect(await store.countAsync(), equals(0));
      });

      test('should not throw when deleting non-existent key', () async {
        // Arrange
        final key = const _ProfileId('non-existent');

        // Act & Assert — deleting a missing key is a no-op.
        await expectLater(store.deleteAsync(key), completes);
      });

      test('should not affect other keys', () async {
        // Arrange
        await store.saveAsync(const _ProfileId('user-1'), _Profile(name: 'Alice', email: 'a@x.com'));
        await store.saveAsync(const _ProfileId('user-2'), _Profile(name: 'Bob', email: 'b@x.com'));

        // Act
        await store.deleteAsync(const _ProfileId('user-1'));

        // Assert — only the targeted key should be removed.
        expect(await store.loadAsync(const _ProfileId('user-1')), isNull);
        expect((await store.loadAsync(const _ProfileId('user-2')))!.name, equals('Bob'));
        expect(await store.countAsync(), equals(1));
      });
    });

    group('persistence', () {
      test('should survive close and reopen with same database', () async {
        // Arrange — save data and close the database.
        final key = const _ProfileId('user-1');
        await store.saveAsync(key, _Profile(name: 'Alice', email: 'a@x.com'));
        await database.close();

        // Act — reopen the database and create a new store instance.
        final dbPath = '${tempDir.path}/test.db';
        database = await databaseFactoryIo.openDatabase(dbPath);
        store = SembastReadModelStore(
          database: database,
          storeName: 'profiles',
          toJson: (profile) => profile.toJson(),
          fromJson: _Profile.fromJson,
          keyToString: (key) => key.value,
        );
        final result = await store.loadAsync(key);

        // Assert — data must survive the close/reopen cycle.
        expect(result, isNotNull);
        expect(result!.name, equals('Alice'));
      });
    });

    group('countAsync', () {
      test('should return 0 for empty store', () async {
        // Assert
        expect(await store.countAsync(), equals(0));
      });

      test('should reflect number of stored entries', () async {
        // Arrange & Act
        await store.saveAsync(const _ProfileId('user-1'), _Profile(name: 'A', email: 'a@x.com'));
        await store.saveAsync(const _ProfileId('user-2'), _Profile(name: 'B', email: 'b@x.com'));

        // Assert
        expect(await store.countAsync(), equals(2));
      });
    });
  });
}

// ---------------------------------------------------------------------------
// Test fixtures
// ---------------------------------------------------------------------------

/// A simple read model for testing.
class _Profile {
  /// The profile name.
  final String name;

  /// The profile email.
  final String email;

  /// Creates a profile.
  _Profile({required this.name, required this.email});

  /// Serializes to JSON.
  Map<String, Object?> toJson() => {'name': name, 'email': email};

  /// Deserializes from JSON.
  static _Profile fromJson(Map<String, Object?> json) {
    return _Profile(
      name: json['name'] as String,
      email: json['email'] as String,
    );
  }
}

/// A typed key for testing.
class _ProfileId {
  /// The underlying string value.
  final String value;

  /// Creates a profile ID.
  const _ProfileId(this.value);
}
