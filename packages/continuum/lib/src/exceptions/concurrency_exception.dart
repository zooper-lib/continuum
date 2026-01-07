import '../identity/stream_id.dart';

/// Thrown when an optimistic concurrency conflict is detected during
/// event append operations.
///
/// This occurs when the expected version does not match the current
/// persisted stream version, indicating another process has modified
/// the stream since it was loaded.
final class ConcurrencyException implements Exception {
  /// The stream where the conflict occurred.
  final StreamId streamId;

  /// The version that was expected.
  final int expectedVersion;

  /// The actual current version of the stream.
  final int actualVersion;

  /// Creates a concurrency exception with conflict details.
  const ConcurrencyException({
    required this.streamId,
    required this.expectedVersion,
    required this.actualVersion,
  });

  @override
  String toString() =>
      'ConcurrencyException: Stream ${streamId.value} has version '
      '$actualVersion but expected $expectedVersion';
}
