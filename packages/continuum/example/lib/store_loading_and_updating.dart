/// Store Example: Loading and Updating
///
/// Demonstrates the typical workflow: load an existing aggregate from the store,
/// apply changes via events, and persist those changes.
///
/// What you'll learn:
/// - How loadAsync() rebuilds aggregates by replaying their event history
/// - How to append mutation events to an aggregate
/// - Why each session is independent (fresh load every time)
///
/// Real-world use case: Editing profiles, updating orders, processing transactions
library;

import 'package:continuum/continuum.dart';
import 'package:continuum_example/continuum.g.dart';
import 'package:continuum_example/domain/events/email_changed.dart';
import 'package:continuum_example/domain/events/user_registered.dart';
import 'package:continuum_example/domain/user.dart';
import 'package:continuum_store_memory/continuum_store_memory.dart';

void main() async {
  print('═══════════════════════════════════════════════════════════════════');
  print('Store Example: Loading and Updating');
  print('═══════════════════════════════════════════════════════════════════');
  print('');

  final store = EventSourcingStore(
    eventStore: InMemoryEventStore(),
    aggregates: $aggregateList,
  );

  // Setup: Create a user first
  final userId = const StreamId('user-001');
  ContinuumSession session = store.openSession();
  session.startStream<User>(
    userId,
    UserRegistered(
      userId: const UserId('user-001'),
      email: 'alice@example.com',
      name: 'Alice Smith',
    ),
  );
  await session.saveChangesAsync();
  print('Setup: Created user alice@example.com');
  print('');

  // Now demonstrate loading and updating
  print('Loading user from event store...');
  print('');

  // Step 1: Open a new session
  // Sessions are short-lived - open one per logical operation
  session = store.openSession();

  // Step 2: Load the aggregate from the stream
  // loadAsync() fetches ALL events for this stream and replays them
  // to rebuild the current aggregate state
  print('  [Store] Loading events from stream ${userId.value}...');
  print('  [Memory] Replaying events to rebuild state...');
  final user = await session.loadAsync<User>(userId);
  print('  [Memory] Aggregate loaded: $user');
  print('');

  // Step 3: Append events to mutate state
  // append() applies the event to the in-memory aggregate
  // and tracks it for persistence
  print('  [Session] Appending EmailChanged event...');
  session.append(
    userId,
    EmailChanged(
      newEmail: 'alice.smith@company.com',
    ),
  );
  print('  [Memory] State updated: $user');
  print('');

  // Step 4: Save changes
  // This persists the EmailChanged event to the store
  print('  [Persisting] Saving new events...');
  await session.saveChangesAsync();
  print('  [Store] EmailChanged event persisted');
  print('');

  print('✓ The stream now has 2 events: UserRegistered + EmailChanged');
  print('  Next time you load, both events will be replayed.');
}
