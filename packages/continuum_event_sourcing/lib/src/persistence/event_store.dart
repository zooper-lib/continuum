import 'package:continuum/continuum.dart';

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
  /// The [aggregateType] is persisted as stream metadata, enabling
  /// [getStreamIdsByAggregateTypeAsync] queries. The value should be the
  /// Dart `Type.toString()` of the aggregate.
  ///
  /// Throws [ConcurrencyException] if the expected version doesn't match.
  Future<void> appendEventsAsync(
    StreamId streamId,
    ExpectedVersion expectedVersion,
    List<StoredEvent> events, {
    required String aggregateType,
  });

  /// Returns all stream IDs that are tagged with the given [aggregateType].
  ///
  /// The [aggregateType] is the Dart `Type.toString()` value that was
  /// passed to [appendEventsAsync] or [AtomicEventStore.appendEventsToStreamsAsync]
  /// when events were first persisted for a stream.
  ///
  /// Returns an empty list if no streams match. Streams that have been
  /// soft-deleted via [softDeleteStreamAsync] are excluded.
  Future<List<StreamId>> getStreamIdsByAggregateTypeAsync(
    String aggregateType,
  );

  /// Marks a stream as deleted using a tombstone flag in stream
  /// metadata.
  ///
  /// The events remain in the store but the stream is treated as
  /// non-existent: [loadStreamAsync] returns an empty list and
  /// [getStreamIdsByAggregateTypeAsync] excludes it.
  ///
  /// Must be idempotent — soft-deleting a non-existent or already
  /// deleted stream is a no-op.
  Future<void> softDeleteStreamAsync(StreamId streamId);
}
