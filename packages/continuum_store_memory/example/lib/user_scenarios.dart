import 'package:continuum/continuum.dart';
import 'package:continuum_store_memory_example/domain/user.dart';

/// Runs the basic user lifecycle scenarios.
final class UserScenarios {
  /// Registers a new user and persists it.
  static Future<StreamId> registerUserAsync({required EventSourcingStore store}) async {
    // Keeping IDs stable makes the example output easier to follow.
    final StreamId userId = const StreamId('user-001');
    final Session session = store.openSession();

    final User user = session.startStream<User>(
      userId,
      UserRegistered(
        eventId: const EventId('evt-1'),
        userId: 'user-001',
        email: 'jane@example.com',
        name: 'Jane Doe',
      ),
    );

    await session.saveChangesAsync();

    print('User ${user.name} registered with email: ${user.email}');
    return userId;
  }

  /// Updates the user's email and persists it.
  static Future<void> updateUserEmailAsync({
    required EventSourcingStore store,
    required StreamId userId,
  }) async {
    final Session session = store.openSession();

    final User loadedUser = await session.loadAsync<User>(userId);

    session.append(
      userId,
      EmailChanged(eventId: const EventId('evt-2'), newEmail: 'jane.doe@company.com'),
    );

    await session.saveChangesAsync();

    print('Email updated to: ${loadedUser.email}');
  }

  /// Demonstrates optimistic concurrency by racing two sessions.
  static Future<void> demonstrateOptimisticConcurrencyAsync({
    required EventSourcingStore store,
    required StreamId userId,
  }) async {
    final Session adminSession = store.openSession();
    final Session userSession = store.openSession();

    // Both load the same user.
    await adminSession.loadAsync<User>(userId);
    await userSession.loadAsync<User>(userId);

    adminSession.append(
      userId,
      EmailChanged(eventId: const EventId('evt-3'), newEmail: 'admin-set@example.com'),
    );
    userSession.append(
      userId,
      EmailChanged(eventId: const EventId('evt-4'), newEmail: 'user-set@example.com'),
    );

    await adminSession.saveChangesAsync();
    print('Admin: email change saved successfully');

    try {
      await userSession.saveChangesAsync();
    } on ConcurrencyException catch (e) {
      print(
        'User: conflict detected (expected ${e.expectedVersion}, '
        'found ${e.actualVersion})',
      );
    }
  }

  /// Deactivates the user account.
  static Future<void> deactivateUserAsync({
    required EventSourcingStore store,
    required StreamId userId,
  }) async {
    final Session session = store.openSession();
    final User finalUser = await session.loadAsync<User>(userId);

    session.append(
      userId,
      UserDeactivated(
        eventId: const EventId('evt-5'),
        deactivatedAt: DateTime.now(),
        reason: 'User requested account deletion',
      ),
    );

    await session.saveChangesAsync();

    print('User active: ${finalUser.isActive}');
  }
}
