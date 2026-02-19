// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: type=lint

import 'package:continuum/continuum.dart';
import 'package:continuum_event_sourcing/continuum_event_sourcing.dart';
import 'package:continuum_uow/continuum_uow.dart';

import 'abstract_interface_aggregates.dart';
import 'domain/projections/user_profile_projection.dart';
import 'domain/user.dart';

/// All discovered aggregates in this package.
///
/// Pass this list to [EventSourcingStore] for automatic
/// registration of all serializers, factories, and appliers.
final List<GeneratedAggregate> $aggregateList = [
  $AbstractUserBase,
  $User,
  $UserContract,
];

/// All discovered projections in this package.
///
/// Use this list to register all projections with the registry,
/// or use the generated [$ProjectionRegistryExtensions.registerAll] method.
final List<GeneratedProjection> $projectionList = [
  $UserProfileProjection,
];

/// Generated registration extension for all discovered projections.
///
/// Registers all projections in a single call with named parameters
/// for each projection instance and its corresponding store.
extension $ProjectionRegistryExtensions on ProjectionRegistry {
  /// Registers all discovered projections with their stores.
  ///
  /// Each projection is registered with the correct lifecycle
  /// (inline or async) and its generated [GeneratedProjection] bundle.
  void registerAll({
    required UserProfileProjection userProfileProjection,
    required ReadModelStore<UserProfile, StreamId> userProfileStore,
  }) {
    registerGeneratedInline(
      $UserProfileProjection,
      userProfileProjection,
      userProfileStore,
    );
  }
}

/// Creates a [CommitHandler] that runs all inline projections.
///
/// This is the simplest way to wire projections into a
/// [TransactionalRunner]. Internally creates a [ProjectionRegistry],
/// registers all inline projections, and wraps them in a
/// [ProjectionCommitHandler].
CommitHandler $createInlineProjectionHandler({
  required UserProfileProjection userProfileProjection,
  required ReadModelStore<UserProfile, StreamId> userProfileStore,
}) {
  final registry = ProjectionRegistry();
  registry.registerGeneratedInline(
    $UserProfileProjection,
    userProfileProjection,
    userProfileStore,
  );
  return ProjectionCommitHandler(InlineProjectionExecutor(registry: registry));
}
