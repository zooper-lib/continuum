import 'event_store.dart';
import 'stored_event.dart';

/// Optional extension to [EventStore] for projection support.
///
/// Stores that support async projections must implement this interface
/// to allow loading events by global sequence position.
///
/// This enables the projection processor to poll for new events
/// starting from the last processed position.
abstract interface class ProjectionEventStore implements EventStore {
  /// Loads events starting from a global sequence position.
  ///
  /// Returns events with [StoredEvent.globalSequence] >= [fromGlobalSequence],
  /// ordered by global sequence, limited to [limit] events.
  ///
  /// Returns an empty list if no events exist at or after the position.
  ///
  /// This method is used by the projection processor to poll for new
  /// events to process.
  Future<List<StoredEvent>> loadEventsFromPositionAsync(
    int fromGlobalSequence,
    int limit,
  );

  /// Returns the current maximum global sequence in the store.
  ///
  /// Returns `null` if no events have been stored.
  ///
  /// Useful for determining if there are new events to process.
  Future<int?> getMaxGlobalSequenceAsync();
}
