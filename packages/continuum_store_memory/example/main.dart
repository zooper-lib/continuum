/// In-Memory Event Store - Quick Start Example
///
/// This example shows the minimal setup for using InMemoryEventStore.
/// The in-memory store is perfect for:
///   - Unit and integration tests (fast, isolated, no cleanup needed)
///   - Rapid prototyping during development
///   - Scenarios where events don't need to survive app restarts
///
/// For comprehensive examples of event sourcing patterns (sessions, concurrency,
/// atomic operations, etc.), see the continuum package examples.
///
/// To run:
///   cd example
///   dart pub get
///   dart run build_runner build
///   dart run main.dart
library;

import 'package:continuum/continuum.dart';
import 'package:continuum_store_memory/continuum_store_memory.dart';
import 'package:continuum_store_memory_example/continuum.g.dart';
import 'package:continuum_store_memory_example/domain/user.dart';

void main() async {
  print('═══════════════════════════════════════════════════════════════════');
  print('InMemoryEventStore - Quick Start');
  print('═══════════════════════════════════════════════════════════════════');
  print('');

  // Setup: Create the in-memory event store
  // Events are stored in memory only - lost when the process exits
  final store = EventSourcingStore(
    eventStore: InMemoryEventStore(),
    aggregates: $aggregateList, // Auto-generated from AggregateRoot classes
  );

  print('Creating a user...');
  final userId = const StreamId('user-001');

  // Open a session, create aggregate, save
  ContinuumSession session = store.openSession();
  final user = session.startStream<User>(
    userId,
    UserRegistered(
      userId: const UserId('user-001'),
      email: 'alice@example.com',
      name: 'Alice',
    ),
  );
  await session.saveChangesAsync();
  print('  Created: $user');
  print('');

  print('Loading the user...');
  session = store.openSession();
  final loadedUser = await session.loadAsync<User>(userId);
  print('  Loaded: $loadedUser');
  print('');

  print('✓ InMemoryEventStore setup complete!');
  print('');
  print('For more examples (concurrency, atomic saves, conflict handling),');
  print('see the continuum package examples.');
}
