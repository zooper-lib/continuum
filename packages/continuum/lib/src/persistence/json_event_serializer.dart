import '../events/domain_event.dart';
import 'event_serializer.dart';
import 'event_serializer_registry.dart';

/// JSON-based implementation of [EventSerializer].
///
/// Uses a generated [EventSerializerRegistry] for automatic
/// serialization and deserialization of domain events.
///
/// Events must have a corresponding entry in the registry, which is
/// automatically generated from `@Event` annotations.
final class JsonEventSerializer implements EventSerializer {
  final EventSerializerRegistry _registry;

  /// Creates a JSON event serializer with the given registry.
  ///
  /// The registry is typically the generated `$generatedSerializerRegistry`
  /// which contains all events discovered at compile time.
  JsonEventSerializer({required EventSerializerRegistry registry}) : _registry = registry;

  @override
  SerializedEvent serialize(DomainEvent event) {
    final entry = _registry[event.runtimeType];
    if (entry == null) {
      throw StateError(
        'No serializer registered for event type: ${event.runtimeType}. '
        'Ensure the event has an @Event annotation with a type discriminator.',
      );
    }

    final data = entry.toJson(event);

    // Include standard domain event fields
    data['eventId'] = event.eventId.value;
    data['occurredOn'] = event.occurredOn.toIso8601String();

    return SerializedEvent(eventType: entry.eventType, data: data);
  }

  @override
  DomainEvent deserialize({required String eventType, required Map<String, dynamic> data, required Map<String, dynamic> storedMetadata}) {
    final entry = _registry.forEventType(eventType);
    if (entry == null) {
      throw StateError(
        'No deserializer registered for event type: $eventType. '
        'Ensure the event has an @Event annotation with this type discriminator.',
      );
    }

    // Merge stored metadata into the data for fromJson reconstruction
    final fullData = {...data};
    if (storedMetadata.isNotEmpty) {
      fullData['metadata'] = storedMetadata;
    }

    return entry.fromJson(fullData);
  }
}
