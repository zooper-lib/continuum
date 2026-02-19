import '../identity/stream_id.dart';
import 'committed_operation.dart';

/// Groups all committed operations for a single stream within a
/// [CommitBatch].
///
/// Each entry pairs a [StreamId] with its ordered list of
/// [CommittedOperation]s, preserving the association that the session
/// held during persistence.
final class CommittedEntry {
  /// The stream these operations belong to.
  final StreamId streamId;

  /// The operations committed to this stream, in application order.
  final List<CommittedOperation> operations;

  /// Creates a committed entry for the given [streamId] and
  /// [operations].
  const CommittedEntry({
    required this.streamId,
    required this.operations,
  });
}
