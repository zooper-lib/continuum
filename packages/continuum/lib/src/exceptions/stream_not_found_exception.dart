import '../identity/stream_id.dart';

/// Thrown when attempting to load a stream that does not exist.
///
/// This indicates either an incorrect stream ID or that the aggregate
/// has not yet been created.
final class StreamNotFoundException implements Exception {
  /// The stream that was not found.
  final StreamId streamId;

  /// Creates an exception indicating [streamId] does not exist.
  const StreamNotFoundException({required this.streamId});

  @override
  String toString() => 'StreamNotFoundException: Stream ${streamId.value} does not exist';
}
