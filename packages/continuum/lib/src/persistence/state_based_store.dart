import 'aggregate_persistence_adapter.dart';
import 'continuum_store.dart';
import 'event_application_mode.dart';
import 'event_serializer_registry.dart';
import 'event_sourcing_store.dart';
import 'generated_aggregate.dart';
import 'session.dart';
import 'state_based_session.dart';

/// Store implementation backed by [AggregatePersistenceAdapter] instances.
///
/// Each aggregate type is mapped to an adapter that handles fetch and
/// persist operations against a backend (REST API, GraphQL, database,
/// etc.). Uses the same [GeneratedAggregate] registries as
/// [EventSourcingStore] for event application and aggregate creation.
///
/// Does not depend on [EventStore], [EventSerializer], or
/// [EventSerializerRegistry] — events exist only in memory as domain
/// objects and are never serialized.
final class StateBasedStore implements ContinuumStore {
  /// Adapter map keyed by aggregate type.
  final Map<Type, AggregatePersistenceAdapter<Object>> _adapters;

  /// Aggregate factory registry for creating instances from events.
  final AggregateFactoryRegistry _aggregateFactories;

  /// Event applier registry for applying events to aggregates.
  final EventApplierRegistry _eventAppliers;

  /// Controls when events mutate the in-memory aggregate.
  final EventApplicationMode _applicationMode;

  /// Creates a state-based store from adapter map and generated aggregate
  /// bundles.
  ///
  /// Pass adapters keyed by aggregate type and all generated aggregate
  /// bundles (e.g., `$User`, `$Account`). The store merges their
  /// factory and applier registries automatically. Serializer registries
  /// from [GeneratedAggregate] are ignored — events are never serialized
  /// in state-based mode.
  ///
  /// Optionally provide an [applicationMode] to control when events
  /// mutate the in-memory aggregate. Defaults to [EventApplicationMode.eager].
  factory StateBasedStore({
    required Map<Type, AggregatePersistenceAdapter<Object>> adapters,
    required List<GeneratedAggregate> aggregates,
    EventApplicationMode applicationMode = EventApplicationMode.eager,
  }) {
    // Merge factory and applier registries from all provided aggregates.
    // Same pattern as EventSourcingStore — serializer registries are
    // ignored because state-based mode never serializes events.
    var aggregateFactories = const AggregateFactoryRegistry.empty();
    var eventAppliers = const EventApplierRegistry.empty();

    for (final aggregate in aggregates) {
      aggregateFactories = aggregateFactories.merge(
        aggregate.aggregateFactories,
      );
      eventAppliers = eventAppliers.merge(aggregate.eventAppliers);
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
    required Map<Type, AggregatePersistenceAdapter<Object>> adapters,
    required AggregateFactoryRegistry aggregateFactories,
    required EventApplierRegistry eventAppliers,
    required EventApplicationMode applicationMode,
  }) : _adapters = adapters,
       _aggregateFactories = aggregateFactories,
       _eventAppliers = eventAppliers,
       _applicationMode = applicationMode;

  @override
  ContinuumSession openSession() {
    return StateBasedSession(
      adapters: _adapters,
      aggregateFactories: _aggregateFactories,
      eventAppliers: _eventAppliers,
      applicationMode: _applicationMode,
    );
  }
}
