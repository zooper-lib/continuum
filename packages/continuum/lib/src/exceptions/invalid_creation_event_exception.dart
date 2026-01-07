/// Thrown when attempting to create an aggregate from an event that
/// is not a valid creation event for that aggregate.
///
/// Creation events are the first event in an aggregate's lifecycle and
/// must be explicitly marked as such through annotation configuration.
final class InvalidCreationEventException implements Exception {
  /// The runtime type of the invalid creation event.
  final Type eventType;

  /// The aggregate type that cannot be created from this event.
  final Type aggregateType;

  /// Creates an exception indicating [eventType] is not a valid creation
  /// event for [aggregateType].
  const InvalidCreationEventException({
    required this.eventType,
    required this.aggregateType,
  });

  @override
  String toString() =>
      'InvalidCreationEventException: Event type $eventType is not a valid '
      'creation event for aggregate $aggregateType';
}
