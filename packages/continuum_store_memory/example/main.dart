/// In-Memory Event Store - Testing & Prototyping
///
/// The in-memory store is perfect for:
///   - Unit and integration tests (fast, isolated, no cleanup needed)
///   - Rapid prototyping during development
///   - Scenarios where events don't need to survive app restarts
///
/// To run this example:
///   cd example
///   dart pub get
///   dart run build_runner build
///   dart run main.dart
library;

import 'package:continuum/continuum.dart';
import 'package:continuum_store_memory/continuum_store_memory.dart';
import 'package:continuum_store_memory_example/continuum.g.dart';
import 'package:continuum_store_memory_example/domain/account.dart';
import 'package:continuum_store_memory_example/domain/user.dart';

void main() async {
  // ─────────────────────────────────────────────────────────────────────────
  // SETUP: Configure the Event Store.
  // ─────────────────────────────────────────────────────────────────────────
  //
  // The generator auto-discovers all @Aggregate classes and creates
  // $aggregateList. Add new aggregates anywhere - no changes needed here!

  final store = EventSourcingStore(
    eventStore: InMemoryEventStore(),
    aggregates: $aggregateList,
  );

  // ─────────────────────────────────────────────────────────────────────────
  // USE CASE 1: Registering a New User
  // ─────────────────────────────────────────────────────────────────────────
  //
  // A typical registration flow: user signs up with their email and name.

  final userId = const StreamId('user-001');
  var session = store.openSession();

  final user = session.startStream<User>(
    userId,
    UserRegistered(
      eventId: const EventId('evt-1'),
      userId: 'user-001',
      email: 'jane@example.com',
      name: 'Jane Doe',
    ),
  );

  await session.saveChangesAsync();

  print('User ${user.name} registered with email: ${user.email}');

  // ─────────────────────────────────────────────────────────────────────────
  // USE CASE 2: Updating User Profile
  // ─────────────────────────────────────────────────────────────────────────
  //
  // Later, the user decides to update their email address.

  session = store.openSession();

  final loadedUser = await session.loadAsync<User>(userId);

  session.append(
    userId,
    EmailChanged(eventId: const EventId('evt-2'), newEmail: 'jane.doe@company.com'),
  );

  await session.saveChangesAsync();

  print('Email updated to: ${loadedUser.email}');

  // ─────────────────────────────────────────────────────────────────────────
  // USE CASE 3: Optimistic Concurrency
  // ─────────────────────────────────────────────────────────────────────────
  //
  // Event sourcing naturally handles concurrent modifications. If two
  // processes try to modify the same user simultaneously, the second
  // one gets a conflict and can retry with fresh data.

  final adminSession = store.openSession();
  final userSession = store.openSession();

  // Both load the same user
  await adminSession.loadAsync<User>(userId);
  await userSession.loadAsync<User>(userId);

  // Both try to change the email
  adminSession.append(
    userId,
    EmailChanged(eventId: const EventId('evt-3'), newEmail: 'admin-set@example.com'),
  );
  userSession.append(
    userId,
    EmailChanged(eventId: const EventId('evt-4'), newEmail: 'user-set@example.com'),
  );

  // Admin saves first - succeeds
  await adminSession.saveChangesAsync();
  print('Admin: email change saved successfully');

  // User tries to save - gets a conflict
  try {
    await userSession.saveChangesAsync();
  } on ConcurrencyException catch (e) {
    print(
      'User: conflict detected (expected ${e.expectedVersion}, '
      'found ${e.actualVersion})',
    );
    // In a real app, user would reload and retry
  }

  // ─────────────────────────────────────────────────────────────────────────
  // USE CASE 4: Account Deactivation
  // ─────────────────────────────────────────────────────────────────────────

  session = store.openSession();
  final finalUser = await session.loadAsync<User>(userId);

  session.append(
    userId,
    UserDeactivated(
      eventId: const EventId('evt-5'),
      deactivatedAt: DateTime.now(),
      reason: 'User requested account deletion',
    ),
  );

  await session.saveChangesAsync();

  print('User active: ${finalUser.isActive}');

  // ─────────────────────────────────────────────────────────────────────────
  // USE CASE 5: Bank Account Operations (Second Aggregate)
  // ─────────────────────────────────────────────────────────────────────────
  //
  // This demonstrates working with multiple aggregate types in the same
  // event store. Each aggregate has its own stream of events.

  final accountId = const StreamId('account-001');
  session = store.openSession();

  final account = session.startStream<Account>(
    accountId,
    AccountOpened(
      eventId: const EventId('acct-evt-1'),
      accountId: 'account-001',
      ownerId: 'user-001',
    ),
  );

  await session.saveChangesAsync();
  print('Account "${account.id}" opened for owner: ${account.ownerId}');

  // Deposit some funds
  session = store.openSession();
  final loadedAccount = await session.loadAsync<Account>(accountId);

  session.append(
    accountId,
    FundsDeposited(eventId: const EventId('acct-evt-2'), amount: 250),
  );

  await session.saveChangesAsync();
  print('Deposited \$250. New balance: \$${loadedAccount.balance}');

  // Withdraw some funds
  session = store.openSession();
  final withdrawAccount = await session.loadAsync<Account>(accountId);

  session.append(
    accountId,
    FundsWithdrawn(eventId: const EventId('acct-evt-3'), amount: 75),
  );

  await session.saveChangesAsync();
  print('Withdrew \$75. Final balance: \$${withdrawAccount.balance}');
}
