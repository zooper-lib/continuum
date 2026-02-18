/// Projection Example
///
/// Demonstrates using projections with code generation.
/// This example shows how to:
/// - Define a projection using `@Projection` annotation
/// - Register projections with the registry
/// - Wire the projection executor as a CommitHandler so projections
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
  final registry = ProjectionRegistry();
  registry.registerInline(
    UserProfileProjection(),
    profileStore,
  );

  // Create the inline projection executor.
  final projectionExecutor = InlineProjectionExecutor(registry: registry);

  // Create event sourcing store.
  final store = EventSourcingStore(
    eventStore: InMemoryEventStore(),
    aggregates: $aggregateList,
  );

  // Wire everything together with TransactionalRunner.
  // The projection commit handler is called automatically after every
  // successful commit — no manual executor calls needed.
  //
  // For multiple commit handlers (e.g., projections + event bus + analytics),
  // use the framework-provided CompositeCommitHandler:
  //   final handler = CompositeCommitHandler([
  //     _ProjectionCommitHandler(projectionExecutor),
  //     EventBusCommitHandler(eventBus),
  //     AnalyticsCommitHandler(analytics),
  //   ]);
  final runner = TransactionalRunner(
    store: store,
    commitHandler: _ProjectionCommitHandler(projectionExecutor),
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
  print('  3. Wire InlineProjectionExecutor as a CommitHandler so');
  print('     projections update automatically — no manual calls');
  print('  4. Read models are optimized for specific query patterns');
  print('═══════════════════════════════════════════════════════════════════');
}

/// Bridges [InlineProjectionExecutor] into the [CommitHandler] contract.
///
/// The executor lives in `continuum` (L0) and cannot depend on
/// `continuum_uow` (L1) where [CommitHandler] is defined. This adapter
/// closes the gap at the application wiring layer.
final class _ProjectionCommitHandler implements CommitHandler {
  /// The executor to delegate committed operations to.
  final InlineProjectionExecutor _executor;

  /// Creates a commit handler that delegates to [executor].
  _ProjectionCommitHandler(this._executor);

  @override
  Future<void> onCommitAsync(List<Operation> committedOperations) async {
    await _executor.executeAsync(committedOperations);
  }
}
