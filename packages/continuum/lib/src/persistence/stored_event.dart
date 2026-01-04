import '../events/domain_event.dart';
import '../identity/event_id.dart';
import '../identity/stream_id.dart';

/// Represents a persisted domain event with storage metadata.
///
/// Contains both the domain data and storage-specific information
/// like version numbers and serialized payload.
final class StoredEvent {
  /// Unique identifier for this event instance.
  final EventId eventId;

  /// The stream (aggregate instance) this event belongs to.
  final StreamId streamId;

  /// The per-stream sequential version number.
  ///
  /// Versions are strictly sequential starting at 0 with no gaps.
  final int version;

  /// Stable type discriminator for deserialization.
  final String eventType;

  /// Serialized event data payload.
  final Map<String, dynamic> data;

  /// The timestamp when this event occurred.
  final DateTime occurredOn;

  /// Optional metadata associated with this event.
  final Map<String, dynamic> metadata;

  /// Optional global sequence number across all streams.
  ///
  /// Used for ordered event projections and subscriptions.
  final int? globalSequence;

  /// Creates a stored event with all persistence metadata.
  const StoredEvent({
    required this.eventId,
    required this.streamId,
    required this.version,
    required this.eventType,
    required this.data,
    required this.occurredOn,
    required this.metadata,
    this.globalSequence,
  });

  /// Creates a stored event from a domain event with additional metadata.
  ///
  /// The [domainEvent] provides base event data, while [streamId], [version],
  /// [eventType], and [data] provide persistence-specific information.
  factory StoredEvent.fromDomainEvent({
    required DomainEvent domainEvent,
    required StreamId streamId,
    required int version,
    required String eventType,
    required Map<String, dynamic> data,
    int? globalSequence,
  }) {
    return StoredEvent(
      eventId: domainEvent.eventId,
      streamId: streamId,
      version: version,
      eventType: eventType,
      data: data,
      occurredOn: domainEvent.occurredOn,
      metadata: domainEvent.metadata,
      globalSequence: globalSequence,
    );
  }
}
