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
import 'package:continuum_store_hive_example/continuum.g.dart';
import 'package:continuum_store_hive_example/domain/account.dart';
import 'package:continuum_store_hive_example/domain/user.dart';
import 'package:hive/hive.dart';

EventSourcingStore createStore(HiveEventStore hiveStore) {
  return EventSourcingStore(
    eventStore: hiveStore,
    aggregates: $aggregateList,
  );
}

void main() async {
  // In a real Flutter app, use path_provider to get the documents directory
  final storageDir = Directory.systemTemp.createTempSync('user_app_');
  Hive.init(storageDir.path);

  final userId = const StreamId('user-001');

  // ─────────────────────────────────────────────────────────────────────────
  // APP SESSION 1: User Registration
  // ─────────────────────────────────────────────────────────────────────────
  //
  // User opens the app and creates an account.

  var hiveStore = await HiveEventStore.openAsync(boxName: 'users');
  var store = createStore(hiveStore);
  var session = store.openSession();

  final user = session.startStream<User>(
    userId,
    UserRegistered(
      eventId: const EventId('evt-1'),
      userId: 'user-001',
      email: 'jane@example.com',
      name: 'Jane Doe',
    ),
  );

  await session.saveChangesAsync();
  print('Session 1: User ${user.name} registered with ${user.email}');

  // Simulate app close
  await hiveStore.closeAsync();

  // ─────────────────────────────────────────────────────────────────────────
  // APP SESSION 2: Profile Update (next day)
  // ─────────────────────────────────────────────────────────────────────────
  //
  // User opens the app again and updates their email.

  hiveStore = await HiveEventStore.openAsync(boxName: 'users');
  store = createStore(hiveStore);
  session = store.openSession();

  final loadedUser = await session.loadAsync<User>(userId);
  print('Session 2: Loaded user ${loadedUser.name}');

  session.append(
    userId,
    EmailChanged(eventId: const EventId('evt-2'), newEmail: 'jane.doe@company.com'),
  );

  await session.saveChangesAsync();
  print('Session 2: Email updated to ${loadedUser.email}');

  await hiveStore.closeAsync();

  // ─────────────────────────────────────────────────────────────────────────
  // APP SESSION 3: Account Deactivation (week later)
  // ─────────────────────────────────────────────────────────────────────────
  //
  // User decides to close their account.

  hiveStore = await HiveEventStore.openAsync(boxName: 'users');
  store = createStore(hiveStore);
  session = store.openSession();

  final userToDeactivate = await session.loadAsync<User>(userId);

  session.append(
    userId,
    UserDeactivated(
      eventId: const EventId('evt-3'),
      deactivatedAt: DateTime.now(),
      reason: 'User requested account closure',
    ),
  );

  await session.saveChangesAsync();

  print('Session 3: User active: ${userToDeactivate.isActive}');
  print('Session 3: Deactivated at: ${userToDeactivate.deactivatedAt}');

  await hiveStore.closeAsync();

  // ─────────────────────────────────────────────────────────────────────────
  // APP SESSION 4: Bank Account Operations (Second Aggregate)
  // ─────────────────────────────────────────────────────────────────────────
  //
  // This demonstrates working with multiple aggregate types in the same
  // event store. Each aggregate has its own stream of events.

  final accountId = const StreamId('account-001');

  hiveStore = await HiveEventStore.openAsync(boxName: 'users');
  store = createStore(hiveStore);
  session = store.openSession();

  final account = session.startStream<Account>(
    accountId,
    AccountOpened(
      eventId: const EventId('acct-evt-1'),
      accountId: 'account-001',
      ownerId: 'user-001',
    ),
  );

  await session.saveChangesAsync();
  print('Session 4: Account "${account.id}" opened for owner: ${account.ownerId}');

  await hiveStore.closeAsync();

  // ─────────────────────────────────────────────────────────────────────────
  // APP SESSION 5: Deposit and Withdraw (persistence across sessions)
  // ─────────────────────────────────────────────────────────────────────────

  hiveStore = await HiveEventStore.openAsync(boxName: 'users');
  store = createStore(hiveStore);
  session = store.openSession();

  final loadedAccount = await session.loadAsync<Account>(accountId);
  print('Session 5: Loaded account with balance: \$${loadedAccount.balance}');

  session.append(
    accountId,
    FundsDeposited(eventId: const EventId('acct-evt-2'), amount: 250),
  );
  session.append(
    accountId,
    FundsWithdrawn(eventId: const EventId('acct-evt-3'), amount: 75),
  );

  await session.saveChangesAsync();
  print('Session 5: After deposit \$250 and withdraw \$75: \$${loadedAccount.balance}');

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
