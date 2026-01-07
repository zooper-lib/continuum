/// Store Example: Atomic Multi-Stream Saves
///
/// Demonstrates that a single session can modify multiple aggregates and persist
/// all changes atomically - either all succeed or all fail together.
///
/// What you'll learn:
/// - How one saveChangesAsync() can persist multiple streams
/// - Why this matters for maintaining consistency across related aggregates
/// - That stores implementing AtomicEventStore support this
///
/// Real-world use cases:
/// - Money transfer: debit one account AND credit another (both must succeed)
/// - User + Profile update: keep them in sync
/// - Order + Inventory: reserve stock when creating order
/// - Any operation where partial success would leave inconsistent state
///
/// Without atomic saves, you'd need distributed transactions or sagas.
/// With Continuum, it's built-in when your store supports AtomicEventStore.
library;

import 'package:continuum/continuum.dart';
import 'package:continuum_example/continuum.g.dart';
import 'package:continuum_example/domain/events/email_changed.dart';
import 'package:continuum_example/domain/events/user_registered.dart';
import 'package:continuum_example/domain/user.dart';
import 'package:continuum_store_memory/continuum_store_memory.dart';

void main() async {
  print('═══════════════════════════════════════════════════════════════════');
  print('Store Example: Atomic Multi-Stream Saves');
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

  // Demonstrate atomic multi-stream save
  print('Updating both users in one transaction...');
  print('');

  // Open one session for both aggregates
  session = store.openSession();

  // Load both users
  print('  [Session] Loading Alice and Bob...');
  final alice = await session.loadAsync<User>(userId1);
  final bob = await session.loadAsync<User>(userId2);
  print('  [Session] Both loaded');
  print('');

  // Append changes to BOTH streams within the same session
  print('  [Session] Staging changes for Alice...');
  session.append(
    userId1,
    EmailChanged(eventId: const EventId('evt-3'), newEmail: 'alice.new@company.com'),
  );
  print('  [Session] Staging changes for Bob...');
  session.append(
    userId2,
    EmailChanged(eventId: const EventId('evt-4'), newEmail: 'bob.new@company.com'),
  );
  print('  [Session] Both changes staged');
  print('');

  // One saveChangesAsync() persists BOTH streams atomically
  print('  [Persisting] Saving both streams atomically...');
  await session.saveChangesAsync();
  print('  [Store] Both streams persisted successfully');
  print('');

  print('Result:');
  print('  Alice: ${alice.email}');
  print('  Bob: ${bob.email}');
  print('');
  print('✓ Both users updated in a single atomic transaction.');
  print('  If ANY stream had a conflict, NEITHER would be persisted.');
  print('  This is true all-or-nothing consistency.');
}
