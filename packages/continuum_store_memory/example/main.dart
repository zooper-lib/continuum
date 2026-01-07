/// In-Memory Event Store - Testing & Prototyping
///
/// The in-memory store is perfect for:
///   - Unit and integration tests (fast, isolated, no cleanup needed)
///   - Rapid prototyping during development
///   - Scenarios where events don't need to survive app restarts
///
/// To run this example:
///   cd example
///   dart pub get
///   dart run build_runner build
///   dart run main.dart
library;

import 'package:continuum/continuum.dart';
import 'package:continuum_store_memory/continuum_store_memory.dart';
import 'package:continuum_store_memory_example/account_scenarios.dart';
import 'package:continuum_store_memory_example/atomic_scenarios.dart';
import 'package:continuum_store_memory_example/continuum.g.dart';
import 'package:continuum_store_memory_example/user_scenarios.dart';

void main() async {
  // ─────────────────────────────────────────────────────────────────────────
  // SETUP: Configure the Event Store.
  // ─────────────────────────────────────────────────────────────────────────
  //
  // The generator auto-discovers all @Aggregate classes and creates
  // $aggregateList. Add new aggregates anywhere - no changes needed here!

  final store = EventSourcingStore(
    eventStore: InMemoryEventStore(),
    aggregates: $aggregateList,
  );

  final StreamId userId = await UserScenarios.registerUserAsync(store: store);
  await UserScenarios.updateUserEmailAsync(store: store, userId: userId);
  await UserScenarios.demonstrateOptimisticConcurrencyAsync(store: store, userId: userId);
  await UserScenarios.deactivateUserAsync(store: store, userId: userId);

  final StreamId accountId = await AccountScenarios.runAccountLifecycleAsync(
    store: store,
    ownerId: userId.value,
  );

  await AtomicScenarios.runAtomicMultiStreamSaveAsync(
    store: store,
    userId: userId,
    accountId: accountId,
  );
  await AtomicScenarios.runAtomicMultiStreamRollbackOnConflictAsync(
    store: store,
    userId: userId,
    accountId: accountId,
  );
}
