import 'package:continuum/continuum.dart';
import 'package:continuum_store_hive_example/domain/user.dart';

/// Runs the user scenarios using a persistent event store.
final class UserScenarios {
  /// Registers a user and persists the creation event.
  static Future<void> registerUserAsync({
    required EventSourcingStore store,
    required StreamId userId,
  }) async {
    final Session session = store.openSession();

    final User user = session.startStream<User>(
      userId,
      UserRegistered(
        eventId: const EventId('evt-1'),
        userId: userId.value,
        email: 'jane@example.com',
        name: 'Jane Doe',
      ),
    );

    await session.saveChangesAsync();
    print('Session 1: User ${user.name} registered with ${user.email}');
  }

  /// Loads the user and updates their email.
  static Future<void> updateEmailAsync({
    required EventSourcingStore store,
    required StreamId userId,
  }) async {
    final Session session = store.openSession();

    final User loadedUser = await session.loadAsync<User>(userId);
    print('Session 2: Loaded user ${loadedUser.name}');

    session.append(
      userId,
      EmailChanged(eventId: const EventId('evt-2'), newEmail: 'jane.doe@company.com'),
    );

    await session.saveChangesAsync();
    print('Session 2: Email updated to ${loadedUser.email}');
  }

  /// Deactivates the user account.
  static Future<void> deactivateUserAsync({
    required EventSourcingStore store,
    required StreamId userId,
  }) async {
    final Session session = store.openSession();

    final User userToDeactivate = await session.loadAsync<User>(userId);

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
  }
}
