/// Store Example: Handling Concurrency Conflicts
///
/// This example demonstrates how to detect and handle concurrency conflicts.
/// When two sessions modify the same aggregate simultaneously, the second save
/// throws a ConcurrencyException.
///
/// This is the mechanism that prevents lost updates in multi-user scenarios.
library;

import 'package:continuum/continuum.dart';
import 'package:continuum_example/continuum.g.dart';
import 'package:continuum_example/domain/events/email_changed.dart';
import 'package:continuum_example/domain/events/user_registered.dart';
import 'package:continuum_example/domain/user.dart';
import 'package:continuum_store_memory/continuum_store_memory.dart';

void main() async {
  print('═══════════════════════════════════════════════════════════════════');
  print('Store Example: Handling Concurrency Conflicts');
  print('═══════════════════════════════════════════════════════════════════');
  print('');

  final store = EventSourcingStore(
    eventStore: InMemoryEventStore(),
    aggregates: $aggregateList,
  );

  // Setup: Create a user
  final userId = const StreamId('user-001');
  final Session session = store.openSession();
  session.startStream<User>(
    userId,
    UserRegistered(
      eventId: const EventId('evt-1'),
      userId: 'user-001',
      email: 'bob@example.com',
      name: 'Bob Johnson',
    ),
  );
  await session.saveChangesAsync();
  print('Created user: bob@example.com');
  print('');

  // Simulate two concurrent operations
  print('Simulating concurrent modifications...');
  print('');

  // Session 1: Admin tries to change email
  print('Session 1 (Admin): Loading user and preparing change...');
  final adminSession = store.openSession();
  await adminSession.loadAsync<User>(userId);

  // Session 2: User also tries to change email (before admin saves)
  print('Session 2 (User): Loading user and preparing change...');
  final userSession = store.openSession();
  await userSession.loadAsync<User>(userId);
  print('');

  // Admin changes email
  adminSession.append(
    userId,
    EmailChanged(
      eventId: const EventId('evt-admin'),
      newEmail: 'bob.admin@company.com',
    ),
  );
  print('Session 1: Admin preparing to save...');

  // User also changes email
  userSession.append(
    userId,
    EmailChanged(
      eventId: const EventId('evt-user'),
      newEmail: 'bob.user@company.com',
    ),
  );
  print('Session 2: User preparing to save...');
  print('');

  // Admin saves first - succeeds
  await adminSession.saveChangesAsync();
  print('✓ Session 1 (Admin): Save succeeded');
  print('  New email: bob.admin@company.com');
  print('');

  // User tries to save - gets concurrency conflict
  try {
    await userSession.saveChangesAsync();
    print('❌ This should not happen!');
  } on ConcurrencyException catch (e) {
    print('✗ Session 2 (User): ConcurrencyException detected!');
    print('  Expected version: ${e.expectedVersion}');
    print('  Actual version: ${e.actualVersion}');
    print('');
    print('  → User must reload and retry with fresh data.');
  }

  print('');
  print('✓ Conflict detection prevents lost updates.');
  print('  Each save must be based on the current version.');
}
