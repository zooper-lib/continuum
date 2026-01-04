import 'event_registry.dart';
import 'event_serializer.dart';
import 'event_store.dart';
import 'session.dart';
import 'session_impl.dart';

/// Root object for event sourcing infrastructure.
///
/// Wires together the [EventStore], [EventSerializer], and [EventRegistry]
/// to provide a complete event sourcing runtime. Sessions are created from
/// this store to perform aggregate operations.
///
/// ```dart
/// final store = EventSourcingStore(
///   eventStore: InMemoryEventStore(),
///   serializer: JsonEventSerializer(registry),
///   registry: generatedEventRegistry,
/// );
///
/// final session = store.openSession();
/// final cart = await session.loadAsync<ShoppingCart>(cartId);
/// ```
final class EventSourcingStore {
  /// The underlying event store for persistence.
  final EventStore _eventStore;

  /// Serializer for converting events to/from stored form.
  final EventSerializer _serializer;

  /// Registry for deserializing events by type.
  final EventRegistry _registry;

  /// Aggregate factory registry for creating instances from events.
  final AggregateFactoryRegistry _aggregateFactories;

  /// Event applier registry for applying events to aggregates.
  final EventApplierRegistry _eventAppliers;

  /// Creates an event sourcing store with the required dependencies.
  ///
  /// The [eventStore] provides persistence, [serializer] handles
  /// serialization, and [registry] enables deserialization lookup.
  ///
  /// The [aggregateFactories] and [eventAppliers] are typically generated
  /// and provide the type-safe machinery for aggregate operations.
  EventSourcingStore({
    required EventStore eventStore,
    required EventSerializer serializer,
    required EventRegistry registry,
    required AggregateFactoryRegistry aggregateFactories,
    required EventApplierRegistry eventAppliers,
  }) : _eventStore = eventStore,
       _serializer = serializer,
       _registry = registry,
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
      registry: _registry,
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
typedef EventApplier<TAggregate> =
    void Function(TAggregate aggregate, Object event);

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
