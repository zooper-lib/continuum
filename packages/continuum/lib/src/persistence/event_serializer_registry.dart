import '../events/continuum_event.dart';

/// Function type for serializing continuum events to JSON.
typedef EventToJsonFactory = Map<String, dynamic> Function(ContinuumEvent event);

/// Function type for deserializing events from JSON data.
typedef EventFromJsonFactory = ContinuumEvent Function(Map<String, dynamic> json);

/// Entry containing all serialization info for an event type.
final class EventSerializerEntry {
  /// The stable event type discriminator string.
  final String eventType;

  /// Factory to convert the event to JSON.
  final EventToJsonFactory toJson;

  /// Factory to reconstruct the event from JSON.
  final EventFromJsonFactory fromJson;

  /// Creates a serializer entry with the given configuration.
  const EventSerializerEntry({
    required this.eventType,
    required this.toJson,
    required this.fromJson,
  });
}

/// Registry mapping Dart types to their serialization configurations.
///
/// Generated code populates this registry with all discovered events.
/// Used by [JsonEventSerializer] for automatic serialization/deserialization.
final class EventSerializerRegistry {
  /// Map of Dart types to their serialization entries.
  final Map<Type, EventSerializerEntry> _entries;

  /// Predicate-based type matchers for sealed class / union type support.
  ///
  /// Maps each registered event Type to a predicate that returns true
  /// when an object is an instance of that type (including subtypes).
  /// This is needed for Freezed unions where `event.runtimeType` is a
  /// private subclass of the annotated base event type.
  final Map<Type, bool Function(Object)> _matchers;

  /// Creates a serializer registry with the given entries.
  ///
  /// Optionally provide [matchers] for sealed class / union type support.
  const EventSerializerRegistry(
    this._entries, {
    Map<Type, bool Function(Object)>? matchers,
  }) : _matchers = matchers ?? const {};

  /// Creates an empty serializer registry.
  const EventSerializerRegistry.empty() : _entries = const {}, _matchers = const {};

  /// Merges this registry with another, returning a new registry.
  ///
  /// If both registries have the same type, the [other] registry's
  /// entry takes precedence.
  EventSerializerRegistry merge(EventSerializerRegistry other) {
    return EventSerializerRegistry(
      {..._entries, ...other._entries},
      matchers: {..._matchers, ...other._matchers},
    );
  }

  /// Gets the serializer entry for a given runtime type.
  ///
  /// Returns null if no entry is registered for this type.
  EventSerializerEntry? operator [](Type type) => _entries[type];

  /// Gets the serializer entry for an event instance, supporting
  /// sealed class hierarchies.
  ///
  /// First tries exact `event.runtimeType` match. Falls back to
  /// predicate-based subtype matching for Freezed unions and sealed
  /// classes where `event.runtimeType` is a private subclass.
  EventSerializerEntry? getEntryForEvent(Object event) {
    // Fast path: exact runtime type match.
    final exact = _entries[event.runtimeType];
    if (exact != null) return exact;

    // Medium path: predicate-based subtype matching (requires matchers
    // to have been provided, e.g. from regenerated code).
    for (final entry in _matchers.entries) {
      if (entry.value(event)) {
        return _entries[entry.key];
      }
    }

    // Slow path: try each registered serializer entry.
    // The `toJson` lambda casts the event to the registered base type
    // (e.g. `event as FeedCreatedDomainEvent`). When the runtime event
    // is a sealed class subtype, that cast succeeds. When the event is
    // completely unrelated, the cast throws TypeError.
    // This works even without matchers (old generated code).
    for (final entry in _entries.entries) {
      try {
        entry.value.toJson(event as ContinuumEvent);
        return entry.value;
        // ignore: avoid_catching_errors
      } on TypeError {
        // Cast failed — this entry does not handle this event type.
        continue;
      }
    }

    return null;
  }

  /// Gets the serializer entry for a given event type discriminator.
  ///
  /// Returns null if no entry is registered for this event type.
  EventSerializerEntry? forEventType(String eventType) {
    for (final entry in _entries.values) {
      if (entry.eventType == eventType) {
        return entry;
      }
    }
    return null;
  }

  /// Checks whether a type is registered.
  bool containsType(Type type) => _entries.containsKey(type);

  /// Returns all registered types.
  Iterable<Type> get registeredTypes => _entries.keys;

  /// Returns all registered event type discriminators.
  Iterable<String> get registeredEventTypes => _entries.values.map((e) => e.eventType);
}
