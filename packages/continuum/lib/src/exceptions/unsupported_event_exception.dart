/// Thrown when an aggregate's apply dispatcher receives an event type
/// that is not supported by the aggregate.
///
/// This typically indicates a programming error where an event was
/// applied to the wrong aggregate type.
final class UnsupportedEventException implements Exception {
  /// The runtime type of the unsupported event.
  final Type eventType;

  /// The aggregate type that does not support this event.
  final Type aggregateType;

  /// Creates an exception indicating [eventType] is not supported by
  /// [aggregateType].
  const UnsupportedEventException({
    required this.eventType,
    required this.aggregateType,
  });

  @override
  String toString() =>
      'UnsupportedEventException: Event type $eventType is not supported '
      'by aggregate $aggregateType';
}
