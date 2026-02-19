/// Thrown when an adapter encounters a transient backend failure.
///
/// Represents recoverable failures such as network timeouts, 503 Service
/// Unavailable responses, or rate limit errors. The session rethrows this
/// immediately without retrying — the caller decides whether to retry the
/// whole workflow.
final class TransientAdapterException implements Exception {
  /// A human-readable description of the transient failure.
  final String message;

  /// The underlying cause of the failure, if available.
  final Object? cause;

  /// Creates a transient adapter exception with the given [message]
  /// and optional [cause].
  const TransientAdapterException({required this.message, this.cause});

  @override
  String toString() => 'TransientAdapterException: $message';
}
