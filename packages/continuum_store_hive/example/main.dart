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
import 'package:continuum_store_hive_example/domain/user.dart';
import 'package:hive/hive.dart';

Future<EventSourcingStore> openStore(HiveEventStore hiveStore) async {
  final serializer = JsonEventSerializer(registry: $generatedEventRegistry)
    ..registerSerializer<UserRegistered>(
      eventType: 'user.registered',
      toJson: (e) => e.toJson(),
    )
    ..registerSerializer<EmailChanged>(
      eventType: 'user.email_changed',
      toJson: (e) => e.toJson(),
    )
    ..registerSerializer<UserDeactivated>(
      eventType: 'user.deactivated',
      toJson: (e) => e.toJson(),
    );

  return EventSourcingStore(
    eventStore: hiveStore,
    serializer: serializer,
    registry: $generatedEventRegistry,
    aggregateFactories: $generatedAggregateFactories,
    eventAppliers: $generatedEventAppliers,
  );
}

void main() async {
  // In a real Flutter app, use path_provider to get the documents directory
  final storageDir = Directory.systemTemp.createTempSync('user_app_');
  Hive.init(storageDir.path);

  final userId = StreamId('user-001');

  // ─────────────────────────────────────────────────────────────────────────
  // APP SESSION 1: User Registration
  // ─────────────────────────────────────────────────────────────────────────
  //
  // User opens the app and creates an account.

  var hiveStore = await HiveEventStore.openAsync(boxName: 'users');
  var store = await openStore(hiveStore);
  var session = store.openSession();

  final user = session.startStream<User>(
    userId,
    UserRegistered(
      eventId: EventId('evt-1'),
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
  store = await openStore(hiveStore);
  session = store.openSession();

  final loadedUser = await session.loadAsync<User>(userId);
  print('Session 2: Loaded user ${loadedUser.name}');

  session.append(
    userId,
    EmailChanged(eventId: EventId('evt-2'), newEmail: 'jane.doe@company.com'),
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
  store = await openStore(hiveStore);
  session = store.openSession();

  final userToDeactivate = await session.loadAsync<User>(userId);

  session.append(
    userId,
    UserDeactivated(
      eventId: EventId('evt-3'),
      deactivatedAt: DateTime.now(),
      reason: 'User requested account closure',
    ),
  );

  await session.saveChangesAsync();

  print('Session 3: User active: ${userToDeactivate.isActive}');
  print('Session 3: Deactivated at: ${userToDeactivate.deactivatedAt}');

  // The event history now shows the complete user journey:
  // 1. User registered: "Jane Doe" with jane@example.com
  // 2. Email changed to: jane.doe@company.com
  // 3. Account deactivated
  //
  // Unlike CRUD, we have the complete audit trail of all changes.

  // Cleanup
  await hiveStore.closeAsync();
  storageDir.deleteSync(recursive: true);
}
