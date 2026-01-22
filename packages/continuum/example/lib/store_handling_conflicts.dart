/// Store Example: Handling Concurrency Conflicts
///
/// Demonstrates optimistic concurrency control: when two sessions try to save
/// changes to the same aggregate, the second one detects that the aggregate
/// has changed and throws ConcurrencyException.
///
/// What you'll learn:
/// - Why sessions track the expected version
/// - How ConcurrencyException prevents lost updates
/// - What to do when a conflict occurs (reload and retry)
///
/// Real-world use case: Two users editing the same record, simultaneous updates
/// from different parts of your app, distributed systems with eventual consistency
///
/// The "lost update" problem this solves:
/// Without versioning, if Alice and Bob both load version 1, modify it, and save,
/// one person's changes would be silently lost. Event sourcing prevents this.
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
  final ContinuumSession session = store.openSession();
  session.startStream<User>(
    userId,
    UserRegistered(
      userId: const UserId('user-001'),
      email: 'bob@example.com',
      name: 'Bob Johnson',
    ),
  );
  await session.saveChangesAsync();
  print('Created user: bob@example.com');
  print('');

  // Simulate two concurrent operations
  print('Simulating two users editing the same aggregate simultaneously...');
  print('');

  // Session 1: Admin loads the user
  // At this point, the stream has version 0 (only the creation event)
  print('Session 1 (Admin): Loading user...');
  final adminSession = store.openSession();
  await adminSession.loadAsync<User>(userId);
  print('  [Session 1] Loaded user at version 0');
  print('  [Session 1] Planning to save at version 1');
  print('');

  // Session 2: Another user also loads (before admin saves)
  // This session ALSO sees version 0 and will try to save at version 1
  print('Session 2 (User): Loading user...');
  final userSession = store.openSession();
  await userSession.loadAsync<User>(userId);
  print('  [Session 2] Loaded user at version 0');
  print('  [Session 2] Planning to save at version 1');
  print('');

  // Both sessions prepare changes (neither has saved yet)
  print('Both sessions preparing changes...');
  adminSession.append(
    userId,
    EmailChanged(
      newEmail: 'bob.admin@company.com',
    ),
  );
  print('  [Session 1] Staged: bob.admin@company.com');

  userSession.append(
    userId,
    EmailChanged(
      newEmail: 'bob.user@company.com',
    ),
  );
  print('  [Session 2] Staged: bob.user@company.com');
  print('');

  // Admin saves first - succeeds
  print('Session 1 saves first...');
  await adminSession.saveChangesAsync();
  print('  ✓ [Session 1] Saved successfully at version 1');
  print('  [Store] Stream is now at version 1');
  print('  [Store] Email is: bob.admin@company.com');
  print('');

  // User tries to save - conflict detected!
  print('Session 2 tries to save...');
  try {
    await userSession.saveChangesAsync();
    print('  ❌ This should never happen!');
  } on ConcurrencyException catch (e) {
    print('  ✗ [Session 2] ConcurrencyException!');
    print('  [Session 2] Expected version ${e.expectedVersion} (what I loaded)');
    print('  [Store] Actual version ${e.actualVersion} (current stream version)');
    print('');
    print('  → Session 2 must reload from version 1 and retry.');
    print('  → The admin\'s changes are protected from being overwritten.');
  }

  print('');
  print('✓ Optimistic concurrency prevents lost updates.');
  print('  The "last writer wins" only if they have the latest version.');
}
