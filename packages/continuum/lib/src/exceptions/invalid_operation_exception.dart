/// Thrown when an operation is logically invalid given the current state.
///
/// For example, applying a creation event to a stream that is already
/// tracked in the session. This represents a programming error where the
/// caller is performing an operation that violates domain invariants.
final class InvalidOperationException implements Exception {
  /// A human-readable description of why the operation is invalid.
  final String message;

  /// Creates an invalid operation exception with the given [message].
  const InvalidOperationException({required this.message});

  @override
  String toString() => 'InvalidOperationException: $message';
}
