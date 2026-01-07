/// A strongly-typed identifier for domain events.
///
/// Wraps a string value to provide type safety and prevent accidental
/// interchange with other identifier types like [StreamId].
///
/// ```dart
/// final eventId = EventId('evt_123');
/// print(eventId.value); // 'evt_123'
/// ```
final class EventId {
  /// The underlying string value of this event identifier.
  final String value;

  /// Creates an event identifier from a string [value].
  const EventId(this.value);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is EventId && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'EventId($value)';
}
