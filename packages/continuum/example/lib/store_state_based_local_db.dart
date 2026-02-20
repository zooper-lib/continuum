/// State-Based Persistence with Local Database
///
/// Demonstrates how to use `StateBasedStore` with a local database.
/// The adapter stores and loads targets as whole entities — no event
/// sourcing, no remote backend. This is the simplest persistence model:
/// load the full object, mutate it with domain events, and write it back.
///
/// What you'll learn:
/// - How to implement `TargetPersistenceAdapter` for a local database
/// - How the adapter serializes/deserializes whole targets (JSON maps)
/// - How `TransactionalRunner` auto-commits changes to the local DB
/// - How create vs. update is handled inside `persistAsync`
///
/// Real-world use case: A mobile app that stores user profiles in a local
/// database (Hive, Sembast, Isar, SQLite, etc.) with no backend involved.
/// The database holds the full current state of each target.
library;

import 'dart:convert';

import 'package:continuum/continuum.dart';
import 'package:continuum_state/continuum_state.dart';
import 'package:continuum_uow/continuum_uow.dart';

import 'continuum.g.dart';
import 'domain/events/email_changed.dart';
import 'domain/events/user_deactivated.dart';
import 'domain/events/user_registered.dart';
import 'domain/user.dart';

// ── Fake Local Database ─────────────────────────────────────────────────────

/// Simulates a local key-value database (like Hive, Sembast, or SharedPreferences).
///
/// In a real app, replace this with your actual database client. The API
/// intentionally mimics a simple key-value store: `put`, `get`, `delete`.
final class FakeLocalDatabase {
  /// Internal storage — simulates an on-disk key-value store.
  final Map<String, String> _storage = {};

  /// Writes a JSON-encoded record to the database.
  Future<void> put(String key, Map<String, Object?> value) async {
    // Simulate disk I/O latency.
    await Future<void>.delayed(const Duration(milliseconds: 5));

    _storage[key] = jsonEncode(value);
    print('    [DB] PUT "$key" → ${jsonEncode(value)}');
  }

  /// Reads a JSON-encoded record from the database,
  /// or `null` if the key does not exist.
  Future<Map<String, Object?>?> get(String key) async {
    await Future<void>.delayed(const Duration(milliseconds: 5));

    final raw = _storage[key];
    if (raw == null) {
      print('    [DB] GET "$key" → null');
      return null;
    }

    print('    [DB] GET "$key" → found');
    return jsonDecode(raw) as Map<String, Object?>;
  }

  /// Deletes a record from the database.
  Future<void> delete(String key) async {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    _storage.remove(key);
    print('    [DB] DELETE "$key"');
  }

  /// Returns all keys currently stored.
  Iterable<String> get keys => _storage.keys;
}

// ── Adapter ─────────────────────────────────────────────────────────────────

/// Bridges the `User` target to a local key-value database.
///
/// `fetchAsync` reads a JSON map from the database and reconstructs the
/// target. `persistAsync` serializes the target's current state
/// and writes it back. The pending operations list is ignored here — we
/// simply store the whole entity every time.
///
/// This is the simplest adapter strategy: full-entity read/write. More
/// sophisticated adapters could diff fields, use SQL UPDATE for changed
/// columns only, etc.
final class UserLocalDbAdapter implements TargetPersistenceAdapter<User> {
  /// The local database instance.
  final FakeLocalDatabase _db;

  /// Creates an adapter backed by the given local database.
  UserLocalDbAdapter({required FakeLocalDatabase db}) : _db = db;

  @override
  Future<User> fetchAsync(StreamId streamId) async {
    final json = await _db.get(streamId.value);
    if (json == null) {
      throw StateError('User not found in local DB: ${streamId.value}');
    }

    // Deserialize from JSON map → domain target.
    // First create via the creation factory, then restore mutable fields
    // that may have changed since creation.
    final user = User.createFromUserRegistered(
      UserRegistered(
        userId: UserId(json['id'] as String),
        name: json['name'] as String,
        email: json['email'] as String,
      ),
    );

    // Restore fields that are not part of the creation event.
    user.email = json['email'] as String;
    user.isActive = json['isActive'] as bool;
    final deactivatedAtRaw = json['deactivatedAt'] as String?;
    user.deactivatedAt = deactivatedAtRaw != null ? DateTime.parse(deactivatedAtRaw) : null;

    return user;
  }

  @override
  Future<void> persistAsync(
    StreamId streamId,
    User target,
    List<Operation> pendingOperations,
  ) async {
    // Serialize the full target state to a JSON map and write it.
    // We ignore pendingOperations entirely — just store the whole entity.
    await _db.put(streamId.value, {
      'id': target.id.value,
      'name': target.name,
      'email': target.email,
      'isActive': target.isActive,
      'deactivatedAt': target.deactivatedAt?.toIso8601String(),
    });
  }
}

// ── Example ─────────────────────────────────────────────────────────────────

void main() async {
  print('═══════════════════════════════════════════════════════════════════');
  print('State-Based Persistence with Local Database');
  print('═══════════════════════════════════════════════════════════════════');
  print('');

  // The local database — in production, this would be Hive, Sembast,
  // Isar, SharedPreferences, SQLite, etc.
  final db = FakeLocalDatabase();

  // The adapter bridges the User target to the local database.
  final userAdapter = UserLocalDbAdapter(db: db);

  // Construct a StateBasedStore — identical setup as the backend
  // example, just with a different adapter implementation.
  final store = StateBasedStore(
    adapters: {User: userAdapter},
    targets: $aggregateList,
  );

  // TransactionalRunner manages session lifecycle.
  final runner = TransactionalRunner(store: store);

  final userId = const StreamId('user-1');

  // ── Transaction 1: Create a new user ──────────────────────────────────

  print('Transaction 1: Create a new user');
  print('');

  await runner.runAsync(() async {
    final session = TransactionalRunner.currentSession;

    final user = await session.applyAsync<User>(
      userId,
      UserRegistered(
        userId: const UserId('user-1'),
        name: 'Bob Miller',
        email: 'bob@example.com',
      ),
    );

    print('  [Memory] Created: ${user.name} <${user.email}>');
  });
  // ← Auto-committed: adapter serialized the full User to the local DB.

  print('');

  // ── Transaction 2: Load from DB, change email ────────────────────────

  print('Transaction 2: Load from DB, change email');
  print('');

  await runner.runAsync(() async {
    final session = TransactionalRunner.currentSession;

    // Load the user from the local database.
    final user = await session.loadAsync<User>(userId);
    print('  [Memory] Loaded: ${user.name} <${user.email}>');

    // Apply a mutation — the session records this operation.
    await session.applyAsync<User>(
      userId,
      EmailChanged(newEmail: 'bob.miller@company.com'),
    );

    print('  [Memory] Updated: ${user.name} <${user.email}>');
  });
  // ← Auto-committed: adapter wrote the updated User back to the DB.

  print('');

  // ── Transaction 3: Load, deactivate ───────────────────────────────────

  print('Transaction 3: Load from DB, deactivate account');
  print('');

  await runner.runAsync(() async {
    final session = TransactionalRunner.currentSession;

    final user = await session.loadAsync<User>(userId);
    print(
      '  [Memory] Loaded: ${user.name} <${user.email}> '
      'active=${user.isActive}',
    );

    await session.applyAsync<User>(
      userId,
      UserDeactivated(deactivatedAt: DateTime(2026, 2, 19)),
    );

    print(
      '  [Memory] Updated: active=${user.isActive} '
      'deactivatedAt=${user.deactivatedAt}',
    );
  });
  // ← Auto-committed: full entity written back with isActive=false.

  print('');

  // ── Verify: Load one more time to prove persistence ───────────────────

  print('Verification: Load from DB to prove persistence');
  print('');

  await runner.runAsync(() async {
    final session = TransactionalRunner.currentSession;

    final user = await session.loadAsync<User>(userId);
    print(
      '  [Memory] Final state: ${user.name} <${user.email}> '
      'active=${user.isActive} deactivatedAt=${user.deactivatedAt}',
    );
  });

  print('');

  // ── Summary ───────────────────────────────────────────────────────────

  print('═══════════════════════════════════════════════════════════════════');
  print('Key Takeaways:');
  print('  1. Same StateBasedStore API — only the adapter changes');
  print('  2. Adapter stores/loads the whole entity as JSON');
  print('  3. No backend needed — works offline with local storage');
  print('  4. Replace FakeLocalDatabase with Hive, Sembast, Isar, etc.');
  print('  5. pendingOperations can be ignored when doing full-entity writes');
  print('═══════════════════════════════════════════════════════════════════');
}
