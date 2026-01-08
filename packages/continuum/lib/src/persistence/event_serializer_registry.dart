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

  /// Creates a serializer registry with the given entries.
  const EventSerializerRegistry(this._entries);

  /// Creates an empty serializer registry.
  const EventSerializerRegistry.empty() : _entries = const {};

  /// Merges this registry with another, returning a new registry.
  ///
  /// If both registries have the same type, the [other] registry's
  /// entry takes precedence.
  EventSerializerRegistry merge(EventSerializerRegistry other) {
    return EventSerializerRegistry({..._entries, ...other._entries});
  }

  /// Gets the serializer entry for a given runtime type.
  ///
  /// Returns null if no entry is registered for this type.
  EventSerializerEntry? operator [](Type type) => _entries[type];

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
