/// Hive Event Store - Local Persistence for Mobile & Desktop
///
/// The Hive store provides persistent event storage that survives app restarts.
/// Ideal for:
///   - Mobile apps (Flutter) with offline-first architecture
///   - Desktop apps needing local data persistence
///   - Single-user applications
///
/// To run this example:
///   cd example
///   dart pub get
///   dart run build_runner build
///   dart run main.dart
library;

import 'dart:io';

import 'package:continuum/continuum.dart';
import 'package:continuum_store_hive/continuum_store_hive.dart';
import 'package:continuum_store_hive_example/account_scenarios.dart';
import 'package:continuum_store_hive_example/atomic_scenarios.dart';
import 'package:continuum_store_hive_example/store_factory.dart';
import 'package:continuum_store_hive_example/user_scenarios.dart';
import 'package:hive/hive.dart';

void main() async {
  // In a real Flutter app, use path_provider to get the documents directory
  final storageDir = Directory.systemTemp.createTempSync('user_app_');
  Hive.init(storageDir.path);

  final userId = const StreamId('user-001');
  final accountId = const StreamId('account-001');

  // ─────────────────────────────────────────────────────────────────────────
  // APP SESSION 1: User Registration
  // ─────────────────────────────────────────────────────────────────────────
  //
  // User opens the app and creates an account.

  var hiveStore = await HiveEventStore.openAsync(boxName: 'users');
  var store = createStore(hiveStore: hiveStore);
  await UserScenarios.registerUserAsync(store: store, userId: userId);

  // Simulate app close
  await hiveStore.closeAsync();

  // ─────────────────────────────────────────────────────────────────────────
  // APP SESSION 2: Profile Update (next day)
  // ─────────────────────────────────────────────────────────────────────────
  //
  // User opens the app again and updates their email.

  hiveStore = await HiveEventStore.openAsync(boxName: 'users');
  store = createStore(hiveStore: hiveStore);
  await UserScenarios.updateEmailAsync(store: store, userId: userId);

  await hiveStore.closeAsync();

  // ─────────────────────────────────────────────────────────────────────────
  // APP SESSION 3: Account Deactivation (week later)
  // ─────────────────────────────────────────────────────────────────────────
  //
  // User decides to close their account.

  hiveStore = await HiveEventStore.openAsync(boxName: 'users');
  store = createStore(hiveStore: hiveStore);
  await UserScenarios.deactivateUserAsync(store: store, userId: userId);

  await hiveStore.closeAsync();

  // ─────────────────────────────────────────────────────────────────────────
  // APP SESSION 4: Bank Account Operations (Second Aggregate)
  // ─────────────────────────────────────────────────────────────────────────
  //
  // This demonstrates working with multiple aggregate types in the same
  // event store. Each aggregate has its own stream of events.

  hiveStore = await HiveEventStore.openAsync(boxName: 'users');
  store = createStore(hiveStore: hiveStore);
  await AccountScenarios.openAccountAsync(
    store: store,
    accountId: accountId,
    ownerId: userId.value,
  );

  await hiveStore.closeAsync();

  // ─────────────────────────────────────────────────────────────────────────
  // APP SESSION 5: Deposit and Withdraw (persistence across sessions)
  // ─────────────────────────────────────────────────────────────────────────

  hiveStore = await HiveEventStore.openAsync(boxName: 'users');
  store = createStore(hiveStore: hiveStore);
  await AccountScenarios.depositAndWithdrawAsync(store: store, accountId: accountId);

  // ─────────────────────────────────────────────────────────────────────────
  // APP SESSION 6: Atomic Multi-Stream Save (User + Account)
  // ─────────────────────────────────────────────────────────────────────────
  //
  // One session can stage changes to multiple streams and persist them as a
  // single atomic unit.

  await AtomicScenarios.runAtomicSaveAsync(
    store: store,
    userId: userId,
    accountId: accountId,
  );

  // ─────────────────────────────────────────────────────────────────────────
  // APP SESSION 7: Atomic Multi-Stream Rollback on Conflict
  // ─────────────────────────────────────────────────────────────────────────
  //
  // If any stream in the staged changes has a concurrency conflict, NONE of
  // the streams are persisted.

  await AtomicScenarios.runRollbackOnConflictAsync(
    store: store,
    userId: userId,
    accountId: accountId,
  );

  // The event history now shows the complete user journey:
  // 1. User registered: "Jane Doe" with jane@example.com
  // 2. Email changed to: jane.doe@company.com
  // 3. Account deactivated
  // 4. Bank account opened
  // 5. Funds deposited and withdrawn
  //
  // Unlike CRUD, we have the complete audit trail of all changes.

  // Cleanup
  await hiveStore.closeAsync();
  storageDir.deleteSync(recursive: true);
}
