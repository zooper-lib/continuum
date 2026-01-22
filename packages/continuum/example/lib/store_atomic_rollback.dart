/// Store Example: Atomic Rollback on Conflict
///
/// Demonstrates that atomic multi-stream saves provide true all-or-nothing
/// semantics: if ANY stream has a concurrency conflict, NONE of the streams
/// are persisted - even the streams that had no conflict.
///
/// What you'll learn:
/// - Why atomic rollback matters for data consistency
/// - How one conflict prevents all writes in the transaction
/// - The difference between atomic and non-atomic stores
///
/// Real-world scenario this prevents:
/// Imagine a money transfer: debit account A, credit account B.
/// If the debit succeeds but credit fails (due to conflict), you'd lose money!
/// Atomic rollback ensures: no partial transfers, ever.
///
/// Another example: updating a user AND their profile.
/// If the user update fails, you don't want an orphaned profile update.
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

  ContinuumSession session = store.openSession();
  session.startStream<User>(
    userId1,
    UserRegistered(
      userId: const UserId('user-001'),
      email: 'alice@example.com',
      name: 'Alice',
    ),
  );
  session.startStream<User>(
    userId2,
    UserRegistered(
      userId: const UserId('user-002'),
      email: 'bob@example.com',
      name: 'Bob',
    ),
  );
  await session.saveChangesAsync();
  print('Setup: Created Alice and Bob');
  print('');

  // Create a stale session that loads both users
  print('Stale session loads both users...');
  final staleSession = store.openSession();
  await staleSession.loadAsync<User>(userId1);
  final staleBob = await staleSession.loadAsync<User>(userId2);
  final bobOriginalEmail = staleBob.email;
  print('  [Stale Session] Loaded Alice at version 0');
  print('  [Stale Session] Loaded Bob at version 0');
  print('');

  // Meanwhile, a concurrent writer updates ONLY Alice
  print('Concurrent writer updates Alice (before stale session saves)...');
  final concurrentSession = store.openSession();
  await concurrentSession.loadAsync<User>(userId1);
  concurrentSession.append(
    userId1,
    EmailChanged(
      newEmail: 'alice.concurrent@company.com',
    ),
  );
  await concurrentSession.saveChangesAsync();
  print('  [Store] Alice now at version 1');
  print('  [Store] Bob still at version 0');
  print('');

  // Stale session tries to update BOTH Alice and Bob
  print('Stale session tries to save changes to BOTH users...');
  staleSession.append(
    userId1,
    EmailChanged(newEmail: 'alice.stale@company.com'),
  );
  print('  [Stale Session] Staging Alice update (expects version 0 → 1)');
  staleSession.append(
    userId2,
    EmailChanged(newEmail: 'bob.stale@company.com'),
  );
  print('  [Stale Session] Staging Bob update (expects version 0 → 1)');
  print('');

  print('  [Stale Session] Attempting atomic save...');
  try {
    await staleSession.saveChangesAsync();
    print('  ❌ This should never succeed!');
  } on ConcurrencyException catch (e) {
    print('  ✗ ConcurrencyException on ${e.streamId}!');
    print('    [Stale Session] Expected Alice at version ${e.expectedVersion}');
    print('    [Store] Alice is actually at version ${e.actualVersion}');
    print('');
    print('  → Atomic rollback triggered!');
    print('  → Bob\'s change is DISCARDED even though Bob had no conflict');
  }

  print('');

  // Verify: Bob was NOT modified (atomic rollback)
  session = store.openSession();
  final bobAfter = await session.loadAsync<User>(userId2);
  print('Verifying atomic rollback worked...');
  print('  Bob\'s email: ${bobAfter.email}');
  print('  Expected (original): $bobOriginalEmail');
  print('  Match: ${bobAfter.email == bobOriginalEmail ? "YES" : "NO"}');
  print('');
  print('✓ Atomic rollback prevented partial write!');
  print('  Even though Bob had no conflict, it was not persisted.');
  print('  This preserves cross-aggregate consistency.');
}
