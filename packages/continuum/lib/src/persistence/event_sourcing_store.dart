import 'event_serializer.dart';
import 'event_serializer_registry.dart';
import 'event_store.dart';
import 'generated_aggregate.dart';
import 'json_event_serializer.dart';
import 'session.dart';
import 'session_impl.dart';

/// Root object for event sourcing infrastructure.
///
/// Wires together the [EventStore] and generated aggregate registries
/// to provide a complete event sourcing runtime. Sessions are created
/// from this store to perform aggregate operations.
///
/// ```dart
/// final store = EventSourcingStore(
///   eventStore: InMemoryEventStore(),
///   aggregates: [$User, $Account],
/// );
///
/// final session = store.openSession();
/// final user = await session.loadAsync<User>(userId);
/// ```
final class EventSourcingStore {
  /// The underlying event store for persistence.
  final EventStore _eventStore;

  /// Serializer for converting events to/from stored form.
  final EventSerializer _serializer;

  /// Aggregate factory registry for creating instances from events.
  final AggregateFactoryRegistry _aggregateFactories;

  /// Event applier registry for applying events to aggregates.
  final EventApplierRegistry _eventAppliers;

  /// Creates an event sourcing store from generated aggregate bundles.
  ///
  /// This is the recommended constructor. Pass all your generated
  /// aggregate bundles (e.g., `$User`, `$Account`) and the store
  /// will automatically merge their registries.
  ///
  /// ```dart
  /// final store = EventSourcingStore(
  ///   eventStore: InMemoryEventStore(),
  ///   aggregates: [$User, $Account],
  /// );
  /// ```
  factory EventSourcingStore({
    required EventStore eventStore,
    required List<GeneratedAggregate> aggregates,
  }) {
    // Merge all registries from the provided aggregates
    var serializerRegistry = const EventSerializerRegistry.empty();
    var aggregateFactories = const AggregateFactoryRegistry.empty();
    var eventAppliers = const EventApplierRegistry.empty();

    for (final aggregate in aggregates) {
      serializerRegistry = serializerRegistry.merge(aggregate.serializerRegistry);
      aggregateFactories = aggregateFactories.merge(aggregate.aggregateFactories);
      eventAppliers = eventAppliers.merge(aggregate.eventAppliers);
    }

    return EventSourcingStore._(
      eventStore: eventStore,
      serializer: JsonEventSerializer(registry: serializerRegistry),
      aggregateFactories: aggregateFactories,
      eventAppliers: eventAppliers,
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
  }) : _eventStore = eventStore,
       _serializer = serializer,
       _aggregateFactories = aggregateFactories,
       _eventAppliers = eventAppliers;

  /// Opens a new session for aggregate operations.
  ///
  /// Each session is independent and tracks its own loaded aggregates
  /// and pending events. Sessions should be short-lived.
  Session openSession() {
    return SessionImpl(
      eventStore: _eventStore,
      serializer: _serializer,
      aggregateFactories: _aggregateFactories,
      eventAppliers: _eventAppliers,
    );
  }
}

/// Factory function type for creating aggregates from creation events.
typedef AggregateFactory<TAggregate> = TAggregate Function(Object event);

/// Registry of aggregate factory functions for creation dispatch.
final class AggregateFactoryRegistry {
  final Map<Type, Map<Type, AggregateFactory<Object>>> _factories;

  /// Creates an aggregate factory registry with the given mappings.
  ///
  /// The outer map key is the aggregate type, and the inner map
  /// maps event types to factory functions.
  const AggregateFactoryRegistry(this._factories);

  /// Creates an empty aggregate factory registry.
  const AggregateFactoryRegistry.empty() : _factories = const {};

  /// Merges this registry with another, returning a new registry.
  ///
  /// If both registries have factories for the same aggregate type,
  /// the event factories are merged (with [other] taking precedence
  /// for duplicate event types).
  AggregateFactoryRegistry merge(AggregateFactoryRegistry other) {
    final merged = <Type, Map<Type, AggregateFactory<Object>>>{};

    // Copy all from this registry
    for (final entry in _factories.entries) {
      merged[entry.key] = {...entry.value};
    }

    // Merge from other registry
    for (final entry in other._factories.entries) {
      if (merged.containsKey(entry.key)) {
        merged[entry.key]!.addAll(entry.value);
      } else {
        merged[entry.key] = {...entry.value};
      }
    }

    return AggregateFactoryRegistry(merged);
  }

  /// Gets the factory for creating [aggregateType] from [eventType].
  ///
  /// Returns null if no factory is registered for the combination.
  AggregateFactory<TAggregate>? getFactory<TAggregate>(
    Type aggregateType,
    Type eventType,
  ) {
    final aggregateFactories = _factories[aggregateType];
    if (aggregateFactories == null) return null;

    final factory = aggregateFactories[eventType];
    if (factory == null) return null;

    // Cast to the specific aggregate type
    return (event) => factory(event) as TAggregate;
  }
}

/// Function type for applying events to aggregates.
typedef EventApplier<TAggregate> = void Function(TAggregate aggregate, Object event);

/// Registry of event applier functions for mutation dispatch.
final class EventApplierRegistry {
  final Map<Type, Map<Type, EventApplier<Object>>> _appliers;

  /// Creates an event applier registry with the given mappings.
  ///
  /// The outer map key is the aggregate type, and the inner map
  /// maps event types to applier functions.
  const EventApplierRegistry(this._appliers);

  /// Creates an empty event applier registry.
  const EventApplierRegistry.empty() : _appliers = const {};

  /// Merges this registry with another, returning a new registry.
  ///
  /// If both registries have appliers for the same aggregate type,
  /// the event appliers are merged (with [other] taking precedence
  /// for duplicate event types).
  EventApplierRegistry merge(EventApplierRegistry other) {
    final merged = <Type, Map<Type, EventApplier<Object>>>{};

    // Copy all from this registry
    for (final entry in _appliers.entries) {
      merged[entry.key] = {...entry.value};
    }

    // Merge from other registry
    for (final entry in other._appliers.entries) {
      if (merged.containsKey(entry.key)) {
        merged[entry.key]!.addAll(entry.value);
      } else {
        merged[entry.key] = {...entry.value};
      }
    }

    return EventApplierRegistry(merged);
  }

  /// Gets the applier for applying [eventType] to [aggregateType].
  ///
  /// Returns null if no applier is registered for the combination.
  EventApplier<TAggregate>? getApplier<TAggregate>(
    Type aggregateType,
    Type eventType,
  ) {
    final aggregateAppliers = _appliers[aggregateType];
    if (aggregateAppliers == null) return null;

    final applier = aggregateAppliers[eventType];
    if (applier == null) return null;

    // Cast to the specific aggregate type by wrapping with proper Object cast
    return (aggregate, event) => applier(aggregate as Object, event);
  }
}
