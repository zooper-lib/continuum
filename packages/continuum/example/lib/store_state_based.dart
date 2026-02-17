/// Store Example: State-Based Persistence
///
/// Demonstrates `StateBasedStore` — the persistence mode for apps backed
/// by a traditional backend (REST API, GraphQL, database). Instead of
/// persisting events, each aggregate is loaded and saved through an
/// `AggregatePersistenceAdapter` that talks to the backend.
///
/// What you'll learn:
/// - How to implement `AggregatePersistenceAdapter` for your aggregate
/// - How to construct a `StateBasedStore` from adapters and aggregate metadata
/// - How sessions work identically to `EventSourcingStore` (same `applyAsync` /
///   `saveChangesAsync` contract)
/// - How the adapter receives the post-event aggregate state on save
///
/// Real-world use case: Backend-authoritative apps where the frontend uses
/// domain events for local state management, then syncs to a REST API.
library;

import 'package:continuum/continuum.dart';
import 'package:continuum_example/continuum.g.dart';
import 'package:continuum_example/domain/events/email_changed.dart';
import 'package:continuum_example/domain/events/user_registered.dart';
import 'package:continuum_example/domain/user.dart';

/// A fake backend adapter that stores user state in memory.
///
/// In a real app this would make HTTP requests to your backend API.
/// The adapter translates between the domain aggregate and the backend's
/// representation (DTOs, JSON, etc.).
class FakeUserApiAdapter implements AggregatePersistenceAdapter<User> {
  /// Simulates a backend database keyed by stream ID.
  final Map<String, _UserRecord> _backendDb = {};

  @override
  Future<User> fetchAsync(StreamId streamId) async {
    // Simulate network latency.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final record = _backendDb[streamId.value];
    if (record == null) {
      throw StateError('User not found: ${streamId.value}');
    }

    print('    [Backend] GET /users/${streamId.value} → 200 OK');

    // Reconstruct the domain aggregate from the stored record.
    return User.createFromUserRegistered(
      UserRegistered(
        userId: UserId(record.id),
        email: record.email,
        name: record.name,
      ),
    );
  }

  @override
  Future<void> persistAsync(
    StreamId streamId,
    User aggregate,
    List<ContinuumEvent> pendingEvents,
  ) async {
    // Simulate network latency.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    // The adapter decides how to translate the aggregate + events into
    // backend calls. Here we simply store the final state.
    _backendDb[streamId.value] = _UserRecord(
      id: streamId.value,
      email: aggregate.email,
      name: aggregate.name,
    );

    print(
      '    [Backend] PUT /users/${streamId.value} '
      '(${pendingEvents.length} event(s)) → 200 OK',
    );
  }
}

/// Simple record representing server-side user state.
class _UserRecord {
  final String id;
  final String email;
  final String name;

  const _UserRecord({
    required this.id,
    required this.email,
    required this.name,
  });
}

void main() async {
  print('═══════════════════════════════════════════════════════════════════');
  print('Store Example: State-Based Persistence');
  print('═══════════════════════════════════════════════════════════════════');
  print('');

  // The adapter bridges your aggregate to the backend.
  // In production you'd inject an HTTP client here.
  final userAdapter = FakeUserApiAdapter();

  // Construct the store with one adapter per aggregate type.
  // $aggregateList provides the generated event-application registries.
  final store = StateBasedStore(
    adapters: {User: userAdapter},
    aggregates: $aggregateList,
  );

  final userId = const StreamId('user-001');

  // ── Session 1: Create and mutate ──────────────────────────────────────

  print('Session 1: Creating a user and changing email');
  print('');

  ContinuumSession session = store.openSession();

  // Apply a creation event — same API as EventSourcingStore
  print('  [Session] Applying UserRegistered...');
  final user = await session.applyAsync<User>(
    userId,
    UserRegistered(
      userId: const UserId('user-001'),
      email: 'alice@example.com',
      name: 'Alice Smith',
    ),
  );
  print('  [Memory]  Created: ${user.name} <${user.email}>');
  print('');

  // Apply a mutation event
  print('  [Session] Applying EmailChanged...');
  await session.applyAsync<User>(
    userId,
    EmailChanged(newEmail: 'alice@company.com'),
  );
  print('  [Memory]  Updated: ${user.name} <${user.email}>');
  print('');

  // Save — the adapter receives the post-event aggregate + pending events
  print('  [Persisting] Saving via adapter...');
  await session.saveChangesAsync();
  print('  Done.');
  print('');

  // ── Session 2: Load from backend ──────────────────────────────────────

  print('Session 2: Loading user from backend');
  print('');

  session = store.openSession();

  // loadAsync delegates to the adapter's fetchAsync
  print('  [Session] Loading user...');
  final loaded = await session.loadAsync<User>(userId);
  print('  [Memory]  Loaded: ${loaded.name} <${loaded.email}>');
  print('');

  print('✓ The user was persisted to and loaded from the fake backend.');
  print('  In production, the adapter would make real HTTP calls.');
}
