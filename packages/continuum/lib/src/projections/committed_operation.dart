import '../operations/operation.dart';

/// Pairs a domain [Operation] with optional persistence metadata.
///
/// Carries the operation itself plus store-specific context such as
/// stream version and global sequence. State-based stores leave the
/// optional fields null; event-sourcing stores populate them.
final class CommittedOperation {
  /// The domain operation that was committed.
  final Operation operation;

  /// The stream-local version assigned by an event-sourcing store.
  ///
  /// Null for state-based stores that do not track per-stream versions.
  final int? streamVersion;

  /// The store-wide global sequence number.
  ///
  /// Null when the store does not support global ordering.
  final int? globalSequence;

  /// Creates a committed operation with the given [operation] and
  /// optional persistence metadata.
  const CommittedOperation({
    required this.operation,
    this.streamVersion,
    this.globalSequence,
  });
}
