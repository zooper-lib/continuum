/// Sembast Event Store - Quick Start Example
///
/// This example shows the minimal setup for using SembastEventStore.
/// The Sembast store provides persistent event storage that survives app restarts.
/// Ideal for:
///   - Mobile apps (Flutter) with offline-first architecture
///   - Desktop apps needing local data persistence
///   - Web apps (via sembast_web)
///   - Cross-platform persistence with a pure Dart solution
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

import 'dart:io';

import 'package:continuum/continuum.dart';
import 'package:continuum_store_sembast/continuum_store_sembast.dart';
import 'package:continuum_store_sembast_example/continuum.g.dart';
import 'package:continuum_store_sembast_example/domain/user.dart';
import 'package:sembast/sembast_io.dart';

void main() async {
  print('═══════════════════════════════════════════════════════════════════');
  print('SembastEventStore - Quick Start');
  print('═══════════════════════════════════════════════════════════════════');
  print('');

  // Setup: Create a temporary directory for the database
  // In a real Flutter app, use path_provider to get the documents directory
  final storageDir = Directory.systemTemp.createTempSync('continuum_example_');
  final dbPath = '${storageDir.path}/events.db';

  // Open the Sembast event store
  final sembastStore = await SembastEventStore.openAsync(
    databaseFactory: databaseFactoryIo,
    dbPath: dbPath,
  );
  final store = EventSourcingStore(
    eventStore: sembastStore,
    aggregates: $aggregateList, // Auto-generated from AggregateRoot classes
  );

  print('Creating a user...');
  final userId = const StreamId('user-001');

  ContinuumSession session = store.openSession();
  final user = await session.applyAsync<User>(
    userId,
    UserRegistered(
      userId: const UserId('user-001'),
      email: 'alice@example.com',
      name: 'Alice',
    ),
  );
  await session.saveChangesAsync();
  print('  Created: $user');
  print('  Events persisted to: $dbPath');
  print('');

  print('Loading the user (from disk)...');
  session = store.openSession();
  final loadedUser = await session.loadAsync<User>(userId);
  print('  Loaded: $loadedUser');
  print('');

  // Cleanup
  await sembastStore.closeAsync();
  storageDir.deleteSync(recursive: true);

  print('✓ SembastEventStore setup complete!');
  print('');
  print('For more examples (concurrency, atomic saves, conflict handling),');
  print('see the continuum package examples.');
}
