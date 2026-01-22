/// Thrown when an aggregate's or projection's apply dispatcher receives
/// an event type that is not supported.
///
/// This typically indicates a programming error where an event was
/// applied to the wrong aggregate or projection type.
final class UnsupportedEventException implements Exception {
  /// The runtime type of the unsupported event.
  final Type eventType;

  /// The aggregate type that does not support this event.
  ///
  /// Null if this exception is for a projection.
  final Type? aggregateType;

  /// The projection type that does not support this event.
  ///
  /// Null if this exception is for an aggregate.
  final Type? projectionType;

  /// Creates an exception indicating [eventType] is not supported by
  /// [aggregateType].
  const UnsupportedEventException({
    required this.eventType,
    this.aggregateType,
    this.projectionType,
  }) : assert(
         aggregateType != null || projectionType != null,
         'Either aggregateType or projectionType must be provided',
       );

  @override
  String toString() {
    if (aggregateType != null) {
      return 'UnsupportedEventException: Event type $eventType is not supported '
          'by aggregate $aggregateType';
    }
    return 'UnsupportedEventException: Event type $eventType is not supported '
        'by projection $projectionType';
  }
}
