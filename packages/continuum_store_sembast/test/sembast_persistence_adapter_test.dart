import 'dart:io';

import 'package:continuum/continuum.dart';
import 'package:continuum_store_sembast/continuum_store_sembast.dart';
import 'package:sembast/sembast_io.dart';
import 'package:test/test.dart';

void main() {
  group('SembastPersistenceAdapter', () {
    late Directory tempDir;
    late Database database;
    late SembastPersistenceAdapter<_Profile> adapter;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'sembast_persistence_test_',
      );
      final dbPath = '${tempDir.path}/test.db';
      database = await databaseFactoryIo.openDatabase(dbPath);
      adapter = SembastPersistenceAdapter<_Profile>(
        database: database,
        storeName: 'profiles',
        toJson: (profile) => profile.toJson(),
        fromJson: _Profile.fromJson,
      );
    });

    tearDown(() async {
      await database.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    group('fetchAsync', () {
      test('returns the stored aggregate when it exists', () async {
        // Arrange — persist a profile first.
        final streamId = const StreamId('profile-1');
        final profile = _Profile(
          id: 'profile-1',
          name: 'Alice',
          age: 30,
        );
        await adapter.persistAsync(streamId, profile, []);

        // Act
        final fetched = await adapter.fetchAsync(streamId);

        // Assert — round-trip must preserve all fields.
        expect(fetched.id, equals('profile-1'));
        expect(fetched.name, equals('Alice'));
        expect(fetched.age, equals(30));
      });

      test('throws StateError when the aggregate does not exist', () async {
        // Arrange — empty store.
        final streamId = const StreamId('nonexistent');

        // Act & Assert — fetching a missing aggregate must throw.
        await expectLater(
          adapter.fetchAsync(streamId),
          throwsA(isA<StateError>()),
        );
      });
    });

    group('persistAsync', () {
      test('stores the aggregate so it can be fetched later', () async {
        // Arrange
        final streamId = const StreamId('profile-2');
        final profile = _Profile(id: 'profile-2', name: 'Bob', age: 25);

        // Act
        await adapter.persistAsync(streamId, profile, []);

        // Assert — the aggregate must be retrievable.
        final fetched = await adapter.fetchAsync(streamId);
        expect(fetched.name, equals('Bob'));
      });

      test('overwrites existing aggregate on repeated persist', () async {
        // Arrange — persist an initial version.
        final streamId = const StreamId('profile-3');
        final original = _Profile(id: 'profile-3', name: 'Carol', age: 40);
        await adapter.persistAsync(streamId, original, []);

        // Act — persist an updated version with the same stream ID.
        final updated = _Profile(
          id: 'profile-3',
          name: 'Carol Updated',
          age: 41,
        );
        await adapter.persistAsync(streamId, updated, []);

        // Assert — fetch must return the updated version.
        final fetched = await adapter.fetchAsync(streamId);
        expect(fetched.name, equals('Carol Updated'));
        expect(fetched.age, equals(41));
      });

      test('ignores pending operations and stores full state', () async {
        // Arrange — create a fake operation list.
        final streamId = const StreamId('profile-4');
        final profile = _Profile(id: 'profile-4', name: 'Dave', age: 35);
        final operations = <Operation>[_FakeOperation()];

        // Act — operations should be ignored.
        await adapter.persistAsync(streamId, profile, operations);

        // Assert — the stored data must reflect full aggregate state.
        final fetched = await adapter.fetchAsync(streamId);
        expect(fetched.name, equals('Dave'));
      });

      test('stores multiple distinct aggregates independently', () async {
        // Arrange
        final profile1 = _Profile(id: 'a', name: 'One', age: 1);
        final profile2 = _Profile(id: 'b', name: 'Two', age: 2);

        // Act
        await adapter.persistAsync(const StreamId('a'), profile1, []);
        await adapter.persistAsync(const StreamId('b'), profile2, []);

        // Assert — each aggregate must be independently retrievable.
        final fetched1 = await adapter.fetchAsync(const StreamId('a'));
        final fetched2 = await adapter.fetchAsync(const StreamId('b'));
        expect(fetched1.name, equals('One'));
        expect(fetched2.name, equals('Two'));
      });
    });

    group('countAsync', () {
      test('returns zero when the store is empty', () async {
        // Assert — no aggregates have been persisted yet.
        expect(await adapter.countAsync(), equals(0));
      });

      test('reflects the number of stored aggregates', () async {
        // Arrange
        await adapter.persistAsync(
          const StreamId('a'),
          _Profile(id: 'a', name: 'A', age: 1),
          [],
        );
        await adapter.persistAsync(
          const StreamId('b'),
          _Profile(id: 'b', name: 'B', age: 2),
          [],
        );

        // Assert — two distinct aggregates were stored.
        expect(await adapter.countAsync(), equals(2));
      });

      test('does not increment when overwriting the same stream ID', () async {
        // Arrange
        final streamId = const StreamId('same');
        await adapter.persistAsync(
          streamId,
          _Profile(id: 'same', name: 'V1', age: 1),
          [],
        );

        // Act — overwrite with a new version.
        await adapter.persistAsync(
          streamId,
          _Profile(id: 'same', name: 'V2', age: 2),
          [],
        );

        // Assert — count must stay at 1 since it's the same key.
        expect(await adapter.countAsync(), equals(1));
      });
    });

    group('persistence', () {
      test('data survives close and reopen', () async {
        // Arrange — persist, then close the database.
        final streamId = const StreamId('persistent-1');
        final profile = _Profile(
          id: 'persistent-1',
          name: 'Persistent',
          age: 99,
        );
        await adapter.persistAsync(streamId, profile, []);
        await database.close();

        // Act — reopen from the same database file.
        final dbPath = '${tempDir.path}/test.db';
        database = await databaseFactoryIo.openDatabase(dbPath);
        adapter = SembastPersistenceAdapter<_Profile>(
          database: database,
          storeName: 'profiles',
          toJson: (profile) => profile.toJson(),
          fromJson: _Profile.fromJson,
        );
        final fetched = await adapter.fetchAsync(streamId);

        // Assert — data must have been persisted to disk.
        expect(fetched.id, equals('persistent-1'));
        expect(fetched.name, equals('Persistent'));
        expect(fetched.age, equals(99));
      });
    });

    group('serialization round-trip', () {
      test('preserves null fields through serialization', () async {
        // Arrange — a profile with a nullable field set to null.
        final streamId = const StreamId('nullable');
        final profile = _Profile(
          id: 'nullable',
          name: 'NullTest',
          age: null,
        );

        // Act
        await adapter.persistAsync(streamId, profile, []);
        final fetched = await adapter.fetchAsync(streamId);

        // Assert — null must survive the JSON encode/decode round-trip.
        expect(fetched.age, isNull);
      });
    });
  });
}

// ---------------------------------------------------------------------------
// Test fixtures
// ---------------------------------------------------------------------------

/// A simple data class representing a profile, used as the
/// aggregate under test.
final class _Profile {
  /// The profile identifier.
  final String id;

  /// The display name.
  final String name;

  /// The age, which may be null.
  final int? age;

  /// Creates a profile with the given fields.
  _Profile({required this.id, required this.name, required this.age});

  /// Serializes the profile to a JSON-compatible map.
  Map<String, Object?> toJson() => {'id': id, 'name': name, 'age': age};

  /// Deserializes a profile from a JSON-compatible map.
  static _Profile fromJson(Map<String, Object?> json) {
    return _Profile(
      id: json['id']! as String,
      name: json['name']! as String,
      age: json['age'] as int?,
    );
  }
}

/// A fake [Operation] for testing that operations are ignored.
final class _FakeOperation implements Operation {}
