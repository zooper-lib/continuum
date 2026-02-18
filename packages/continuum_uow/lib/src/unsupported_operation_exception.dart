/// Thrown when no applier or factory is registered for an operation type.
///
/// This typically indicates a programming error where an operation was
/// applied to the wrong aggregate type or the registries are
/// incomplete.
final class UnsupportedOperationException implements Exception {
  /// The runtime type of the unsupported operation.
  final Type operationType;

  /// The aggregate type that does not support this operation.
  final Type aggregateType;

  /// Creates an exception indicating [operationType] is not supported
  /// by [aggregateType].
  const UnsupportedOperationException({
    required this.operationType,
    required this.aggregateType,
  });

  @override
  String toString() =>
      'UnsupportedOperationException: Operation type $operationType '
      'is not supported by aggregate $aggregateType';
}
