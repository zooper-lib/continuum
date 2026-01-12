/// Hive Event Store - Quick Start Example
///
/// This example shows the minimal setup for using HiveEventStore.
/// The Hive store provides persistent event storage that survives app restarts.
/// Ideal for:
///   - Mobile apps (Flutter) with offline-first architecture
///   - Desktop apps needing local data persistence
///   - Single-user applications
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
import 'package:continuum_store_hive/continuum_store_hive.dart';
import 'package:continuum_store_hive_example/continuum.g.dart';
import 'package:continuum_store_hive_example/domain/user.dart';
import 'package:hive/hive.dart';

void main() async {
  print('═══════════════════════════════════════════════════════════════════');
  print('HiveEventStore - Quick Start');
  print('═══════════════════════════════════════════════════════════════════');
  print('');

  // Setup: Initialize Hive
  // In a real Flutter app, use path_provider to get the documents directory
  final storageDir = Directory.systemTemp.createTempSync('continuum_example_');
  Hive.init(storageDir.path);

  // Open the Hive event store
  final hiveStore = await HiveEventStore.openAsync(boxName: 'events');
  final store = EventSourcingStore(
    eventStore: hiveStore,
    aggregates: $aggregateList, // Auto-generated from @Aggregate classes
  );

  print('Creating a user...');
  final userId = const StreamId('user-001');

  ContinuumSession session = store.openSession();
  final user = session.startStream<User>(
    userId,
    UserRegistered(
      userId: 'user-001',
      email: 'alice@example.com',
      name: 'Alice',
    ),
  );
  await session.saveChangesAsync();
  print('  Created: $user');
  print('  Events persisted to: ${storageDir.path}');
  print('');

  print('Loading the user (from disk)...');
  session = store.openSession();
  final loadedUser = await session.loadAsync<User>(userId);
  print('  Loaded: $loadedUser');
  print('');

  // Cleanup
  await hiveStore.closeAsync();
  storageDir.deleteSync(recursive: true);

  print('✓ HiveEventStore setup complete!');
  print('');
  print('For more examples (concurrency, atomic saves, conflict handling),');
  print('see the continuum package examples.');
}
