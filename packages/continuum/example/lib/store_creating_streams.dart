/// Store Example: Creating Streams
///
/// Demonstrates the fundamental operation: creating a new aggregate and persisting
/// its creation event to the event store.
///
/// What you'll learn:
/// - How to open a Session (unit-of-work for persistence)
/// - How to start a new stream with startStream() using a creation event
/// - How to save changes to persist events
///
/// Real-world use case: User registration, creating orders, opening accounts
library;

import 'package:continuum/continuum.dart';
import 'package:continuum_example/continuum.g.dart';
import 'package:continuum_example/domain/events/user_registered.dart';
import 'package:continuum_example/domain/user.dart';
import 'package:continuum_store_memory/continuum_store_memory.dart';

void main() async {
  print('═══════════════════════════════════════════════════════════════════');
  print('Store Example: Creating Streams');
  print('═══════════════════════════════════════════════════════════════════');
  print('');

  final store = EventSourcingStore(
    eventStore: InMemoryEventStore(),
    aggregates: $aggregateList,
  );

  print('Creating a new user stream...');
  print('');

  // Every aggregate lives in its own stream, identified by a StreamId
  final userId = const StreamId('user-001');

  // Step 1: Open a session
  // A Session is your unit-of-work - it tracks changes and persists them atomically
  final session = store.openSession();

  // Step 2: Start a new stream with a creation event
  // startStream() creates the aggregate by applying the creation event
  // The aggregate is now in memory and tracked by the session
  print('  [Session] Starting new stream...');
  final user = session.startStream<User>(
    userId,
    UserRegistered(
      userId: 'user-001',
      email: 'alice@example.com',
      name: 'Alice Smith',
    ),
  );
  print('  [Memory] Aggregate created: $user');
  print('');

  // Step 3: Save changes
  // saveChangesAsync() persists all events to the event store
  // Until you call this, nothing is persisted!
  print('  [Persisting] Saving events to store...');
  await session.saveChangesAsync();
  print('  [Store] Event persisted successfully');
  print('');

  print('✓ The UserRegistered event is now in the event store.');
  print('  Stream ID: ${userId.value}');
  print('  You can now reload this aggregate in a future session.');
}
