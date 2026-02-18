/// Thrown when an adapter encounters a permanent backend failure.
///
/// Represents non-recoverable failures such as 400 Bad Request, 403
/// Forbidden, or validation errors. The session rethrows this immediately
/// without retrying — something is fundamentally wrong with the request.
final class PermanentAdapterException implements Exception {
  /// A human-readable description of the permanent failure.
  final String message;

  /// The underlying cause of the failure, if available.
  final Object? cause;

  /// Creates a permanent adapter exception with the given [message]
  /// and optional [cause].
  const PermanentAdapterException({required this.message, this.cause});

  @override
  String toString() => 'PermanentAdapterException: $message';
}
