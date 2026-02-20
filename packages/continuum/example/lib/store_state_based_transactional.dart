/// State-Based Persistence with TransactionalRunner
///
/// Demonstrates how to use `StateBasedStore` with `TransactionalRunner` for
/// apps backed by a traditional REST API. The backend is the source of truth —
/// it returns targets directly, and accepts commands like "update email"
/// or "deactivate account". There is no event store; events exist only in
/// memory as domain-level state mutations.
///
/// What you'll learn:
/// - How to implement `TargetPersistenceAdapter` backed by a REST API
/// - How `TransactionalRunner` manages session lifecycle (auto-commit)
/// - How to run multiple mutations in a single transaction
/// - How the adapter receives the post-mutation target and pending
///   operations, letting it choose how to translate them into API calls
///
/// Real-world use case: A mobile or web app where the backend owns
/// the user table. The frontend applies events locally for state management,
/// then the adapter syncs changed state to the backend on commit.
library;

import 'package:continuum/continuum.dart';
import 'package:continuum_state/continuum_state.dart';
import 'package:continuum_uow/continuum_uow.dart';

import 'continuum.g.dart';
import 'domain/events/email_changed.dart';
import 'domain/events/user_deactivated.dart';
import 'domain/events/user_registered.dart';
import 'domain/user.dart';

// ── Fake Backend ────────────────────────────────────────────────────────────

/// Simulates a REST API backend that stores user records.
///
/// In a real app this would be an HTTP client making requests to
/// endpoints like `GET /users/:id`, `PATCH /users/:id`, etc.
final class FakeBackendApi {
  /// Server-side database keyed by user ID.
  final Map<String, UserRecord> _database = {};

  /// Simulates `POST /users` — creates a new user on the backend.
  Future<void> createUserAsync(String id, String name, String email) async {
    await Future<void>.delayed(const Duration(milliseconds: 30));

    _database[id] = UserRecord(
      id: id,
      name: name,
      email: email,
      isActive: true,
      deactivatedAt: null,
    );

    print('    [Backend] POST /users/$id → 201 Created');
  }

  /// Simulates `GET /users/:id` — fetches user state from the backend.
  Future<UserRecord> getUserAsync(String id) async {
    await Future<void>.delayed(const Duration(milliseconds: 30));

    final record = _database[id];
    if (record == null) {
      throw StateError('User not found: $id');
    }

    print('    [Backend] GET /users/$id → 200 OK');
    return record;
  }

  /// Simulates `PATCH /users/:id` — updates specific fields on the backend.
  Future<void> updateUserAsync(
    String id, {
    String? email,
    bool? isActive,
    DateTime? deactivatedAt,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 30));

    final record = _database[id];
    if (record == null) {
      throw StateError('User not found: $id');
    }

    // The backend applies only the fields that were sent.
    _database[id] = UserRecord(
      id: id,
      name: record.name,
      email: email ?? record.email,
      isActive: isActive ?? record.isActive,
      deactivatedAt: deactivatedAt ?? record.deactivatedAt,
    );

    print('    [Backend] PATCH /users/$id → 200 OK');
  }
}

/// Simple record representing server-side user state.
///
/// In a real app this would be a DTO parsed from JSON.
final class UserRecord {
  final String id;
  final String name;
  final String email;
  final bool isActive;
  final DateTime? deactivatedAt;

  const UserRecord({
    required this.id,
    required this.name,
    required this.email,
    required this.isActive,
    required this.deactivatedAt,
  });
}

// ── Adapter ─────────────────────────────────────────────────────────────────

/// Bridges the `User` target to the fake REST API.
///
/// `fetchAsync` maps `GET /users/:id` → `User` domain object.
/// `persistAsync` inspects pending operations and translates them
/// into the appropriate backend calls (POST for creation, PATCH for
/// mutations).
///
/// In production, replace `FakeBackendApi` with a real HTTP client.
final class UserApiAdapter implements TargetPersistenceAdapter<User> {
  /// The backend API client injected at construction time.
  final FakeBackendApi _api;

  /// Creates an adapter backed by the given API client.
  UserApiAdapter({required FakeBackendApi api}) : _api = api;

  @override
  Future<User> fetchAsync(StreamId streamId) async {
    // Load user state from the backend and reconstruct the target.
    final record = await _api.getUserAsync(streamId.value);

    // The backend returns all fields — we reconstruct the domain
    // target using its creation factory. This is the only place
    // where backend ↔ domain mapping happens.
    return User.createFromUserRegistered(
      UserRegistered(
        userId: UserId(record.id),
        name: record.name,
        email: record.email,
      ),
    );
  }

  @override
  Future<void> persistAsync(
    StreamId streamId,
    User target,
    List<Operation> pendingOperations,
  ) async {
    // Inspect the pending operations to decide which backend calls
    // to make. The adapter has full flexibility here — it can send
    // the final target state, translate each operation into a
    // separate API call, or batch them.
    for (final operation in pendingOperations) {
      switch (operation) {
        case UserRegistered():
          // Creation event → POST new user to the backend.
          await _api.createUserAsync(
            streamId.value,
            target.name,
            target.email,
          );

        case EmailChanged():
          // Email mutation → PATCH with the new email.
          await _api.updateUserAsync(
            streamId.value,
            email: target.email,
          );

        case UserDeactivated():
          // Deactivation → PATCH with the active flag and timestamp.
          await _api.updateUserAsync(
            streamId.value,
            isActive: false,
            deactivatedAt: target.deactivatedAt,
          );
      }
    }
  }
}

// ── Example ─────────────────────────────────────────────────────────────────

void main() async {
  print('═══════════════════════════════════════════════════════════════════');
  print('State-Based Persistence with TransactionalRunner');
  print('═══════════════════════════════════════════════════════════════════');
  print('');

  // The backend API client — in production, inject your HTTP client here.
  final backendApi = FakeBackendApi();

  // The adapter bridges the User target to the backend.
  final userAdapter = UserApiAdapter(api: backendApi);

  // Construct a StateBasedStore with one adapter per target type.
  // $aggregateList provides the generated event-application registries
  // so the session knows how to apply events to targets.
  final store = StateBasedStore(
    adapters: {User: userAdapter},
    targets: $aggregateList,
  );

  // TransactionalRunner manages session lifecycle automatically:
  //   1. Opens a session before the action
  //   2. Commits (saveChangesAsync) after the action succeeds
  //   3. Abandons the session if the action throws
  final runner = TransactionalRunner(store: store);

  final userId = const StreamId('user-42');

  // ── Transaction 1: Create a new user ──────────────────────────────────

  print('Transaction 1: Register a new user');
  print('');

  await runner.runAsync(() async {
    // Access the ambient session provided by the runner.
    final session = TransactionalRunner.currentSession;

    // Apply the creation event — the session tracks the new target
    // and the adapter will receive a UserRegistered operation on commit.
    final user = await session.applyAsync<User>(
      userId,
      UserRegistered(
        userId: const UserId('user-42'),
        name: 'Alice Smith',
        email: 'alice@example.com',
      ),
    );

    print('  [Memory] Created: ${user.name} <${user.email}>');
  });
  // ← TransactionalRunner auto-committed here: the adapter's
  //   persistAsync received the UserRegistered operation and
  //   called POST /users/user-42.

  print('');

  // ── Transaction 2: Load and update email ──────────────────────────────

  print('Transaction 2: Change email address');
  print('');

  await runner.runAsync(() async {
    final session = TransactionalRunner.currentSession;

    // Load the user from the backend via the adapter's fetchAsync.
    final user = await session.loadAsync<User>(userId);
    print('  [Memory] Loaded: ${user.name} <${user.email}>');

    // Apply a mutation — the session records this operation and
    // the adapter will translate it into PATCH /users/user-42.
    await session.applyAsync<User>(
      userId,
      EmailChanged(newEmail: 'alice@company.com'),
    );

    print('  [Memory] Updated: ${user.name} <${user.email}>');
  });
  // ← Auto-committed: adapter received EmailChanged and called
  //   PATCH /users/user-42 with the new email.

  print('');

  // ── Transaction 3: Multiple mutations in one transaction ──────────────

  print('Transaction 3: Change email and deactivate (batched)');
  print('');

  await runner.runAsync(() async {
    final session = TransactionalRunner.currentSession;

    // Load the user — fetched from the backend again.
    final user = await session.loadAsync<User>(userId);
    print('  [Memory] Loaded: ${user.name} <${user.email}>');

    // Apply two mutations in the same transaction.
    // Both will be persisted atomically on commit.
    await session.applyAsync<User>(
      userId,
      EmailChanged(newEmail: 'alice.archived@company.com'),
    );

    await session.applyAsync<User>(
      userId,
      UserDeactivated(deactivatedAt: DateTime.now()),
    );

    print(
      '  [Memory] Updated: ${user.name} <${user.email}> '
      'active=${user.isActive}',
    );
  });
  // ← Auto-committed: adapter received both EmailChanged and
  //   UserDeactivated, calling PATCH twice.

  print('');

  // ── Summary ───────────────────────────────────────────────────────────

  print('═══════════════════════════════════════════════════════════════════');
  print('Key Takeaways:');
  print('  1. StateBasedStore + adapter = no event store needed');
  print('  2. Backend is the source of truth (REST API, GraphQL, etc.)');
  print('  3. TransactionalRunner auto-commits on success');
  print('  4. The adapter translates operations → backend API calls');
  print('  5. Same session.applyAsync / loadAsync API as event sourcing');
  print('═══════════════════════════════════════════════════════════════════');
}
