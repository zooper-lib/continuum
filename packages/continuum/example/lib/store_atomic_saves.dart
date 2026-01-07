/// Store Example: Atomic Multi-Stream Saves
///
/// This example demonstrates atomic multi-stream persistence - saving changes
/// to multiple aggregates as a single all-or-nothing transaction.
///
/// Use cases:
/// - Transferring balance between accounts
/// - Updating a user and their profile together
/// - Any operation requiring cross-aggregate consistency
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
  print('Updating both users atomically...');
  session = store.openSession();

  final alice = await session.loadAsync<User>(userId1);
  final bob = await session.loadAsync<User>(userId2);

  session.append(
    userId1,
    EmailChanged(eventId: const EventId('evt-3'), newEmail: 'alice.new@company.com'),
  );
  session.append(
    userId2,
    EmailChanged(eventId: const EventId('evt-4'), newEmail: 'bob.new@company.com'),
  );

  // One saveChangesAsync() persists both streams atomically
  await session.saveChangesAsync();

  print('  Alice: ${alice.email}');
  print('  Bob: ${bob.email}');
  print('');
  print('✓ Both users updated in a single atomic transaction.');
  print('  If one had failed, neither would be persisted.');
}
