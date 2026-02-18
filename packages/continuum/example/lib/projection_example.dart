/// Projection Example
///
/// Demonstrates using projections with code generation.
/// This example shows how to:
/// - Define a projection using `@Projection` annotation
/// - Register projections with the registry
/// - Wire the framework-provided [ProjectionCommitHandler] so projections
///   update automatically on every commit
library;

import 'package:continuum/continuum.dart';
import 'package:continuum_event_sourcing/continuum_event_sourcing.dart';
import 'package:continuum_store_memory/continuum_store_memory.dart';
import 'package:continuum_uow/continuum_uow.dart';

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

  // Create read model store for profiles.
  final profileStore = InMemoryReadModelStore<UserProfile, StreamId>();

  // Create projection registry and register our projection.
  // The generated registerAll extension wires all discovered
  // projections in a single type-safe call.
  final registry = ProjectionRegistry();
  registry.registerAll(
    userProfileProjection: UserProfileProjection(),
    userProfileStore: profileStore,
  );

  // Create the inline projection executor.
  final projectionExecutor = InlineProjectionExecutor(registry: registry);

  // Create event sourcing store.
  final store = EventSourcingStore(
    eventStore: InMemoryEventStore(),
    aggregates: $aggregateList,
  );

  // Wire everything together with TransactionalRunner.
  // The framework-provided ProjectionCommitHandler bridges the executor
  // into the commit handler contract — no hand-written adapter needed.
  //
  // For multiple commit handlers (e.g., projections + event bus + analytics),
  // use CompositeCommitHandler:
  //   final handler = CompositeCommitHandler([
  //     ProjectionCommitHandler(executor: projectionExecutor),
  //     EventBusCommitHandler(eventBus),
  //     AnalyticsCommitHandler(analytics),
  //   ]);
  final runner = TransactionalRunner(
    store: store,
    commitHandler: ProjectionCommitHandler(projectionExecutor),
  );

  final streamId = const StreamId('user-123');
  final userId = const UserId('user-123');

  // --- Create User ---
  print('');
  print('Creating user...');

  await runner.runAsync(() async {
    final session = TransactionalRunner.currentSession;
    await session.applyAsync<User>(
      streamId,
      UserRegistered(
        userId: userId,
        email: 'alice@example.com',
        name: 'Alice Smith',
      ),
    );
  });

  // The projection was updated automatically during the commit.
  var profile = await profileStore.loadAsync(streamId);
  print('  Profile after registration: $profile');

  // --- Update Email ---
  print('');
  print('Updating email...');

  await runner.runAsync(() async {
    final session = TransactionalRunner.currentSession;
    await session.loadAsync<User>(streamId);
    await session.applyAsync<User>(
      streamId,
      EmailChanged(newEmail: 'alice@company.com', userId: userId),
    );
  });

  profile = await profileStore.loadAsync(streamId);
  print('  Profile after email change: $profile');

  // --- Deactivate User ---
  print('');
  print('Deactivating user...');

  await runner.runAsync(() async {
    final session = TransactionalRunner.currentSession;
    await session.loadAsync<User>(streamId);
    await session.applyAsync<User>(
      streamId,
      UserDeactivated(deactivatedAt: DateTime.now(), userId: userId),
    );
  });

  profile = await profileStore.loadAsync(streamId);
  print('  Profile after deactivation: $profile');

  // --- Summary ---
  print('');
  print('═══════════════════════════════════════════════════════════════════');
  print('Key Takeaways:');
  print('  1. Projections are defined with @Projection annotation');
  print('  2. Generated mixin provides type-safe apply methods');
  print('  3. Generated registerAll wires all projections in one call');
  print('  4. Framework-provided ProjectionCommitHandler bridges the');
  print('     executor into the commit lifecycle — no adapters needed');
  print('  5. SingleStreamProjection no longer requires extractKey');
  print('═══════════════════════════════════════════════════════════════════');
}
