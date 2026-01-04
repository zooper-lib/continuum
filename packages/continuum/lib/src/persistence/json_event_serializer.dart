import '../events/domain_event.dart';
import 'event_registry.dart';
import 'event_serializer.dart';

/// JSON-based implementation of [EventSerializer].
///
/// Uses a registry of `toJson` functions to serialize domain events
/// and the [EventRegistry] for deserialization.
///
/// Each event must have a corresponding serializer registered via
/// [registerSerializer] or through the constructor.
final class JsonEventSerializer implements EventSerializer {
  final EventRegistry _registry;
  final Map<Type, _EventSerializerEntry> _serializers;

  /// Creates a JSON event serializer with the given registry.
  ///
  /// The [serializers] map provides the toJson and type discriminator
  /// for each event type.
  JsonEventSerializer({
    required EventRegistry registry,
    Map<Type, _EventSerializerEntry>? serializers,
  }) : _registry = registry,
       _serializers = serializers ?? {};

  /// Registers a serializer for an event type.
  ///
  /// The [toJson] function converts the event to a JSON-compatible map.
  /// The [eventType] is the stable type discriminator string.
  void registerSerializer<TEvent extends DomainEvent>({
    required String eventType,
    required Map<String, dynamic> Function(TEvent event) toJson,
  }) {
    _serializers[TEvent] = _EventSerializerEntry(
      eventType: eventType,
      toJson: (event) => toJson(event as TEvent),
    );
  }

  @override
  SerializedEvent serialize(DomainEvent event) {
    final entry = _serializers[event.runtimeType];
    if (entry == null) {
      throw StateError('No serializer registered for event type: ${event.runtimeType}. '
          'Register a serializer using registerSerializer<${event.runtimeType}>().');
    }

    final data = entry.toJson(event);

    // Include standard domain event fields
    data['eventId'] = event.eventId.value;
    data['occurredOn'] = event.occurredOn.toIso8601String();

    return SerializedEvent(eventType: entry.eventType, data: data);
  }

  @override
  DomainEvent deserialize({
    required String eventType,
    required Map<String, dynamic> data,
    required Map<String, dynamic> storedMetadata,
  }) {
    // Merge stored metadata into the data for fromJson reconstruction
    final fullData = {...data};
    if (storedMetadata.isNotEmpty) {
      fullData['metadata'] = storedMetadata;
    }

    return _registry.fromStored(eventType, fullData);
  }
}

/// Internal entry for event serialization configuration.
final class _EventSerializerEntry {
  final String eventType;
  final Map<String, dynamic> Function(DomainEvent event) toJson;

  const _EventSerializerEntry({required this.eventType, required this.toJson});
}
