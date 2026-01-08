import '../events/continuum_event.dart';
import '../exceptions/unknown_event_type_exception.dart';

/// Factory function type for deserializing events from JSON data.
typedef EventFactory = ContinuumEvent Function(Map<String, dynamic> json);

/// Registry mapping stable event type strings to deserialization factories.
///
/// Generated code populates this registry with all discovered events
/// that have type discriminators defined.
///
/// The registry is used during event loading to reconstruct domain
/// events from their serialized form.
final class EventRegistry {
  /// Map of event type discriminators to factory functions.
  final Map<String, EventFactory> _factories;

  /// Creates an event registry with the given factory mappings.
  const EventRegistry(this._factories);

  /// Creates an empty event registry.
  const EventRegistry.empty() : _factories = const {};

  /// Merges this registry with another, returning a new registry.
  ///
  /// If both registries have the same event type, the [other] registry's
  /// factory takes precedence.
  EventRegistry merge(EventRegistry other) {
    return EventRegistry({..._factories, ...other._factories});
  }

  /// Deserializes a stored event from its type and data.
  ///
  /// Throws [UnknownEventTypeException] if the event type is not registered.
  ContinuumEvent fromStored(String eventType, Map<String, dynamic> data) {
    final factory = _factories[eventType];
    if (factory == null) {
      throw UnknownEventTypeException(eventType: eventType);
    }
    return factory(data);
  }

  /// Checks whether an event type is registered.
  bool containsType(String eventType) => _factories.containsKey(eventType);

  /// Returns all registered event types.
  Iterable<String> get registeredTypes => _factories.keys;
}
