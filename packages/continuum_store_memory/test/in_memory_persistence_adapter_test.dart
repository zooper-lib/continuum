import 'package:continuum/continuum.dart';
import 'package:continuum_store_memory/continuum_store_memory.dart';
import 'package:test/test.dart';

void main() {
  group('InMemoryPersistenceAdapter', () {
    late InMemoryPersistenceAdapter<_Profile> adapter;

    setUp(() {
      adapter = InMemoryPersistenceAdapter<_Profile>(
        toJson: (profile) => profile.toJson(),
        fromJson: _Profile.fromJson,
      );
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
        final updated = _Profile(id: 'profile-3', name: 'Carol Updated', age: 41);
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

    group('length', () {
      test('returns zero when the store is empty', () {
        // Assert — no aggregates have been persisted yet.
        expect(adapter.length, equals(0));
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
        expect(adapter.length, equals(2));
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

        // Assert — length must stay at 1 since it's the same key.
        expect(adapter.length, equals(1));
      });
    });

    group('clear', () {
      test('removes all stored aggregates', () async {
        // Arrange — store some aggregates.
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

        // Act
        adapter.clear();

        // Assert — store must be empty.
        expect(adapter.length, equals(0));
      });

      test('causes subsequent fetches to throw', () async {
        // Arrange — store and then clear.
        final streamId = const StreamId('c');
        await adapter.persistAsync(
          streamId,
          _Profile(id: 'c', name: 'C', age: 3),
          [],
        );
        adapter.clear();

        // Act & Assert — the aggregate is gone.
        await expectLater(
          adapter.fetchAsync(streamId),
          throwsA(isA<StateError>()),
        );
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

        // Assert — null must survive the round-trip.
        expect(fetched.age, isNull);
      });
    });

    group('deleteAsync', () {
      test('removes a stored aggregate', () async {
        // Arrange — store a profile, then delete it.
        const streamId = StreamId('profile-del');
        final profile = _Profile(id: 'profile-del', name: 'Deleted', age: 1);
        await adapter.persistAsync(streamId, profile, []);

        // Act — delete the stored aggregate.
        await adapter.deleteAsync(streamId);

        // Assert — fetch should throw because the entity is gone.
        await expectLater(
          adapter.fetchAsync(streamId),
          throwsA(isA<StateError>()),
        );
        expect(adapter.length, equals(0));
      });

      test('is idempotent for non-existent stream', () async {
        // Arrange — empty store.
        const streamId = StreamId('nonexistent');

        // Act & Assert — deleting a missing key should not throw.
        await adapter.deleteAsync(streamId);
        expect(adapter.length, equals(0));
      });

      test('only removes the targeted stream', () async {
        // Arrange — store two profiles.
        const streamId1 = StreamId('keep');
        const streamId2 = StreamId('remove');
        await adapter.persistAsync(
          streamId1,
          _Profile(id: 'keep', name: 'Keep', age: 1),
          [],
        );
        await adapter.persistAsync(
          streamId2,
          _Profile(id: 'remove', name: 'Remove', age: 2),
          [],
        );

        // Act — delete only the second profile.
        await adapter.deleteAsync(streamId2);

        // Assert — first profile is still there, second is gone.
        final fetched = await adapter.fetchAsync(streamId1);
        expect(fetched.name, equals('Keep'));
        expect(adapter.length, equals(1));
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
