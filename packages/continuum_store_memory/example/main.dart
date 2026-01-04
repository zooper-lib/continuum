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
import 'package:continuum_store_memory_example/domain/user.dart';

void main() async {
  // ─────────────────────────────────────────────────────────────────────────
  // SETUP: Configure the Event Store
  // ─────────────────────────────────────────────────────────────────────────

  final serializer = JsonEventSerializer(registry: $generatedEventRegistry)
    ..registerSerializer<UserRegistered>(
      eventType: 'user.registered',
      toJson: (e) => e.toJson(),
    )
    ..registerSerializer<EmailChanged>(
      eventType: 'user.email_changed',
      toJson: (e) => e.toJson(),
    )
    ..registerSerializer<UserDeactivated>(
      eventType: 'user.deactivated',
      toJson: (e) => e.toJson(),
    );

  final store = EventSourcingStore(
    eventStore: InMemoryEventStore(),
    serializer: serializer,
    registry: $generatedEventRegistry,
    aggregateFactories: $generatedAggregateFactories,
    eventAppliers: $generatedEventAppliers,
  );

  // ─────────────────────────────────────────────────────────────────────────
  // USE CASE 1: Registering a New User
  // ─────────────────────────────────────────────────────────────────────────
  //
  // A typical registration flow: user signs up with their email and name.

  final userId = StreamId('user-001');
  var session = store.openSession();

  final user = session.startStream<User>(
    userId,
    UserRegistered(
      eventId: EventId('evt-1'),
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
    EmailChanged(eventId: EventId('evt-2'), newEmail: 'jane.doe@company.com'),
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
    EmailChanged(eventId: EventId('evt-3'), newEmail: 'admin-set@example.com'),
  );
  userSession.append(
    userId,
    EmailChanged(eventId: EventId('evt-4'), newEmail: 'user-set@example.com'),
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
      eventId: EventId('evt-5'),
      deactivatedAt: DateTime.now(),
      reason: 'User requested account deletion',
    ),
  );

  await session.saveChangesAsync();

  print('User active: ${finalUser.isActive}');
}
