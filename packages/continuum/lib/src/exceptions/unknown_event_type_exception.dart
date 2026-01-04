/// Thrown when deserializing a stored event with a type discriminator
/// that is not registered in the event registry.
///
/// This typically indicates either a missing event type registration or
/// data corruption in the event store.
final class UnknownEventTypeException implements Exception {
  /// The unknown event type discriminator string.
  final String eventType;

  /// Creates an exception indicating [eventType] is not registered.
  const UnknownEventTypeException({required this.eventType});

  @override
  String toString() =>
      'UnknownEventTypeException: Event type "$eventType" is not registered '
      'in the event registry';
}
