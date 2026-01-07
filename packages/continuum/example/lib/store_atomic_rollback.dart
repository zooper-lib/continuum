/// Store Example: Atomic Rollback on Conflict
///
/// This example demonstrates that atomic multi-stream saves are truly
/// all-or-nothing: if ANY stream has a concurrency conflict, NONE of the
/// streams are persisted.
///
/// This prevents partial writes across related aggregates.
library;

import 'package:continuum/continuum.dart';
import 'package:continuum_example/continuum.g.dart';
import 'package:continuum_example/domain/events/email_changed.dart';
import 'package:continuum_example/domain/events/user_registered.dart';
import 'package:continuum_example/domain/user.dart';
import 'package:continuum_store_memory/continuum_store_memory.dart';

void main() async {
  print('═══════════════════════════════════════════════════════════════════');
  print('Store Example: Atomic Rollback on Conflict');
  print('═══════════════════════════════════════════════════════════════════');
  print('');

  final store = EventSourcingStore(
    eventStore: InMemoryEventStore(),
    aggregates: $aggregateList,
  );

  // Setup: Create two users
  final userId1 = const StreamId('user-001');
  final userId2 = const StreamId('user-002');

  Session session = store.openSession();
  session.startStream<User>(
    userId1,
    UserRegistered(
      eventId: const EventId('evt-1'),
      userId: 'user-001',
      email: 'alice@example.com',
      name: 'Alice',
    ),
  );
  session.startStream<User>(
    userId2,
    UserRegistered(
      eventId: const EventId('evt-2'),
      userId: 'user-002',
      email: 'bob@example.com',
      name: 'Bob',
    ),
  );
  await session.saveChangesAsync();
  print('Setup: Created Alice and Bob');
  print('');

  // Create a stale session
  print('Creating a stale session (outdated versions)...');
  final staleSession = store.openSession();
  await staleSession.loadAsync<User>(userId1);
  final staleBob = await staleSession.loadAsync<User>(userId2);
  final bobOriginalEmail = staleBob.email;

  // Concurrent writer updates Alice
  print('Concurrent writer updates Alice...');
  final concurrentSession = store.openSession();
  await concurrentSession.loadAsync<User>(userId1);
  concurrentSession.append(
    userId1,
    EmailChanged(eventId: const EventId('evt-3'), newEmail: 'alice.concurrent@company.com'),
  );
  await concurrentSession.saveChangesAsync();
  print('  Alice updated by concurrent writer');
  print('');

  // Stale session tries to update BOTH Alice and Bob
  print('Stale session tries to update both users...');
  staleSession.append(
    userId1,
    EmailChanged(eventId: const EventId('evt-4'), newEmail: 'alice.stale@company.com'),
  );
  staleSession.append(
    userId2,
    EmailChanged(eventId: const EventId('evt-5'), newEmail: 'bob.stale@company.com'),
  );

  try {
    await staleSession.saveChangesAsync();
    print('  ❌ This should not succeed!');
  } on ConcurrencyException catch (e) {
    print('  ✗ ConcurrencyException on Alice (stream ${e.streamId})');
    print('    Expected: ${e.expectedVersion}, Actual: ${e.actualVersion}');
  }

  print('');

  // Verify: Bob was NOT modified (atomic rollback)
  session = store.openSession();
  final bobAfter = await session.loadAsync<User>(userId2);
  print('Verifying Bob was not modified...');
  print('  Bob\'s email: ${bobAfter.email}');
  print('  Expected: $bobOriginalEmail');
  print('');
  print('✓ Atomic rollback: Bob unchanged even though it had no conflict.');
  print('  All-or-nothing consistency preserved.');
}
