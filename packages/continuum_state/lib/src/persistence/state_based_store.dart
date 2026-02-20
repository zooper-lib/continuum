import 'package:continuum/continuum.dart';
import 'package:continuum_state/src/persistence/target_persistence_adapter.dart';
import 'package:continuum_uow/continuum_uow.dart';

import 'state_based_session.dart';

/// Store implementation backed by [TargetPersistenceAdapter] instances.
///
/// Each target type is mapped to an adapter that handles fetch and
/// persist operations against a backend (REST API, GraphQL, database,
/// etc.). Uses the same [GeneratedAggregate] registries as the event
/// sourcing store for event application and entity creation.
///
/// Does not depend on event store, event serializer, or serializer
/// registry — events exist only in memory as domain objects and are
/// never serialized.
final class StateBasedStore implements SessionStore {
  /// Adapter map keyed by target type.
  final Map<Type, TargetPersistenceAdapter<Object>> _adapters;

  /// Aggregate factory registry for creating instances from events.
  final AggregateFactoryRegistry _aggregateFactories;

  /// Event applier registry for applying events to aggregates.
  final EventApplierRegistry _eventAppliers;

  /// Controls when events mutate the in-memory aggregate.
  final EventApplicationMode _applicationMode;

  /// Creates a state-based store from adapter map and generated target
  /// bundles.
  ///
  /// Pass adapters keyed by target type and all generated aggregate
  /// bundles (e.g., `$User`, `$Account`). The store merges their
  /// factory and applier registries automatically. Serializer registries
  /// from [GeneratedAggregate] are ignored — events are never serialized
  /// in state-based mode.
  ///
  /// Optionally provide an [applicationMode] to control when events
  /// mutate the in-memory aggregate. Defaults to [EventApplicationMode.eager].
  factory StateBasedStore({
    required Map<Type, TargetPersistenceAdapter<Object>> adapters,
    List<GeneratedAggregate>? targets,
    @Deprecated('Use targets instead. This alias will be removed in a future major release.') List<GeneratedAggregate>? aggregates,
    EventApplicationMode applicationMode = EventApplicationMode.eager,
  }) {
    final List<GeneratedAggregate>? resolvedTargets = targets ?? aggregates;
    if (resolvedTargets == null) {
      throw ArgumentError(
        'StateBasedStore requires either `targets` or `aggregates`.',
      );
    }
    if (targets != null && aggregates != null) {
      throw ArgumentError(
        'Provide only one of `targets` or `aggregates`.',
      );
    }

    // Merge factory and applier registries from all provided aggregates.
    // Same pattern as the event sourcing store — serializer registries
    // are ignored because state-based mode never serializes events.
    var aggregateFactories = const AggregateFactoryRegistry.empty();
    var eventAppliers = const EventApplierRegistry.empty();

    for (final target in resolvedTargets) {
      aggregateFactories = aggregateFactories.merge(target.aggregateFactories);
      eventAppliers = eventAppliers.merge(target.eventAppliers);
    }

    return StateBasedStore._(
      adapters: adapters,
      aggregateFactories: aggregateFactories,
      eventAppliers: eventAppliers,
      applicationMode: applicationMode,
    );
  }

  /// Creates a state-based store with explicit dependencies.
  StateBasedStore._({
    required Map<Type, TargetPersistenceAdapter<Object>> adapters,
    required AggregateFactoryRegistry aggregateFactories,
    required EventApplierRegistry eventAppliers,
    required EventApplicationMode applicationMode,
  }) : _adapters = adapters,
       _aggregateFactories = aggregateFactories,
       _eventAppliers = eventAppliers,
       _applicationMode = applicationMode;

  @override
  StateBasedSession openSession() {
    return StateBasedSession(
      adapters: _adapters,
      aggregateFactories: _aggregateFactories,
      eventAppliers: _eventAppliers,
      applicationMode: _applicationMode,
    );
  }
}
