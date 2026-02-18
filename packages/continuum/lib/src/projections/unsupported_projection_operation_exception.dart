/// Thrown when a projection receives an operation type it does not handle.
///
/// This indicates a programming error where an operation was routed to a
/// projection that has no handler for that type. Check the projection's
/// [handledEventTypes] and ensure only matching operations are dispatched.
final class UnsupportedProjectionOperationException implements Exception {
  /// The runtime type of the unsupported operation.
  final Type operationType;

  /// The projection type that does not support this operation.
  final Type projectionType;

  /// Creates an exception indicating [operationType] is not handled
  /// by [projectionType].
  const UnsupportedProjectionOperationException({
    required this.operationType,
    required this.projectionType,
  });

  @override
  String toString() =>
      'UnsupportedProjectionOperationException: Operation type '
      '$operationType is not handled by projection $projectionType';
}
