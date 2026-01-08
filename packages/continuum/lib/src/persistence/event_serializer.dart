import '../events/continuum_event.dart';

/// Intermediate representation of a serialized event for persistence.
///
/// Contains the serialized form of a domain event including its
/// type discriminator and data payload.
final class SerializedEvent {
  /// Stable type discriminator for deserialization lookup.
  final String eventType;

  /// Serialized event data payload.
  final Map<String, dynamic> data;

  /// Creates a serialized event representation.
  const SerializedEvent({required this.eventType, required this.data});
}

/// Abstraction for converting domain events to/from persisted representation.
///
/// Implementations handle the serialization of specific event types
/// using their registered type discriminators.
abstract interface class EventSerializer {
  /// Serializes a continuum event to its persisted representation.
  ///
  /// Returns a [SerializedEvent] containing the type discriminator
  /// and serialized data payload.
  ///
  /// Throws if the event type is not supported for serialization.
  SerializedEvent serialize(ContinuumEvent event);

  /// Deserializes a stored event back to a continuum event.
  ///
  /// Uses the [eventType] discriminator to look up the appropriate
  /// factory and reconstruct the continuum event from [data].
  ///
  /// Throws [UnknownEventTypeException] if the event type is not registered.
  ContinuumEvent deserialize({
    required String eventType,
    required Map<String, dynamic> data,
    required Map<String, dynamic> storedMetadata,
  });
}
