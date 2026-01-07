/// Store Example: Creating Streams
///
/// This example demonstrates how to create a new aggregate stream and persist it.
/// Starting a stream is how you create a new aggregate in the event store.
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
  final userId = const StreamId('user-001');

  // Step 1: Open a session (unit-of-work)
  final session = store.openSession();

  // Step 2: Start a new stream with a creation event
  final user = session.startStream<User>(
    userId,
    UserRegistered(
      eventId: const EventId('evt-1'),
      userId: 'user-001',
      email: 'alice@example.com',
      name: 'Alice Smith',
    ),
  );

  // Step 3: Save changes (persists the event)
  await session.saveChangesAsync();

  print('  Created: $user');
  print('');
  print('✓ The aggregate and its creation event are now persisted.');
  print('  Stream ID: ${userId.value}');
}
