import 'continuum_store.dart';
import 'event_application_mode.dart';
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
/// Implements [ContinuumStore] so it can be used interchangeably with
/// other store implementations (e.g., future state-based stores).
final class EventSourcingStore implements ContinuumStore {
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

  /// Creates an event sourcing store from generated aggregate bundles.
  ///
  /// This is the recommended constructor. Pass all your generated
  /// aggregate bundles (e.g., `$User`, `$Account`) and the store
  /// will automatically merge their registries.
  ///
  /// Optionally provide an [applicationMode] to control when events
  /// mutate the in-memory aggregate. Defaults to [EventApplicationMode.eager].
  factory EventSourcingStore({
    required EventStore eventStore,
    required List<GeneratedAggregate> aggregates,
    EventApplicationMode applicationMode = EventApplicationMode.eager,
  }) {
    // Merge all registries from the provided aggregates
    var serializerRegistry = const EventSerializerRegistry.empty();
    var aggregateFactories = const AggregateFactoryRegistry.empty();
    var eventAppliers = const EventApplierRegistry.empty();

    for (final aggregate in aggregates) {
      serializerRegistry = serializerRegistry.merge(
        aggregate.serializerRegistry,
      );
      aggregateFactories = aggregateFactories.merge(
        aggregate.aggregateFactories,
      );
      eventAppliers = eventAppliers.merge(aggregate.eventAppliers);
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
  ContinuumSession openSession() {
    return SessionImpl(
      eventStore: _eventStore,
      serializer: _serializer,
      aggregateFactories: _aggregateFactories,
      eventAppliers: _eventAppliers,
      applicationMode: _applicationMode,
    );
  }
}

/// Factory function type for creating aggregates from creation events.
typedef AggregateFactory<TAggregate> = TAggregate Function(Object event);

/// Registry of aggregate factory functions for creation dispatch.
final class AggregateFactoryRegistry {
  final Map<Type, Map<Type, AggregateFactory<Object>>> _factories;

  /// Predicate-based type matchers for sealed class / union type support.
  ///
  /// Each entry maps an aggregate type to a map of registered event types
  /// to type-check predicates. When an exact `runtimeType` match fails
  /// (e.g., because the event is a private Freezed subclass), these
  /// predicates are tried as a fallback.
  final Map<Type, Map<Type, bool Function(Object)>> _matchers;

  /// Creates an aggregate factory registry with the given mappings.
  ///
  /// The outer map key is the aggregate type, and the inner map
  /// maps event types to factory functions.
  ///
  /// Optionally provide [matchers] for sealed class / union type support.
  /// Each matcher maps an event Type to a predicate that returns true
  /// when an object is an instance of that type (including subtypes).
  /// This is needed for Freezed unions where `event.runtimeType` is a
  /// private subclass of the annotated base event type.
  const AggregateFactoryRegistry(
    this._factories, {
    Map<Type, Map<Type, bool Function(Object)>>? matchers,
  }) : _matchers = matchers ?? const {};

  /// Creates an empty aggregate factory registry.
  const AggregateFactoryRegistry.empty() : _factories = const {}, _matchers = const {};

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

    // Merge matchers
    final mergedMatchers = <Type, Map<Type, bool Function(Object)>>{};
    for (final entry in _matchers.entries) {
      mergedMatchers[entry.key] = {...entry.value};
    }
    for (final entry in other._matchers.entries) {
      if (mergedMatchers.containsKey(entry.key)) {
        mergedMatchers[entry.key]!.addAll(entry.value);
      } else {
        mergedMatchers[entry.key] = {...entry.value};
      }
    }

    return AggregateFactoryRegistry(merged, matchers: mergedMatchers);
  }

  /// Gets the factory for creating [aggregateType] from [eventType].
  ///
  /// Uses exact [Type] equality. Returns null if no factory is registered.
  /// Prefer [getFactoryForEvent] when the event may be a sealed class
  /// subtype (e.g., a Freezed union member).
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

  /// Gets the factory for creating [aggregateType] from [event],
  /// supporting sealed class hierarchies.
  ///
  /// First attempts an exact `event.runtimeType` match. When that fails,
  /// iterates over registered type-check predicates for [aggregateType]
  /// to find a match. This handles Freezed unions and sealed classes
  /// where `event.runtimeType` is a private subclass of the annotated
  /// base event type.
  AggregateFactory<TAggregate>? getFactoryForEvent<TAggregate>(
    Type aggregateType,
    Object event,
  ) {
    // Fast path: exact runtime type match.
    final exact = getFactory<TAggregate>(aggregateType, event.runtimeType);
    if (exact != null) return exact;

    // Medium path: predicate-based subtype matching (requires matchers
    // to have been provided, e.g. from regenerated code).
    final aggregateMatchers = _matchers[aggregateType];
    if (aggregateMatchers != null) {
      for (final entry in aggregateMatchers.entries) {
        if (entry.value(event)) {
          return getFactory<TAggregate>(aggregateType, entry.key);
        }
      }
    }

    // Slow path: try each registered factory for this aggregate.
    // The factory lambda already casts the event (e.g. `event as
    // FeedCreatedDomainEvent`). When the event is a sealed class
    // subtype, that cast succeeds because Dart's `as` respects
    // the inheritance hierarchy. This works even without matchers,
    // so old generated code (pre-matchers) is supported.
    return _tryEachFactory<TAggregate>(aggregateType, event);
  }

  /// Looks up a creation factory by [eventType] alone, scanning all
  /// registered aggregate types.
  ///
  /// Returns a record of the resolved aggregate [Type] and the factory,
  /// or null if no aggregate has a creation factory for this event type.
  ///
  /// This is used as a fallback when the caller does not specify a
  /// concrete aggregate type parameter (i.e. `TAggregate` is `dynamic`
  /// or `Object`).
  ({Type aggregateType, AggregateFactory<Object> factory})? getFactoryByEventType(Type eventType) {
    for (final entry in _factories.entries) {
      final factory = entry.value[eventType];
      if (factory != null) {
        return (aggregateType: entry.key, factory: factory);
      }
    }
    return null;
  }

  /// Looks up a creation factory by event instance alone, scanning all
  /// registered aggregate types. Supports sealed class hierarchies.
  ///
  /// First tries exact `event.runtimeType` match via [getFactoryByEventType].
  /// Falls back to predicate-based subtype matching across all aggregates.
  ({Type aggregateType, AggregateFactory<Object> factory})? getFactoryByEvent(
    Object event,
  ) {
    // Fast path: exact runtime type match.
    final exact = getFactoryByEventType(event.runtimeType);
    if (exact != null) return exact;

    // Medium path: predicate-based subtype matching across all aggregates.
    for (final aggEntry in _matchers.entries) {
      for (final matcherEntry in aggEntry.value.entries) {
        if (matcherEntry.value(event)) {
          final factory = _factories[aggEntry.key]?[matcherEntry.key];
          if (factory != null) {
            return (aggregateType: aggEntry.key, factory: factory);
          }
        }
      }
    }

    // Slow path: try each factory across all aggregates.
    // See [_tryEachFactory] for rationale.
    for (final aggEntry in _factories.entries) {
      for (final factoryEntry in aggEntry.value.entries) {
        try {
          // If the cast inside the factory succeeds, this is the
          // correct factory for this event subtype.
          factoryEntry.value(event);
          return (aggregateType: aggEntry.key, factory: factoryEntry.value);
          // ignore: avoid_catching_errors
        } on TypeError {
          // Cast failed — this factory does not accept this event type.
          continue;
        }
      }
    }

    return null;
  }

  /// Tries each registered factory for [aggregateType] by invoking it
  /// with [event] and catching [TypeError] from failed casts.
  ///
  /// The generated factory lambdas cast the event to the annotated base
  /// type (e.g. `event as FeedCreatedDomainEvent`). When the runtime
  /// event is a sealed class subtype (e.g. `_DirectoryFeedCreatedEvent`),
  /// the cast succeeds because Dart's type system respects inheritance.
  /// When the event is completely unrelated, the cast throws [TypeError].
  ///
  /// This provides a universal fallback that works without matchers,
  /// supporting both old generated code and manually constructed
  /// registries.
  AggregateFactory<TAggregate>? _tryEachFactory<TAggregate>(
    Type aggregateType,
    Object event,
  ) {
    final aggregateFactories = _factories[aggregateType];
    if (aggregateFactories == null) return null;

    for (final entry in aggregateFactories.entries) {
      try {
        // If the cast inside the factory succeeds, this is the
        // correct factory for this event subtype.
        entry.value(event);
        return (e) => entry.value(e) as TAggregate;
        // ignore: avoid_catching_errors
      } on TypeError {
        // Cast failed — this factory does not accept this event type.
        continue;
      }
    }

    return null;
  }

  /// Returns the registered event types for the given [aggregateType].
  ///
  /// Returns an empty list when no factories are registered for the
  /// aggregate. Used in diagnostic error messages to show what IS
  /// registered versus what was expected.
  List<Type> getRegisteredEventTypes(Type aggregateType) {
    final aggregateFactories = _factories[aggregateType];
    if (aggregateFactories == null) return const [];
    return aggregateFactories.keys.toList();
  }

  /// Returns all registered aggregate types.
  ///
  /// Used in diagnostic error messages to help the user verify which
  /// aggregates have been registered.
  List<Type> get registeredAggregateTypes => _factories.keys.toList();
}

/// Function type for applying events to aggregates.
typedef EventApplier<TAggregate> = void Function(TAggregate aggregate, Object event);

/// Registry of event applier functions for mutation dispatch.
final class EventApplierRegistry {
  final Map<Type, Map<Type, EventApplier<Object>>> _appliers;

  /// Predicate-based type matchers for sealed class / union type support.
  ///
  /// Mirrors [AggregateFactoryRegistry._matchers]. When an exact
  /// `runtimeType` match fails, these predicates are tried as a fallback.
  final Map<Type, Map<Type, bool Function(Object)>> _matchers;

  /// Creates an event applier registry with the given mappings.
  ///
  /// The outer map key is the aggregate type, and the inner map
  /// maps event types to applier functions.
  ///
  /// Optionally provide [matchers] for sealed class / union type support.
  const EventApplierRegistry(
    this._appliers, {
    Map<Type, Map<Type, bool Function(Object)>>? matchers,
  }) : _matchers = matchers ?? const {};

  /// Creates an empty event applier registry.
  const EventApplierRegistry.empty() : _appliers = const {}, _matchers = const {};

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

    // Merge matchers
    final mergedMatchers = <Type, Map<Type, bool Function(Object)>>{};
    for (final entry in _matchers.entries) {
      mergedMatchers[entry.key] = {...entry.value};
    }
    for (final entry in other._matchers.entries) {
      if (mergedMatchers.containsKey(entry.key)) {
        mergedMatchers[entry.key]!.addAll(entry.value);
      } else {
        mergedMatchers[entry.key] = {...entry.value};
      }
    }

    return EventApplierRegistry(merged, matchers: mergedMatchers);
  }

  /// Gets the applier for applying [eventType] to [aggregateType].
  ///
  /// Uses exact [Type] equality. Returns null if no applier is registered.
  /// Prefer [getApplierForEvent] when the event may be a sealed class
  /// subtype.
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

  /// Gets the applier for applying [event] to [aggregateType],
  /// supporting sealed class hierarchies.
  ///
  /// First attempts an exact `event.runtimeType` match. When that fails,
  /// iterates over registered type-check predicates for [aggregateType]
  /// to find a match.
  EventApplier<TAggregate>? getApplierForEvent<TAggregate>(
    Type aggregateType,
    Object event,
  ) {
    // Fast path: exact runtime type match.
    final exact = getApplier<TAggregate>(aggregateType, event.runtimeType);
    if (exact != null) return exact;

    // Medium path: predicate-based subtype matching.
    final aggregateMatchers = _matchers[aggregateType];
    if (aggregateMatchers != null) {
      for (final entry in aggregateMatchers.entries) {
        if (entry.value(event)) {
          return getApplier<TAggregate>(aggregateType, entry.key);
        }
      }
    }

    // Slow path: try each registered applier for this aggregate.
    // The generated applier lambda casts the event before calling the
    // apply method (e.g. `event as FeedSourceAddedDomainEvent`). When
    // the event is a sealed class subtype, that cast succeeds. We
    // return a wrapper that tries each applier and catches TypeError
    // from incompatible event casts.
    //
    // This is safe because the event cast inside the lambda executes
    // BEFORE the apply method body, so no aggregate state is mutated
    // if the cast fails.
    final aggregateAppliers = _appliers[aggregateType];
    if (aggregateAppliers == null) return null;

    // Return a wrapper applier that tries each registered applier.
    // At invocation time, the first one whose internal event cast
    // succeeds will be used.
    if (aggregateAppliers.isNotEmpty) {
      return (aggregate, evt) {
        for (final candidateApplier in aggregateAppliers.values) {
          try {
            candidateApplier(aggregate as Object, evt);
            return;
            // ignore: avoid_catching_errors
          } on TypeError {
            // The event cast inside this applier failed — try the
            // next one. No state was mutated because the cast
            // happens before the method body.
            continue;
          }
        }

        // None of the registered appliers accepted this event type.
        throw UnsupportedError(
          'No registered applier for $aggregateType accepted '
          'event of type ${evt.runtimeType}.',
        );
      };
    }

    return null;
  }
}
