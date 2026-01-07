/// Store Example: Loading and Updating
///
/// This example demonstrates how to load an existing aggregate stream
/// and update it by appending events.
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
  Session session = store.openSession();
  session.startStream<User>(
    userId,
    UserRegistered(
      eventId: const EventId('evt-1'),
      userId: 'user-001',
      email: 'alice@example.com',
      name: 'Alice Smith',
    ),
  );
  await session.saveChangesAsync();
  print('Setup: Created user alice@example.com');
  print('');

  // Now demonstrate loading and updating
  print('Loading user and applying changes...');

  // Step 1: Open a new session
  session = store.openSession();

  // Step 2: Load the aggregate from the stream
  final user = await session.loadAsync<User>(userId);
  print('  Loaded: $user');

  // Step 3: Append events to mutate state
  session.append(
    userId,
    EmailChanged(
      eventId: const EventId('evt-2'),
      newEmail: 'alice.smith@company.com',
    ),
  );

  // Step 4: Save changes
  await session.saveChangesAsync();
  print('  Updated: $user');
  print('');

  print('✓ Load → mutate → save is the standard update pattern.');
}
