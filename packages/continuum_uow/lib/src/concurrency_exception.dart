import 'package:continuum/continuum.dart';

/// Thrown when an optimistic concurrency conflict is detected during
/// save operations.
///
/// This occurs when the expected version does not match the current
/// persisted version, indicating another process has modified the
/// stream since it was loaded.
final class ConcurrencyException implements Exception {
  /// The stream where the conflict occurred.
  final StreamId streamId;

  /// The version that was expected.
  final int expectedVersion;

  /// The actual current version of the stream.
  final int actualVersion;

  /// A human-readable description of the conflict.
  final String message;

  /// Creates a concurrency exception with conflict details.
  ///
  /// If [message] is not provided, a default message is generated
  /// from the [streamId], [expectedVersion], and [actualVersion].
  ConcurrencyException({
    required this.streamId,
    required this.expectedVersion,
    required this.actualVersion,
    String? message,
  }) : message =
           message ??
           'Stream ${streamId.value} has version '
               '$actualVersion but expected $expectedVersion';

  @override
  String toString() => 'ConcurrencyException: $message';
}
