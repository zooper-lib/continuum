import 'package:continuum/continuum.dart';

import 'event_serializer.dart';

/// JSON-based implementation of [EventSerializer].
///
/// Uses a generated [EventSerializerRegistry] for automatic
/// serialization and deserialization of domain events.
///
/// Events must have a corresponding entry in the registry, which is
/// automatically generated from `@AggregateEvent` annotations.
final class JsonEventSerializer implements EventSerializer {
  /// The registry of serializer entries for event type resolution.
  final EventSerializerRegistry _registry;

  /// Creates a JSON event serializer with the given registry.
  JsonEventSerializer({required EventSerializerRegistry registry}) : _registry = registry;

  @override
  SerializedEvent serialize(ContinuumEvent event) {
    // Use predicate-based lookup to support sealed class hierarchies.
    final entry = _registry.getEntryForEvent(event);
    if (entry == null) {
      throw StateError(
        'No serializer registered for event type: ${event.runtimeType}. '
        'Ensure the event has an @AggregateEvent annotation with a type discriminator.',
      );
    }

    final data = <String, dynamic>{...entry.toJson(event)};

    // Include standard domain event fields
    data['eventId'] = event.id.value;
    data['occurredOn'] = event.occurredOn.toIso8601String();

    return SerializedEvent(eventType: entry.eventType, data: data);
  }

  @override
  ContinuumEvent deserialize({
    required String eventType,
    required Map<String, dynamic> data,
    required Map<String, dynamic> storedMetadata,
  }) {
    final entry = _registry.forEventType(eventType);
    if (entry == null) {
      throw StateError(
        'No deserializer registered for event type: $eventType. '
        'Ensure the event has an @AggregateEvent annotation with this type discriminator.',
      );
    }

    final fullData = {...data, 'metadata': storedMetadata};

    return entry.fromJson(fullData);
  }
}
