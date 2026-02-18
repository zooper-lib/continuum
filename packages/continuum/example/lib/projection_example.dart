/// Projection Example
///
/// Demonstrates using projections with code generation.
/// This example shows how to:
/// - Define a projection using `@Projection` annotation
/// - Register projections with the registry
/// - Execute inline projections after committing events
library;

import 'package:continuum/continuum.dart';
import 'package:continuum_event_sourcing/continuum_event_sourcing.dart';
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

  // Create the inline projection executor
  final projectionExecutor = InlineProjectionExecutor(registry: registry);

  // Create event sourcing store
  final store = EventSourcingStore(
    eventStore: InMemoryEventStore(),
    aggregates: $aggregateList,
  );

  final streamId = const StreamId('user-123');
  final userId = const UserId('user-123');

  // --- Create User via Events ---
  print('');
  print('Creating user via events...');

  final session = store.openSession();
  final creationEvent = UserRegistered(
    userId: userId,
    email: 'alice@example.com',
    name: 'Alice Smith',
  );
  await session.applyAsync<User>(streamId, creationEvent);
  await session.saveChangesAsync();

  // Feed committed operations to projections
  await projectionExecutor.executeAsync([creationEvent]);

  // Read profile from projection
  var profile = await profileStore.loadAsync(streamId);
  print('  Profile after registration: $profile');

  // --- Update Email ---
  print('');
  print('Updating email...');

  final updateSession = store.openSession();
  await updateSession.loadAsync<User>(streamId);
  final emailEvent = EmailChanged(newEmail: 'alice@company.com', userId: userId);
  await updateSession.applyAsync<User>(streamId, emailEvent);
  await updateSession.saveChangesAsync();

  // Feed committed operations to projections
  await projectionExecutor.executeAsync([emailEvent]);

  profile = await profileStore.loadAsync(streamId);
  print('  Profile after email change: $profile');

  // --- Deactivate User ---
  print('');
  print('Deactivating user...');

  final deactivateSession = store.openSession();
  await deactivateSession.loadAsync<User>(streamId);
  final deactivateEvent = UserDeactivated(
    deactivatedAt: DateTime.now(),
    userId: userId,
  );
  await deactivateSession.applyAsync<User>(streamId, deactivateEvent);
  await deactivateSession.saveChangesAsync();

  // Feed committed operations to projections
  await projectionExecutor.executeAsync([deactivateEvent]);

  profile = await profileStore.loadAsync(streamId);
  print('  Profile after deactivation: $profile');

  // --- Summary ---
  print('');
  print('═══════════════════════════════════════════════════════════════════');
  print('Key Takeaways:');
  print('  1. Projections are defined with @Projection annotation');
  print('  2. Generated mixin provides type-safe apply methods');
  print('  3. Projections work with Operation — decoupled from event');
  print('     sourcing infrastructure. Feed events directly via');
  print('     InlineProjectionExecutor or a CommitHandler');
  print('  4. Read models are optimized for specific query patterns');
  print('═══════════════════════════════════════════════════════════════════');
}
