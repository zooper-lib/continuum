import '../identity/stream_id.dart';
import 'expected_version.dart';
import 'stored_event.dart';

/// Low-level abstraction for event persistence operations.
///
/// Implementations provide the actual storage mechanism for events,
/// whether in-memory, file-based, or database-backed.
///
/// All operations are asynchronous to support various storage backends.
abstract interface class EventStore {
  /// Loads all events for a stream, ordered by version.
  ///
  /// Returns an empty list if the stream does not exist.
  /// Events are guaranteed to be ordered by their per-stream version.
  Future<List<StoredEvent>> loadStreamAsync(StreamId streamId);

  /// Appends events to a stream with optimistic concurrency control.
  ///
  /// The [expectedVersion] is checked against the stream's current version.
  /// If they don't match, a [ConcurrencyException] is thrown.
  ///
  /// For new streams, use [ExpectedVersion.noStream].
  /// For existing streams, use [ExpectedVersion.exact(currentVersion)].
  ///
  /// Throws [ConcurrencyException] if the expected version doesn't match.
  Future<void> appendEventsAsync(
    StreamId streamId,
    ExpectedVersion expectedVersion,
    List<StoredEvent> events,
  );
}
