import '../identity/stream_id.dart';
import 'event_store.dart';
import 'expected_version.dart';
import 'stored_event.dart';

/// A batch of events to append to a single stream.
///
/// Used by [AtomicEventStore] to append events to multiple streams atomically.
final class StreamAppendBatch {
  /// The optimistic concurrency expectation for the target stream.
  final ExpectedVersion expectedVersion;

  /// The events to append to the target stream.
  ///
  /// Events are expected to have sequential versions for that stream.
  final List<StoredEvent> events;

  /// Creates a batch append request for a single stream.
  const StreamAppendBatch({
    required this.expectedVersion,
    required this.events,
  });
}

/// Optional extension to [EventStore] for atomic multi-stream writes.
///
/// The base [EventStore] API only supports appending to a single stream at a
/// time. That means a session saving changes across multiple streams cannot be
/// truly all-or-nothing without store support.
///
/// Stores which can provide transactional/atomic semantics across multiple
/// streams SHOULD implement this interface.
abstract interface class AtomicEventStore implements EventStore {
  /// Appends events to multiple streams atomically.
  ///
  /// Implementations MUST guarantee that either:
  /// - all stream appends succeed, or
  /// - none of them are persisted.
  ///
  /// Implementations MUST perform optimistic concurrency checks using each
  /// [StreamAppendBatch.expectedVersion].
  Future<void> appendEventsToStreamsAsync(
    Map<StreamId, StreamAppendBatch> batches,
  );
}
