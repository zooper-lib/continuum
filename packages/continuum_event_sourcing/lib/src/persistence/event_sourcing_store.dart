import 'package:continuum/continuum.dart';
import 'package:continuum_uow/continuum_uow.dart';

import 'event_serializer.dart';
import 'event_store.dart';
import 'json_event_serializer.dart';
import 'session_impl.dart';

/// Root object for event sourcing infrastructure.
///
/// Wires together the [EventStore] and generated aggregate registries
/// to provide a complete event sourcing runtime. Sessions are created
/// from this store to perform aggregate operations.
///
/// Implements [SessionStore] from the UoW layer so it can be used
/// interchangeably with other store implementations.
final class EventSourcingStore implements SessionStore {
  /// The underlying event store for persistence.
  final EventStore _eventStore;

  /// Serializer for converting events to/from stored form.
  final EventSerializer _serializer;

  /// Aggregate factory registry for creating instances from events.
  final AggregateFactoryRegistry _aggregateFactories;

  /// Event applier registry for applying events to aggregates.
  final EventApplierRegistry _eventAppliers;

  /// Controls when events mutate the in-memory aggregate.
  final EventApplicationMode _applicationMode;

  /// Creates an event sourcing store from generated target bundles.
  ///
  /// This is the recommended constructor. Pass all your generated
  /// target bundles (e.g., `$User`, `$Account`) and the store
  /// will automatically merge their registries.
  ///
  /// Optionally provide an [applicationMode] to control when events
  /// mutate the in-memory aggregate. Defaults to [EventApplicationMode.eager].
  factory EventSourcingStore({
    required EventStore eventStore,
    List<GeneratedAggregate>? targets,
    @Deprecated('Use targets instead. This alias will be removed in a future major release.') List<GeneratedAggregate>? aggregates,
    EventApplicationMode applicationMode = EventApplicationMode.eager,
  }) {
    final List<GeneratedAggregate>? resolvedTargets = targets ?? aggregates;
    if (resolvedTargets == null) {
      throw ArgumentError(
        'EventSourcingStore requires either `targets` or `aggregates`.',
      );
    }
    if (targets != null && aggregates != null) {
      throw ArgumentError(
        'Provide only one of `targets` or `aggregates`.',
      );
    }

    // Merge all registries from the provided targets.
    var serializerRegistry = const EventSerializerRegistry.empty();
    var aggregateFactories = const AggregateFactoryRegistry.empty();
    var eventAppliers = const EventApplierRegistry.empty();

    for (final target in resolvedTargets) {
      serializerRegistry = serializerRegistry.merge(
        target.serializerRegistry,
      );
      aggregateFactories = aggregateFactories.merge(
        target.aggregateFactories,
      );
      eventAppliers = eventAppliers.merge(target.eventAppliers);
    }

    return EventSourcingStore._(
      eventStore: eventStore,
      serializer: JsonEventSerializer(registry: serializerRegistry),
      aggregateFactories: aggregateFactories,
      eventAppliers: eventAppliers,
      applicationMode: applicationMode,
    );
  }

  /// Creates an event sourcing store with explicit dependencies.
  ///
  /// Use this constructor when you need custom serialization or
  /// want to manually configure the registries.
  EventSourcingStore._({
    required EventStore eventStore,
    required EventSerializer serializer,
    required AggregateFactoryRegistry aggregateFactories,
    required EventApplierRegistry eventAppliers,
    required EventApplicationMode applicationMode,
  }) : _eventStore = eventStore,
       _serializer = serializer,
       _aggregateFactories = aggregateFactories,
       _eventAppliers = eventAppliers,
       _applicationMode = applicationMode;

  @override
  SessionImpl openSession() {
    return SessionImpl(
      eventStore: _eventStore,
      serializer: _serializer,
      aggregateFactories: _aggregateFactories,
      eventAppliers: _eventAppliers,
      applicationMode: _applicationMode,
    );
  }
}
