/// Projection Example
///
/// Demonstrates using projections with code generation.
/// This example shows how to:
/// - Define a projection using `@Projection` annotation
/// - Register projections with the registry
/// - Use inline projections for strongly consistent reads
library;

import 'package:continuum/continuum.dart';
import 'package:continuum_store_memory/continuum_store_memory.dart';

import 'continuum.g.dart';
import 'domain/events/email_changed.dart';
import 'domain/events/user_deactivated.dart';
import 'domain/events/user_registered.dart';
import 'domain/projections/user_profile_projection.dart';
import 'domain/user.dart';

void main() async {
  print('═══════════════════════════════════════════════════════════════════');
  print('Projection Example');
  print('═══════════════════════════════════════════════════════════════════');
  print('');

  // --- Setup ---
  print('Setting up event store and projections...');

  // Create read model store for profiles
  final profileStore = InMemoryReadModelStore<UserProfile, StreamId>();

  // Create projection registry and register our projection
  final registry = ProjectionRegistry();
  registry.registerInline(
    UserProfileProjection(),
    profileStore,
  );

  // Create event sourcing store with projections
  final store = EventSourcingStore(
    eventStore: InMemoryEventStore(),
    aggregates: $aggregateList,
    projections: registry,
  );

  final userId = const StreamId('user-123');

  // --- Create User via Events ---
  print('');
  print('Creating user via events...');

  final session = store.openSession();
  session.startStream<User>(
    userId,
    UserRegistered(
      userId: userId.value,
      email: 'alice@example.com',
      name: 'Alice Smith',
    ),
  );
  await session.saveChangesAsync();

  // Read profile from projection (inline = always up to date)
  var profile = await profileStore.loadAsync(userId);
  print('  Profile after registration: $profile');

  // --- Update Email ---
  print('');
  print('Updating email...');

  final updateSession = store.openSession();
  await updateSession.loadAsync<User>(userId);
  updateSession.append(
    userId,
    EmailChanged(newEmail: 'alice@company.com'),
  );
  await updateSession.saveChangesAsync();

  profile = await profileStore.loadAsync(userId);
  print('  Profile after email change: $profile');

  // --- Deactivate User ---
  print('');
  print('Deactivating user...');

  final deactivateSession = store.openSession();
  await deactivateSession.loadAsync<User>(userId);
  deactivateSession.append(
    userId,
    UserDeactivated(deactivatedAt: DateTime.now()),
  );
  await deactivateSession.saveChangesAsync();

  profile = await profileStore.loadAsync(userId);
  print('  Profile after deactivation: $profile');

  // --- Summary ---
  print('');
  print('═══════════════════════════════════════════════════════════════════');
  print('Key Takeaways:');
  print('  1. Projections are defined with @Projection annotation');
  print('  2. Generated mixin provides type-safe apply methods');
  print('  3. Inline projections update atomically with event writes');
  print('  4. Read models are optimized for specific query patterns');
  print('═══════════════════════════════════════════════════════════════════');
}
