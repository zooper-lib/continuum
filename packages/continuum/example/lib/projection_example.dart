/// Projection Example
///
/// Demonstrates using projections with code generation.
/// This example shows how to:
/// - Define a projection using `@Projection` annotation
/// - Register projections with the registry
/// - Execute inline projections after committing events
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

  // Feed committed events to projections
  await projectionExecutor.executeAsync([
    _toStoredEvent(creationEvent, streamId, version: 1),
  ]);

  // Read profile from projection
  var profile = await profileStore.loadAsync(streamId);
  print('  Profile after registration: $profile');

  // --- Update Email ---
  print('');
  print('Updating email...');

  final updateSession = store.openSession();
  await updateSession.loadAsync<User>(streamId);
  final emailEvent = EmailChanged(newEmail: 'alice@company.com');
  await updateSession.applyAsync<User>(streamId, emailEvent);
  await updateSession.saveChangesAsync();

  // Feed committed events to projections
  await projectionExecutor.executeAsync([
    _toStoredEvent(emailEvent, streamId, version: 2),
  ]);

  profile = await profileStore.loadAsync(streamId);
  print('  Profile after email change: $profile');

  // --- Deactivate User ---
  print('');
  print('Deactivating user...');

  final deactivateSession = store.openSession();
  await deactivateSession.loadAsync<User>(streamId);
  final deactivateEvent = UserDeactivated(deactivatedAt: DateTime.now());
  await deactivateSession.applyAsync<User>(streamId, deactivateEvent);
  await deactivateSession.saveChangesAsync();

  // Feed committed events to projections
  await projectionExecutor.executeAsync([
    _toStoredEvent(deactivateEvent, streamId, version: 3),
  ]);

  profile = await profileStore.loadAsync(streamId);
  print('  Profile after deactivation: $profile');

  // --- Summary ---
  print('');
  print('═══════════════════════════════════════════════════════════════════');
  print('Key Takeaways:');
  print('  1. Projections are defined with @Projection annotation');
  print('  2. Generated mixin provides type-safe apply methods');
  print('  3. Projections are decoupled from the session — feed events');
  print('     via InlineProjectionExecutor or a CommitHandler');
  print('  4. Read models are optimized for specific query patterns');
  print('═══════════════════════════════════════════════════════════════════');
}

/// Converts a [ContinuumEvent] to a [StoredEvent] for projection execution.
///
/// In production, a [CommitHandler] would handle this conversion
/// automatically. This helper is for demonstration only.
StoredEvent _toStoredEvent(
  ContinuumEvent event,
  StreamId streamId, {
  required int version,
}) {
  return StoredEvent.fromContinuumEvent(
    continuumEvent: event,
    streamId: streamId,
    version: version,
    eventType: event.runtimeType.toString(),
    data: const <String, dynamic>{},
  );
}
