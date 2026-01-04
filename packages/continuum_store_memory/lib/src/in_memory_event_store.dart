import 'package:continuum/continuum.dart';

/// In-memory implementation of [EventStore].
///
/// Stores events in memory, suitable for testing and development.
/// Events are lost when the store instance is garbage collected.
///
/// Thread-safety: This implementation is not thread-safe. For concurrent
/// access, external synchronization is required.
final class InMemoryEventStore implements EventStore {
  /// Internal storage of events by stream ID.
  final Map<StreamId, List<StoredEvent>> _streams = {};

  /// Global sequence counter for optional global ordering.
  int _globalSequence = 0;

  @override
  Future<List<StoredEvent>> loadStreamAsync(StreamId streamId) async {
    // Return a copy of the events to prevent external modification
    final events = _streams[streamId];
    if (events == null) {
      return [];
    }
    return List.unmodifiable(events);
  }

  @override
  Future<void> appendEventsAsync(StreamId streamId, ExpectedVersion expectedVersion, List<StoredEvent> events) async {
    // Get or create the stream
    final stream = _streams[streamId] ?? [];
    final currentVersion = stream.isEmpty ? -1 : stream.last.version;

    // Check expected version for optimistic concurrency
    if (expectedVersion.isNoStream) {
      // Expecting a new stream - current version should be -1
      if (stream.isNotEmpty) {
        throw ConcurrencyException(streamId: streamId, expectedVersion: -1, actualVersion: currentVersion);
      }
    } else {
      // Expecting a specific version
      if (currentVersion != expectedVersion.value) {
        throw ConcurrencyException(streamId: streamId, expectedVersion: expectedVersion.value, actualVersion: currentVersion);
      }
    }

    // Assign sequential versions and global sequence numbers
    final newEvents = <StoredEvent>[];
    var nextVersion = currentVersion + 1;

    for (final event in events) {
      // Create a new StoredEvent with proper versioning
      newEvents.add(
        StoredEvent(
          eventId: event.eventId,
          streamId: streamId,
          version: nextVersion,
          eventType: event.eventType,
          data: event.data,
          occurredOn: event.occurredOn,
          metadata: event.metadata,
          globalSequence: _globalSequence++,
        ),
      );
      nextVersion++;
    }

    // Store the events
    if (_streams.containsKey(streamId)) {
      _streams[streamId]!.addAll(newEvents);
    } else {
      _streams[streamId] = newEvents;
    }
  }

  /// Clears all events from the store.
  ///
  /// Useful for resetting state between tests.
  void clear() {
    _streams.clear();
    _globalSequence = 0;
  }

  /// Returns the number of streams in the store.
  int get streamCount => _streams.length;

  /// Returns the total number of events across all streams.
  int get eventCount => _streams.values.fold(0, (sum, events) => sum + events.length);
}
