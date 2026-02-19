import '../operations/operation.dart';
import 'committed_entry.dart';

/// The full set of operations persisted by a single transaction,
/// grouped by stream.
///
/// Produced by [Session.saveChangesAsync] and consumed by
/// [CommitHandler.onCommitAsync] and [InlineProjectionExecutor].
/// Preserves the [StreamId] → [Operation] association that exists
/// during persistence, so post-commit consumers (projections, event
/// bus, analytics) receive full stream context without requiring
/// operations to carry identity themselves.
final class CommitBatch {
  /// The committed entries grouped by stream, in the order the
  /// session iterated its tracked entities.
  final List<CommittedEntry> entries;

  /// Creates a commit batch from the given [entries].
  const CommitBatch({required this.entries});

  /// An empty commit batch with no entries.
  static const CommitBatch empty = CommitBatch(entries: []);

  /// Whether this batch contains no committed entries.
  bool get isEmpty => entries.isEmpty;

  /// Whether this batch contains at least one committed entry.
  bool get isNotEmpty => entries.isNotEmpty;

  /// All operations across all entries as a flat list, preserving
  /// per-stream and per-operation ordering.
  ///
  /// Useful for consumers that do not need stream context and just
  /// want the bare [Operation] instances in commit order.
  List<Operation> get flatOperations => [
    for (final entry in entries)
      for (final committedOp in entry.operations) committedOp.operation,
  ];
}
